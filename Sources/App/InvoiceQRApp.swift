import SwiftUI

@main
struct InvoiceQRApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @State private var settings = AppSettings.shared

    var body: some Scene {
        Window("InvoiceQR", id: "main") {
            ContentView()
                .environment(model)
                .environment(settings)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 900, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Invoice…") { model.chooseFile() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .newItem) {
                Button("Reset") { model.reset() }
                    .keyboardShortcut("k")
                    .disabled(model.sourceURL == nil)
                Divider()
                Button("Read Again") { model.retry() }
                    .keyboardShortcut("r")
                    .disabled(model.sourceURL == nil || model.isBusy)
            }
        }

        Settings {
            SettingsView()
                .environment(settings)
        }
    }
}
