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
                SecureField("API key", text: Binding(
                    get: { settings.apiKey },
                    set: { settings.apiKey = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                ))
                .textContentType(.password)
                Text("Stored in the keychain, not in the preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Model", text: Binding(
                        get: { settings.model },
                        set: { settings.model = $0.trimmingCharacters(in: .whitespaces) }
                    ))
                    .font(.system(.body, design: .monospaced))

                    Button("Load Models") { loadModels() }
                        .disabled(!settings.hasAPIKey || loadState == .loading)
                }

                if !availableModels.isEmpty {
                    Picker("Available", selection: Binding(
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
                        Text("Fetching models…").font(.caption)
                    }
                case let .failed(message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                case let .loaded(count):
                    Text("\(count) models found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .idle:
                    Text("Suggestion: \(AppSettings.defaultModel) for everyday use, a larger model for poor scans.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("QR code") {
                TextField("Default note to payee", text: Binding(
                    get: { settings.beneficiaryHint },
                    set: { settings.beneficiaryHint = $0 }
                ))
                Toggle("Copy the payload automatically after reading", isOn: Binding(
                    get: { settings.copyPayloadAutomatically },
                    set: { settings.copyPayloadAutomatically = $0 }
                ))
            }

            Section("Finder") {
                Text("“Create Payment QR Code” appears in the right-click menu under Services once the app has been launched from the Applications folder. If the entry is missing, restart Finder or run `pbs -flush`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 470)
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
