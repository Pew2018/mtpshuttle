import AppKit
import QuickLookUI

/// Owns the window lifecycle instead of relying on QLPreviewPanel's responder-chain controller.
@MainActor
enum OpenMTPQuickLookHost {
    static func trace(_ message: String) {
        DebugLogger.verbose("QL trace: \(message)")
    }

    static func panelState() -> String {
        QuickLookWindowController.shared.stateDescription
    }

    static func isSharedPanelVisible() -> Bool {
        QuickLookWindowController.shared.isPresented
    }

    static func present(urls: [URL], onPreviewEnded: @escaping ([URL]) -> Void) {
        QuickLookWindowController.shared.present(urls: urls, onPreviewEnded: onPreviewEnded)
    }

    static func update(urls: [URL]) {
        QuickLookWindowController.shared.update(urls: urls)
    }

    static func closeSharedPanel() {
        QuickLookWindowController.shared.close()
    }
}

private final class OpenMTPPreviewPanel: NSPanel {
    var onSpace: (() -> Void)?
    var onStep: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            switch event.keyCode {
            case 49:
                if !event.isARepeat {
                    onSpace?()
                }
                return
            case 123:
                onStep?(-1)
                return
            case 124:
                onStep?(1)
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }
}

@MainActor
private final class QuickLookWindowController: NSObject, NSWindowDelegate {
    static let shared = QuickLookWindowController()

    private var panel: OpenMTPPreviewPanel?
    private var previewView: QLPreviewView?
    private var urls: [URL] = []
    private var index = 0
    private var onPreviewEnded: (([URL]) -> Void)?
    private(set) var isPresented = false

    var stateDescription: String {
        "presented=\(isPresented), visible=\(panel?.isVisible == true), key=\(panel?.isKeyWindow == true), items=\(urls.count), index=\(index)"
    }

    func present(urls: [URL], onPreviewEnded: @escaping ([URL]) -> Void) {
        guard !urls.isEmpty else { return }
        if isPresented {
            update(urls: urls)
            return
        }

        let frame = NSRect(x: 0, y: 0, width: 840, height: 600)
        let window = OpenMTPPreviewPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 300)
        window.level = .floating
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.delegate = self
        window.center()

        let preview = QLPreviewView(frame: NSRect(origin: .zero, size: frame.size), style: .normal)!
        preview.autoresizingMask = [.width, .height]
        preview.shouldCloseWithWindow = true
        window.contentView = preview
        window.onSpace = { [weak self] in self?.close() }
        window.onStep = { [weak self] direction in self?.step(direction) }

        self.panel = window
        self.previewView = preview
        self.urls = urls
        self.index = 0
        self.onPreviewEnded = onPreviewEnded
        self.isPresented = true
        displayCurrentItem()
        OpenMTPQuickLookHost.trace("present; \(stateDescription)")
        window.makeKeyAndOrderFront(nil)
    }

    func update(urls: [URL]) {
        guard isPresented else { return }
        guard !urls.isEmpty else {
            close()
            return
        }
        if self.urls == urls { return }
        self.urls = urls
        index = 0
        displayCurrentItem()
        OpenMTPQuickLookHost.trace("selection updated; \(stateDescription)")
    }

    func close() {
        guard isPresented else { return }
        OpenMTPQuickLookHost.trace("close requested; \(stateDescription)")
        panel?.close()
        // AppKit normally calls windowWillClose synchronously. Complete the cleanup
        // if it does not, so a queued update cannot restore the old preview.
        if isPresented {
            finishClosing()
        }
    }

    func windowWillClose(_ notification: Notification) {
        finishClosing()
    }

    private func finishClosing() {
        guard isPresented else { return }
        isPresented = false
        let endedURLs = urls
        urls = []
        index = 0
        previewView?.close()
        previewView = nil
        panel?.delegate = nil
        panel?.onSpace = nil
        panel?.onStep = nil
        panel = nil
        let callback = onPreviewEnded
        onPreviewEnded = nil
        OpenMTPQuickLookHost.trace("closed; \(stateDescription)")
        callback?(endedURLs)
    }

    private func step(_ direction: Int) {
        guard isPresented, urls.count > 1 else { return }
        index = (index + direction + urls.count) % urls.count
        displayCurrentItem()
    }

    private func displayCurrentItem() {
        guard urls.indices.contains(index) else { return }
        let url = urls[index]
        previewView?.previewItem = OpenMTPQuickLookItem(url: url)
        panel?.title = urls.count == 1
            ? url.lastPathComponent
            : "\(url.lastPathComponent) (\(index + 1)/\(urls.count))"
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
