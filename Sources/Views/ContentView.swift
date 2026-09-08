import SwiftUI

struct ContentView: View {

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @State private var isDropTargeted = false

    var body: some View {
        content
            .toolbar { toolbarContent }
            .navigationTitle("InvoiceQR")
            .navigationSubtitle(model.sourceURL?.lastPathComponent ?? "")
            // Ganzes Fenster als Ablagefläche.
            .dropDestination(for: URL.self) { urls, _ in
                model.handle(urls: urls)
                return true
            } isTargeted: { isDropTargeted = $0 }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .idle:
            DropZoneView()
        case let .extracting(fileName):
            ExtractingView(fileName: fileName)
        case .ready:
            ResultView()
        case let .failed(message):
            FailureView(message: message)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ToolbarDropButton()
        }

        ToolbarItemGroup {
            if model.sourceURL != nil {
                Button {
                    model.retry()
                } label: {
                    Label("Erneut auslesen", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
                .help("Rechnung erneut an OpenAI schicken")

                Button {
                    model.reset()
                } label: {
                    Label("Zurücksetzen", systemImage: "xmark.circle")
                }
                .help("Fenster leeren")
            }

            SettingsLink {
                Label("Einstellungen", systemImage: "gearshape")
            }
            .help(settings.hasAPIKey ? "Modell: \(settings.model)" : "API-Key fehlt")
        }
    }
}

/// Ablagefläche in der Toolbar – nimmt Dateien direkt oben entgegen.
private struct ToolbarDropButton: View {

    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        Button {
            model.chooseFile()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "doc.badge.plus")
                Text(isTargeted ? "Loslassen" : "Rechnung")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(isTargeted ? 0.25 : 0))
            }
        }
        .help("Rechnung wählen (⌘O) oder PDF hierher ziehen")
        .dropDestination(for: URL.self) { urls, _ in
            model.handle(urls: urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct ExtractingView: View {

    let fileName: String

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Rechnung wird ausgelesen …")
                .font(.title3)
            Text(fileName)
                .foregroundStyle(.secondary)
            Text("Modell: \(settings.model)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FailureView: View {

    let message: String

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("Auslesen fehlgeschlagen")
                .font(.title3)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: 460)

            HStack {
                Button("Erneut versuchen") { model.retry() }
                    .disabled(model.sourceURL == nil)
                SettingsLink { Text("Einstellungen …") }
                Button("Zurücksetzen") { model.reset() }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
