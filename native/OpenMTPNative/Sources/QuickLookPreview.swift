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

    static func trace(_ message: String) {
        DebugLogger.verbose("QL trace: \(message)")
    }

    static func panelState() -> String {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() else {
            return "panel=absent"
        }
        return "visible=\(panel.isVisible), key=\(panel.isKeyWindow), controller=\(String(describing: panel.currentController.map { type(of: $0) })), generation=\(presentationGeneration)"
    }

    static func isSharedPanelVisible() -> Bool {
        QLPreviewPanel.shared()?.isVisible == true
    }

    static func isSharedPanelKeyWindow() -> Bool {
        QLPreviewPanel.shared()?.isKeyWindow == true
    }

    static func requestSharedPanelPresentation() {
        presentationGeneration &+= 1
        trace("request presentation; \(panelState())")
    }

    static func closeSharedPanel() {
        // Invalidate deferred presentations before hiding the shared panel.
        trace("close before; \(panelState())")
        presentationGeneration &+= 1
        QLPreviewPanel.shared()?.orderOut(nil)
        trace("close after; \(panelState())")
    }

    @Binding var isPresented: Bool
    @Binding var urls: [URL]
    let onPreviewEnded: ([URL]) -> Void

    func makeNSView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.onPreviewEnded = onPreviewEnded
        return view
    }

    func updateNSView(_ nsView: PreviewHostView, context: Context) {
        nsView.onPreviewEnded = onPreviewEnded
        nsView.setPreviewState(isPresented: isPresented, urls: urls)
    }

    final class PreviewHostView: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        private var previewURLs: [URL] = []
        private var isPreviewRequested = false
        private var isControllingPreviewPanel = false
        var onPreviewEnded: (([URL]) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        func setPreviewState(isPresented: Bool, urls: [URL]) {
            let urlsChanged = previewURLs != urls
            let presentationChanged = isPreviewRequested != isPresented
            previewURLs = urls
            isPreviewRequested = isPresented
            OpenMTPQuickLookHost.trace("set state: requested=\(isPresented), urls=\(urls.count), urlsChanged=\(urlsChanged), presentationChanged=\(presentationChanged), controlling=\(isControllingPreviewPanel); \(OpenMTPQuickLookHost.panelState())")

            guard isPresented, !urls.isEmpty else {
                if presentationChanged || OpenMTPQuickLookHost.isSharedPanelVisible() {
                    OpenMTPQuickLookHost.closeSharedPanel()
                }
                return
            }

            let panelIsVisible = OpenMTPQuickLookHost.isSharedPanelVisible()
            if isControllingPreviewPanel, panelIsVisible {
                guard urlsChanged, let panel = QLPreviewPanel.shared() else { return }
                OpenMTPQuickLookHost.trace("reload selection, no presentation; \(OpenMTPQuickLookHost.panelState())")
                panel.reloadData()
                panel.currentPreviewItemIndex = 0
                return
            }

            guard urlsChanged || presentationChanged || !panelIsVisible else { return }
            let requestedURLs = urls
            let generation = OpenMTPQuickLookHost.presentationGeneration
            OpenMTPQuickLookHost.trace("schedule show: generation=\(generation); \(OpenMTPQuickLookHost.panelState())")
            DispatchQueue.main.async { [weak self] in
                OpenMTPQuickLookHost.trace("execute show: scheduled=\(generation), requested=\(self?.isPreviewRequested.description ?? "nil"), urlsMatch=\(self?.previewURLs == requestedURLs), controlling=\(self?.isControllingPreviewPanel.description ?? "nil"); \(OpenMTPQuickLookHost.panelState())")
                guard let self,
                      OpenMTPQuickLookHost.presentationGeneration == generation,
                      self.isPreviewRequested,
                      self.previewURLs == requestedURLs,
                      !self.isControllingPreviewPanel else {
                    return
                }
                self.showPreviewPanel()
            }
        }

        private func showPreviewPanel() {
            guard let window,
                  let panel = QLPreviewPanel.shared()
            else {
                return
            }

            OpenMTPQuickLookHost.trace("show before: firstResponder=\(String(describing: window.firstResponder.map { type(of: $0) })); \(OpenMTPQuickLookHost.panelState())")
            window.makeFirstResponder(self)
            panel.makeKeyAndOrderFront(nil)
            OpenMTPQuickLookHost.trace("show after; \(OpenMTPQuickLookHost.panelState())")
        }

        override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
            true
        }

        override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            OpenMTPQuickLookHost.trace("begin control; \(OpenMTPQuickLookHost.panelState())")
            isControllingPreviewPanel = true
            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
        }

        override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            OpenMTPQuickLookHost.trace("end control; \(OpenMTPQuickLookHost.panelState())")
            let endedURLs = previewURLs
            let generation = OpenMTPQuickLookHost.presentationGeneration
            panel.dataSource = nil
            panel.delegate = nil
            isControllingPreviewPanel = false

            // Losing control when the main window becomes active is normal while
            // the panel remains visible. Only report an end after an actual close.
            DispatchQueue.main.async { [weak self, weak panel] in
                OpenMTPQuickLookHost.trace("check end callback: scheduled=\(generation), requested=\(self?.isPreviewRequested.description ?? "nil"); \(OpenMTPQuickLookHost.panelState())")
                guard let self,
                      let panel,
                      !panel.isVisible,
                      OpenMTPQuickLookHost.presentationGeneration == generation,
                      self.isPreviewRequested else {
                    return
                }
                self.isPreviewRequested = false
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
            OpenMTPQuickLookHost.trace("space: eventNumber=\(event.eventNumber), timestamp=\(event.timestamp), repeat=\(event.isARepeat), main=\(isMainWindowEvent), panel=\(isQuickLookWindowEvent), firstResponder=\(String(describing: window.firstResponder.map { type(of: $0) })); \(OpenMTPQuickLookHost.panelState())")
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

