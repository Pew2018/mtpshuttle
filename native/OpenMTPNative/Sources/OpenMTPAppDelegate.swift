import AppKit

@MainActor
final class OpenMTPAppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?
    private let frameKey = "SwiftMTP.mainWindowFrame"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)), name: NSWindow.didMoveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowChanged(_:)), name: NSWindow.didEndLiveResizeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowClosed(_:)), name: NSWindow.willCloseNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
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
        let window = notification.object as? NSWindow
        saveMainWindowFrame(window)
        if window?.title == "SwiftMTP" || window?.title == "OpenMTP" {
            OpenMTPQuickLookHost.closeSharedPanel()
        }
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.title == "MTP Shuttle" else { return }
        restoreMainWindowFrame(on: window)
    }

    func saveMainWindowFrame(_ window: NSWindow?) {
        guard let window, window.title == "MTP Shuttle" else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameKey)
    }

    func restoreMainWindowFrame() {
        guard let value = UserDefaults.standard.string(forKey: frameKey),
              let window = NSApp.windows.first(where: { $0.title == "MTP Shuttle" || $0.title == "SwiftMTP" || $0.title == "OpenMTP" }),
              !value.isEmpty else { return }
        restoreMainWindowFrame(on: window)
    }

    private func restoreMainWindowFrame(on window: NSWindow) {
        guard let value = UserDefaults.standard.string(forKey: frameKey), !value.isEmpty else { return }
        window.setFrame(NSRectFromString(value), display: true)
    }
}
