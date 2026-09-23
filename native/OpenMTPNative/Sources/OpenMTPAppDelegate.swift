import AppKit

@MainActor
final class OpenMTPAppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?
    private let frameKey = "OpenMTP.mainWindowFrame"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)), name: NSWindow.didMoveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)), name: NSWindow.didEndLiveResizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)), name: NSWindow.willCloseNotification, object: nil)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            openMainWindow?()
            DispatchQueue.main.async { self.restoreMainWindowFrame() }
        }

        return true
    }

    @objc private func windowChanged(_ notification: Notification) {
        saveMainWindowFrame(notification.object as? NSWindow)
    }

    @objc private func windowClosed(_ notification: Notification) {
        saveMainWindowFrame(notification.object as? NSWindow)
    }

    func saveMainWindowFrame(_ window: NSWindow?) {
        guard let window, window.title == "OpenMTP" else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameKey)
    }

    func restoreMainWindowFrame() {
        guard let value = UserDefaults.standard.string(forKey: frameKey),
              let window = NSApp.windows.first(where: { $0.title == "OpenMTP" }),
              !value.isEmpty else { return }
        window.setFrame(NSRectFromString(value), display: true)
    }
}
