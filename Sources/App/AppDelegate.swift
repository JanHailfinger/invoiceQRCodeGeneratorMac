import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Macht "Zahlungs-QR erzeugen" im Finder-Kontextmenü unter "Dienste" verfügbar.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// "Öffnen mit" und Doppelklick.
    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.handle(urls: urls)
    }

    /// Dienste-Eintrag aus Info.plist (`NSMessage` = createPaymentQR).
    @objc func createPaymentQR(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []

        guard !urls.isEmpty else {
            error?.pointee = "Keine Datei übergeben." as NSString
            return
        }
        AppModel.shared.handle(urls: urls)
    }
}
