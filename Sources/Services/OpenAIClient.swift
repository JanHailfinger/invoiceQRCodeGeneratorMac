import Foundation
import UniformTypeIdentifiers

/// Ruft die OpenAI Responses API mit der Rechnung als `input_file`/`input_image` auf.
/// Bei PDFs zieht die API serverseitig Text **und** Seitenbilder – Scans funktionieren dadurch mit.
struct OpenAIClient: Sendable {

    enum Failure: LocalizedError {
        case missingAPIKey
        case unreadableFile(URL)
        case unsupportedType(String)
        case fileTooLarge(bytes: Int)
        case http(status: Int, message: String)
        case incompleteResponse(String)
        case noStructuredOutput
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "Kein OpenAI-API-Key hinterlegt. Einstellungen öffnen (⌘,) und Key eintragen."
            case let .unreadableFile(url):
                "Datei nicht lesbar: \(url.lastPathComponent)"
            case let .unsupportedType(type):
                "Dateityp wird nicht unterstützt: \(type)"
            case let .fileTooLarge(bytes):
                "Datei ist \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) groß – Limit sind 30 MB."
            case let .http(status, message):
                "OpenAI-Fehler \(status): \(message)"
            case let .incompleteResponse(reason):
                "Antwort abgebrochen: \(reason)"
            case .noStructuredOutput:
                "Antwort enthielt keine JSON-Ausgabe."
            case let .decoding(message):
                "Antwort nicht auswertbar: \(message)"
            }
        }
    }

    static let maximumFileBytes = 30 * 1024 * 1024

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Extraktion

    func extract(fileURL: URL, model: String, apiKey: String) async throws -> InvoiceExtraction {
        guard !apiKey.isEmpty else { throw Failure.missingAPIKey }

        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            throw Failure.unreadableFile(fileURL)
        }
        guard data.count <= Self.maximumFileBytes else { throw Failure.fileTooLarge(bytes: data.count) }

        let contentItem = try Self.inputItem(for: fileURL, data: data)
        let body: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": InvoiceExtraction.systemPrompt],
                ["role": "user", "content": [
                    contentItem,
                    ["type": "input_text", "text": "Extrahiere die Zahlungsdaten aus dieser Rechnung."],
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

    /// Modelliste des Accounts – füllt den Picker in den Einstellungen.
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
                ?? "keine Details"
            throw Failure.http(status: status, message: message)
        }
        return json
    }

    // MARK: - Payload-Bau

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

    /// Responses API liefert `output` als Array; die JSON-Ausgabe steckt im Message-Item als `output_text`.
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
            // Refusal statt Ausgabe – mit Begründung weitermelden.
            for part in content where part["type"] as? String == "refusal" {
                throw Failure.incompleteResponse(part["refusal"] as? String ?? "Modell hat abgelehnt.")
            }
        }
        throw Failure.noStructuredOutput
    }
}
