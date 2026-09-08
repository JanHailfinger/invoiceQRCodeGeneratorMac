import Foundation
import Observation

/// Einstellungen: Modell in UserDefaults, API-Key im Schlüsselbund.
@MainActor
@Observable
final class AppSettings {

    static let shared = AppSettings()

    static let defaultModel = "gpt-5-mini"

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }

    /// Zusatz, der als "Hinweis an Empfänger" (EPC-Feld 12) vorbelegt wird.
    var beneficiaryHint: String {
        didSet { UserDefaults.standard.set(beneficiaryHint, forKey: Keys.hint) }
    }

    /// QR gleich nach der Extraktion in die Zwischenablage legen.
    var copyPayloadAutomatically: Bool {
        didSet { UserDefaults.standard.set(copyPayloadAutomatically, forKey: Keys.autoCopy) }
    }

    var apiKey: String {
        didSet { KeychainStore.write(apiKey) }
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    private init() {
        let defaults = UserDefaults.standard
        model = defaults.string(forKey: Keys.model) ?? Self.defaultModel
        beneficiaryHint = defaults.string(forKey: Keys.hint) ?? ""
        copyPayloadAutomatically = defaults.bool(forKey: Keys.autoCopy)
        apiKey = KeychainStore.read() ?? ""
    }

    private enum Keys {
        static let model = "openai.model"
        static let hint = "epc.beneficiaryHint"
        static let autoCopy = "qr.autoCopyPayload"
    }
}
