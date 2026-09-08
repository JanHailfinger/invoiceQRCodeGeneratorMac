import Foundation
import Observation

/// Settings: model in UserDefaults, API key in the keychain.
@MainActor
@Observable
final class AppSettings {

    static let shared = AppSettings()

    static let defaultModel = "gpt-5-mini"

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Keys.model) }
    }

    /// Prefilled into "note to payee" (EPC field 12).
    var beneficiaryHint: String {
        didSet { UserDefaults.standard.set(beneficiaryHint, forKey: Keys.hint) }
    }

    /// Put the payload on the clipboard right after extraction.
    var copyPayloadAutomatically: Bool {
        didSet { UserDefaults.standard.set(copyPayloadAutomatically, forKey: Keys.autoCopy) }
    }

    var apiKey: String {
        didSet { KeychainStore.write(apiKey) }
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    /// The language the model should write its warnings in, named in English so the
    /// prompt stays unambiguous ("German", "English", ...).
    var warningLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? "English"
    }

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
