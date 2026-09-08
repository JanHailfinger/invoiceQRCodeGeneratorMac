import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {

    static let shared = AppModel()

    enum Status: Equatable {
        case idle
        case extracting(fileName: String)
        case ready
        case failed(String)
    }

    // MARK: - Zustand

    var status: Status = .idle
    var sourceURL: URL?
    var extraction: InvoiceExtraction?

    /// Bearbeitbare Felder – der QR-Code hängt live daran.
    var beneficiaryName = ""
    var ibanText = ""
    var bicText = ""
    var amountText = ""
    var remittanceText = ""
    var referenceText = ""
    var purposeCode = ""
    var beneficiaryHint = ""

    var payload: EPCPayload {
        EPCPayload(.init(
            beneficiaryName: beneficiaryName,
            iban: ibanText,
            bic: bicText,
            amount: Amount.parse(amountText),
            purposeCode: purposeCode,
            structuredReference: referenceText,
            unstructuredRemittance: remittanceText,
            beneficiaryToOriginator: beneficiaryHint
        ))
    }

    var isBusy: Bool {
        if case .extracting = status { return true }
        return false
    }

    /// Warnungen des Modells plus Hinweis zur Zahlungsart und zu Fremdwährungen.
    var advisories: [String] {
        var result: [String] = []
        if let mode = extraction?.paymentMode.warning { result.append(mode) }
        if let currency = extraction?.currency?.uppercased(), !currency.isEmpty, currency != "EUR" {
            result.append("Rechnung lautet auf \(currency). GiroCode überträgt ausschließlich EUR – Betrag prüfen.")
        }
        result.append(contentsOf: extraction?.warnings ?? [])
        return result
    }

    static let supportedTypes: [UTType] = [.pdf, .png, .jpeg, .heic, .tiff]

    private let client = OpenAIClient()
    private var currentTask: Task<Void, Never>?

    private init() {}

    // MARK: - Ablauf

    func canHandle(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return Self.supportedTypes.contains { type.conforms(to: $0) }
    }

    func handle(urls: [URL]) {
        guard let url = urls.first(where: canHandle) else {
            if let rejected = urls.first {
                status = .failed("\(rejected.lastPathComponent) ist kein PDF und kein Bild.")
            }
            return
        }
        load(url)
    }

    func load(_ url: URL) {
        currentTask?.cancel()
        sourceURL = url
        extraction = nil
        clearFields()
        status = .extracting(fileName: url.lastPathComponent)
        activateWindow()

        let settings = AppSettings.shared
        let model = settings.model
        let apiKey = settings.apiKey
        let client = client

        currentTask = Task { [weak self] in
            do {
                let result = try await client.extract(fileURL: url, model: model, apiKey: apiKey)
                guard !Task.isCancelled else { return }
                self?.apply(result)
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed(error.localizedDescription)
            }
        }
    }

    func retry() {
        guard let sourceURL else { return }
        load(sourceURL)
    }

    func reset() {
        currentTask?.cancel()
        currentTask = nil
        sourceURL = nil
        extraction = nil
        clearFields()
        status = .idle
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.supportedTypes
        panel.allowsMultipleSelection = false
        panel.prompt = "Auslesen"
        panel.message = "Rechnung als PDF oder Bild auswählen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    // MARK: - Ausgabe

    func copyPayload() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload.text, forType: .string)
    }

    func copyQRImage() {
        guard let image = QRGenerator.image(for: payload.text) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    func saveQRImage() {
        guard let data = QRGenerator.pngData(for: payload.text) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    func revealSource() {
        guard let sourceURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([sourceURL])
    }

    func openSource() {
        guard let sourceURL else { return }
        NSWorkspace.shared.open(sourceURL)
    }

    private var suggestedFileName: String {
        let base = extraction?.invoiceNumber?.replacingOccurrences(of: "/", with: "-")
            ?? sourceURL?.deletingPathExtension().lastPathComponent
            ?? "Zahlung"
        return "QR-\(base).png"
    }

    // MARK: - Intern

    private func apply(_ result: InvoiceExtraction) {
        extraction = result
        beneficiaryName = result.creditorName ?? ""
        ibanText = IBAN.display(result.iban ?? "")
        bicText = BIC.normalized(result.bic ?? "")

        if let amount = Amount.parse(result.amount) {
            amountText = Amount.display(amount)
        } else {
            amountText = ""
        }

        // Strukturierte Referenz und Verwendungszweck schließen sich in EPC069-12 aus.
        let reference = result.creditorReference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if reference.uppercased().hasPrefix("RF") {
            referenceText = reference
            remittanceText = ""
        } else {
            referenceText = ""
            remittanceText = result.remittanceText ?? result.invoiceNumber ?? ""
        }

        beneficiaryHint = AppSettings.shared.beneficiaryHint
        status = .ready

        if AppSettings.shared.copyPayloadAutomatically, payload.isUsable {
            copyPayload()
        }
    }

    private func clearFields() {
        beneficiaryName = ""
        ibanText = ""
        bicText = ""
        amountText = ""
        remittanceText = ""
        referenceText = ""
        purposeCode = ""
        beneficiaryHint = ""
    }

    private func activateWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: \.isVisible)?.makeKeyAndOrderFront(nil)
    }
}
