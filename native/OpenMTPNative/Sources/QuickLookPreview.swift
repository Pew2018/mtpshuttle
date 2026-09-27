import AppKit
import PDFKit
import QuickLookUI

/// Owns the preview window and keeps the Quick Look view inside a bounded content view.
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
                if !event.isARepeat { onSpace?() }
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
    private var container: NSView?
    private var quickLookView: QLPreviewView?
    private var pdfView: PDFView?
    private var textScrollView: NSScrollView?
    private var textView: NSTextView?
    private var imageView: NSImageView?
    private var urls: [URL] = []
    private var index = 0
    private var onPreviewEnded: (([URL]) -> Void)?
    private(set) var isPresented = false

    private let textExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "log", "csv", "tsv", "json",
        "xml", "yaml", "yml", "swift", "go", "js", "ts", "html", "css"
    ]
    private let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tif", "tiff", "bmp"
    ]

    var stateDescription: String {
        "presented=\(isPresented), visible=\(panel?.isVisible == true), key=\(panel?.isKeyWindow == true), items=\(urls.count), index=\(index)"
    }

    func present(urls: [URL], onPreviewEnded: @escaping ([URL]) -> Void) {
        guard !urls.isEmpty else { return }
        if isPresented {
            update(urls: urls)
            return
        }

        ensureWindow()
        self.urls = urls
        self.index = 0
        self.onPreviewEnded = onPreviewEnded
        self.isPresented = true
        displayCurrentItem()
        OpenMTPQuickLookHost.trace("present; \(stateDescription)")
        panel?.makeKeyAndOrderFront(nil)
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
        isPresented = false
        panel?.orderOut(nil)
        let endedURLs = urls
        urls = []
        index = 0
        let callback = onPreviewEnded
        onPreviewEnded = nil
        OpenMTPQuickLookHost.trace("closed; \(stateDescription)")
        callback?(endedURLs)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    private func ensureWindow() {
        guard panel == nil else { return }

        let size = NSSize(width: 840, height: 600)
        let frame = NSRect(origin: .zero, size: size)
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

        let content = NSView(frame: frame)
        content.autoresizesSubviews = true
        window.contentView = content
        window.setContentSize(size)
        window.center()
        window.onSpace = { [weak self] in self?.close() }
        window.onStep = { [weak self] direction in self?.step(direction) }

        panel = window
        container = content
    }

    private func step(_ direction: Int) {
        guard isPresented, urls.count > 1 else { return }
        index = (index + direction + urls.count) % urls.count
        displayCurrentItem()
    }

    private func displayCurrentItem() {
        guard urls.indices.contains(index), let container else { return }
        let url = urls[index]
        panel?.title = urls.count == 1
            ? url.lastPathComponent
            : "\(url.lastPathComponent) (\(index + 1)/\(urls.count))"

        hidePreviewViews()
        let ext = url.pathExtension.lowercased()

        if ext == "pdf", let document = PDFDocument(url: url) {
            let view = ensurePDFView(in: container)
            view.document = document
            view.autoScales = true
            view.isHidden = false
            OpenMTPQuickLookHost.trace("display PDF: \(url.lastPathComponent)")
            return
        }

        if textExtensions.contains(ext), let text = readableText(at: url) {
            let scroll = ensureTextView(in: container)
            textView?.string = text
            scroll.isHidden = false
            OpenMTPQuickLookHost.trace("display text: \(url.lastPathComponent)")
            return
        }

        if imageExtensions.contains(ext), let image = NSImage(contentsOf: url) {
            let view = ensureImageView(in: container)
            view.image = image
            view.isHidden = false
            OpenMTPQuickLookHost.trace("display image: \(url.lastPathComponent)")
            return
        }

        let view = ensureQuickLookView(in: container)
        view.previewItem = OpenMTPQuickLookItem(url: url)
        view.isHidden = false
        OpenMTPQuickLookHost.trace("display Quick Look: \(url.lastPathComponent)")
    }

    private func hidePreviewViews() {
        pdfView?.isHidden = true
        textScrollView?.isHidden = true
        imageView?.isHidden = true
        quickLookView?.isHidden = true
    }

    private func attach(_ view: NSView, to container: NSView) {
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    private func ensurePDFView(in container: NSView) -> PDFView {
        if let pdfView { return pdfView }
        let view = PDFView(frame: container.bounds)
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        attach(view, to: container)
        pdfView = view
        return view
    }

    private func ensureTextView(in container: NSView) -> NSScrollView {
        if let textScrollView { return textScrollView }
        let scroll = NSScrollView(frame: container.bounds)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        let text = NSTextView(frame: container.bounds)
        text.isEditable = false
        text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        text.textContainer?.widthTracksTextView = true
        text.isHorizontallyResizable = false
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        scroll.documentView = text
        attach(scroll, to: container)
        textView = text
        textScrollView = scroll
        return scroll
    }

    private func ensureImageView(in container: NSView) -> NSImageView {
        if let imageView { return imageView }
        let view = NSImageView(frame: container.bounds)
        view.imageScaling = .scaleProportionallyUpOrDown
        attach(view, to: container)
        imageView = view
        return view
    }

    private func ensureQuickLookView(in container: NSView) -> QLPreviewView {
        if let quickLookView { return quickLookView }
        let view = QLPreviewView(frame: container.bounds, style: .normal)!
        view.shouldCloseWithWindow = false
        attach(view, to: container)
        quickLookView = view
        return view
    }

    private func readableText(at url: URL) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 4 * 1_024 * 1_024 else { return nil }
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) { return utf8 }
        return try? String(contentsOf: url, encoding: .utf16)
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
