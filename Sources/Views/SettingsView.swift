import SwiftUI

struct SettingsView: View {

    @Environment(AppSettings.self) private var settings

    @State private var availableModels: [String] = []
    @State private var loadState: LoadState = .idle

    private enum LoadState: Equatable {
        case idle, loading, failed(String), loaded(Int)
    }

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API-Key", text: Binding(
                    get: { settings.apiKey },
                    set: { settings.apiKey = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                ))
                .textContentType(.password)
                Text("Wird im Schlüsselbund gespeichert, nicht in den Einstellungen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Modell", text: Binding(
                        get: { settings.model },
                        set: { settings.model = $0.trimmingCharacters(in: .whitespaces) }
                    ))
                    .font(.system(.body, design: .monospaced))

                    Button("Modelle laden") { loadModels() }
                        .disabled(!settings.hasAPIKey || loadState == .loading)
                }

                if !availableModels.isEmpty {
                    Picker("Verfügbar", selection: Binding(
                        get: { settings.model },
                        set: { settings.model = $0 }
                    )) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                switch loadState {
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Modelle werden abgerufen …").font(.caption)
                    }
                case let .failed(message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                case let .loaded(count):
                    Text("\(count) Modelle gefunden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .idle:
                    Text("Vorschlag: \(AppSettings.defaultModel) für den Alltag, ein größeres Modell bei schlechten Scans.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("QR-Code") {
                TextField("Hinweis an Empfänger (Standard)", text: Binding(
                    get: { settings.beneficiaryHint },
                    set: { settings.beneficiaryHint = $0 }
                ))
                Toggle("Nutzdaten nach dem Auslesen automatisch kopieren", isOn: Binding(
                    get: { settings.copyPayloadAutomatically },
                    set: { settings.copyPayloadAutomatically = $0 }
                ))
            }

            Section("Finder") {
                Text("„Zahlungs-QR erzeugen“ erscheint im Rechtsklick-Menü unter „Dienste“, sobald die App einmal aus dem Programme-Ordner gestartet wurde. Fehlt der Eintrag, hilft ein Neustart des Finders oder `pbs -flush`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.vertical, 8)
    }

    private func loadModels() {
        loadState = .loading
        let apiKey = settings.apiKey
        Task {
            do {
                let models = try await OpenAIClient().availableModels(apiKey: apiKey)
                availableModels = models
                loadState = .loaded(models.count)
            } catch {
                availableModels = []
                loadState = .failed(error.localizedDescription)
            }
        }
    }
}
