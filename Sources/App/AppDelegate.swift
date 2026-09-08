import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Makes "Create Payment QR Code" show up under Services in the Finder context menu.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Open With and double-click.
    func application(_ application: NSApplication, open urls: [URL]) {
        AppModel.shared.handle(urls: urls)
    }

    /// The Services entry from Info.plist (`NSMessage` = createPaymentQR).
    @objc func createPaymentQR(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []

        guard !urls.isEmpty else {
            error?.pointee = NSLocalizedString("No file was passed.", comment: "Service error") as NSString
            return
        }
        AppModel.shared.handle(urls: urls)
    }
}
