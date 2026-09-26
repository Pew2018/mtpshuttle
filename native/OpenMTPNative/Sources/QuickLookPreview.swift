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
    static func closeSharedPanel() {
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
        private var spaceKeyMonitor: Any?
        var onPreviewEnded: (([URL]) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            installSpaceKeyMonitor()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            installSpaceKeyMonitor()
        }

        deinit {
            if let spaceKeyMonitor {
                NSEvent.removeMonitor(spaceKeyMonitor)
            }
        }

        private func installSpaceKeyMonitor() {
            spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard self != nil,
                      event.keyCode == 49,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                      let panel = QLPreviewPanel.shared(),
                      panel.isVisible else {
                    return event
                }

                panel.orderOut(nil)
                return nil
            }
        }

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
                DispatchQueue.main.async { [weak self] in self?.showPreviewPanel() }
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

        func previewPanel(
            _ panel: QLPreviewPanel!,
            handle event: NSEvent!
        ) -> Bool {
            guard event.type == .keyDown,
                  event.keyCode == 49
            else {
                return false
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers.isEmpty else {
                return false
            }

            panel.orderOut(nil)
            return true
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window === window,
                  event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  !(window.firstResponder is NSTextView),
                  self.isEnabled() else {
                return event
            }
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

