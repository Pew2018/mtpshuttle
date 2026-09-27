import SwiftUI
import AppKit
import QuickLookUI

extension Notification.Name {
    static let openMTPCopy = Notification.Name("OpenMTP.Copy")
    static let openMTPCut = Notification.Name("OpenMTP.Cut")
    static let openMTPPaste = Notification.Name("OpenMTP.Paste")
}

struct OpenMTPQuickLookHost: NSViewRepresentable {
    /// QLPreviewPanel is shared and can outlive the SwiftUI owner.
    private static var presentationGeneration: UInt = 0

    static func isSharedPanelVisible() -> Bool {
        QLPreviewPanel.shared()?.isVisible == true
    }

    static func isSharedPanelKeyWindow() -> Bool {
        QLPreviewPanel.shared()?.isKeyWindow == true
    }

    static func closeSharedPanel() {
        // Invalidate any deferred presentation requested by a previous selection.
        presentationGeneration &+= 1
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.orderOut(nil)
        panel.dataSource = nil
        panel.delegate = nil
    }

    @Binding var urls: [URL]
    let onPreviewEnded: ([URL]) -> Void

    func makeNSView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.onPreviewEnded = onPreviewEnded
        return view
    }

    func updateNSView(_ nsView: PreviewHostView, context: Context) {
        nsView.onPreviewEnded = onPreviewEnded
        nsView.setPreviewURLs(urls)
    }

    final class PreviewHostView: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        private var previewURLs: [URL] = []
        private var isControllingPreviewPanel = false
        var onPreviewEnded: (([URL]) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        func setPreviewURLs(_ urls: [URL]) {
            let changed = previewURLs != urls
            previewURLs = urls
            guard changed else { return }
            if isControllingPreviewPanel {
                guard let panel = QLPreviewPanel.shared() else { return }
                if urls.isEmpty {
                    panel.orderOut(nil)
                } else {
                    panel.reloadData()
                    panel.currentPreviewItemIndex = 0
                }
            } else if !urls.isEmpty {
                let requestedURLs = urls
                let generation = OpenMTPQuickLookHost.presentationGeneration
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          OpenMTPQuickLookHost.presentationGeneration == generation,
                          self.previewURLs == requestedURLs,
                          !self.isControllingPreviewPanel else {
                        return
                    }
                    self.showPreviewPanel()
                }
            }
        }

        private func showPreviewPanel() {
            guard let window,
                  let panel = QLPreviewPanel.shared()
            else {
                return
            }

            window.makeFirstResponder(self)
            panel.makeKeyAndOrderFront(nil)
        }

        override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
            true
        }

        override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            isControllingPreviewPanel = true
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
        }

        override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            let endedURLs = previewURLs
            panel.dataSource = nil
            panel.delegate = nil
            isControllingPreviewPanel = false

            // Clicking another row gives the app window focus and can end
            // control even while the Quick Look panel is still visible.
            // Keep the URLs so the next selection can take control again.
            DispatchQueue.main.async { [weak self, weak panel] in
                guard let self, let panel, !panel.isVisible else { return }
                self.previewURLs = []
                self.onPreviewEnded?(endedURLs)
            }
        }

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            previewURLs.count
        }

        func previewPanel(
            _ panel: QLPreviewPanel!,
            previewItemAt index: Int
        ) -> QLPreviewItem! {
            guard previewURLs.indices.contains(index) else {
                return nil
            }

            return OpenMTPQuickLookItem(url: previewURLs[index])
        }

    }
}

private final class OpenMTPQuickLookItem: NSObject, QLPreviewItem {
    let previewItemURL: URL
    let previewItemTitle: String?

    init(url: URL) {
        self.previewItemURL = url
        self.previewItemTitle = url.lastPathComponent
        super.init()
    }
}
struct QuickLookKeyboardShortcutMonitor: NSViewRepresentable {
    let isEnabled: () -> Bool
    let onShortcut: () -> Void

    func makeNSView(context: Context) -> QuickLookShortcutView {
        let view = QuickLookShortcutView()
        view.isEnabled = isEnabled
        view.onShortcut = onShortcut
        return view
    }

    func updateNSView(_ view: QuickLookShortcutView, context: Context) {
        view.isEnabled = isEnabled
        view.onShortcut = onShortcut
    }

    static func dismantleNSView(_ view: QuickLookShortcutView, coordinator: ()) {
        view.stopMonitoring()
    }
}

@MainActor
final class QuickLookShortcutView: NSView {
    var isEnabled: () -> Bool = { false }
    var onShortcut: () -> Void = {}
    private var eventMonitor: Any?
    private static var lastHandledSpaceEventTimestamp: TimeInterval?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  self.isEnabled() else {
                return event
            }

            let isMainWindowEvent = event.window === window
            let isQuickLookWindowEvent = OpenMTPQuickLookHost.isSharedPanelKeyWindow()
                && event.window === QLPreviewPanel.shared()
            guard isMainWindowEvent || isQuickLookWindowEvent,
                  !(isMainWindowEvent && window.firstResponder is NSTextView) else {
                return event
            }

            // Multiple SwiftUI representable instances can observe the same NSEvent.
            // Treat its timestamp as an idempotency key so one physical key press
            // cannot close the panel and then immediately reopen it.
            guard Self.lastHandledSpaceEventTimestamp != event.timestamp else {
                DebugLogger.verbose("Duplicate Quick Look Space event ignored: timestamp=\(event.timestamp)")
                return nil
            }
            Self.lastHandledSpaceEventTimestamp = event.timestamp
            DebugLogger.verbose(
                "Quick Look Space event handled: timestamp=\(event.timestamp), visible=\(OpenMTPQuickLookHost.isSharedPanelVisible())"
            )

            self.onShortcut()
            return nil
        }
    }

    func stopMonitoring() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

