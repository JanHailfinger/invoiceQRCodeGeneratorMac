import Foundation
import UniformTypeIdentifiers

/// Calls the OpenAI Responses API with the invoice as `input_file` / `input_image`.
/// For PDFs the API extracts text *and* page images server side, so scans work without local OCR.
struct OpenAIClient: Sendable {

    enum Failure: LocalizedError {
        case missingAPIKey
        case unreadableFile(String)
        case unsupportedType(String)
        case fileTooLarge(bytes: Int)
        case http(status: Int, message: String)
        case incompleteResponse(String)
        case noStructuredOutput
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                NSLocalizedString("No OpenAI API key stored. Open Settings (⌘,) and enter one.", comment: "Error")
            case let .unreadableFile(name):
                String(format: NSLocalizedString("Cannot read file: %@", comment: "Error"), name)
            case let .unsupportedType(type):
                String(format: NSLocalizedString("Unsupported file type: %@", comment: "Error"), type)
            case let .fileTooLarge(bytes):
                String(
                    format: NSLocalizedString("File is %@, the limit is 30 MB.", comment: "Error"),
                    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
                )
            case let .http(status, message):
                String(format: NSLocalizedString("OpenAI error %1$ld: %2$@", comment: "Error"), status, message)
            case let .incompleteResponse(reason):
                String(format: NSLocalizedString("Response was cut short: %@", comment: "Error"), reason)
            case .noStructuredOutput:
                NSLocalizedString("The response contained no JSON output.", comment: "Error")
            case let .decoding(message):
                String(format: NSLocalizedString("Response could not be parsed: %@", comment: "Error"), message)
            }
        }
    }

    static let maximumFileBytes = 30 * 1024 * 1024

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Extraction

    func extract(fileURL: URL, model: String, apiKey: String, warningLanguage: String) async throws -> InvoiceExtraction {
        guard !apiKey.isEmpty else { throw Failure.missingAPIKey }

        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            throw Failure.unreadableFile(fileURL.lastPathComponent)
        }
        guard data.count <= Self.maximumFileBytes else { throw Failure.fileTooLarge(bytes: data.count) }

        let contentItem = try Self.inputItem(for: fileURL, data: data)
        let body: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": InvoiceExtraction.systemPrompt(warningLanguage: warningLanguage)],
                ["role": "user", "content": [
                    contentItem,
                    ["type": "input_text", "text": "Extract the payment details from this invoice."],
                ]],
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "invoice_payment_data",
                    "strict": true,
                    "schema": InvoiceExtraction.jsonSchema,
                ],
            ],
        ]

        let json = try await post(body: body, path: "responses", apiKey: apiKey)
        let outputText = try Self.structuredOutput(from: json)

        do {
            return try JSONDecoder().decode(InvoiceExtraction.self, from: Data(outputText.utf8))
        } catch {
            throw Failure.decoding(error.localizedDescription)
        }
    }

    /// The account's model list, used to fill the picker in Settings.
    func availableModels(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw Failure.missingAPIKey }
        let json = try await get(path: "models", apiKey: apiKey)
        let entries = json["data"] as? [[String: Any]] ?? []
        return entries
            .compactMap { $0["id"] as? String }
            .filter { $0.hasPrefix("gpt-") || $0.hasPrefix("o1") || $0.hasPrefix("o3") || $0.hasPrefix("o4") }
            .filter { id in !["-audio", "-realtime", "-tts", "-transcribe", "-search", "-image"].contains(where: id.contains) }
            .sorted()
    }

    // MARK: - Transport

    private func post(body: [String: Any], path: String, apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 180
        return try await send(request)
    }

    private func get(path: String, apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/\(path)")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        guard (200..<300).contains(status) else {
            let message = (json["error"] as? [String: Any])?["message"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? NSLocalizedString("no details", comment: "Error detail fallback")
            throw Failure.http(status: status, message: message)
        }
        return json
    }

    // MARK: - Request payload

    private static func inputItem(for url: URL, data: Data) throws -> [String: Any] {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        let base64 = data.base64EncodedString()

        if type?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            return [
                "type": "input_file",
                "filename": url.lastPathComponent,
                "file_data": "data:application/pdf;base64,\(base64)",
                "detail": "high",
            ]
        }

        if let type, type.conforms(to: .image), let mime = type.preferredMIMEType {
            return [
                "type": "input_image",
                "image_url": "data:\(mime);base64,\(base64)",
                "detail": "high",
            ]
        }

        throw Failure.unsupportedType(type?.identifier ?? url.pathExtension)
    }

    /// The Responses API returns `output` as an array; the JSON sits in the message item
    /// as an `output_text` part. There is no top-level `output_text` field in the raw API.
    private static func structuredOutput(from json: [String: Any]) throws -> String {
        if let status = json["status"] as? String, status != "completed" {
            let reason = (json["incomplete_details"] as? [String: Any])?["reason"] as? String ?? status
            if status == "incomplete" || status == "failed" { throw Failure.incompleteResponse(reason) }
        }

        let output = json["output"] as? [[String: Any]] ?? []
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content where part["type"] as? String == "output_text" {
                if let text = part["text"] as? String, !text.isEmpty { return text }
            }
            // A refusal replaces the output; pass its reason through.
            for part in content where part["type"] as? String == "refusal" {
                throw Failure.incompleteResponse(
                    part["refusal"] as? String
                        ?? NSLocalizedString("The model declined.", comment: "Error")
                )
            }
        }
        throw Failure.noStructuredOutput
    }
}
