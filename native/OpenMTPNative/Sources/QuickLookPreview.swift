import SwiftUI
import AppKit
import QuickLookUI

extension Notification.Name {
    static let openMTPQuickLook = Notification.Name("OpenMTP.QuickLook")
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
        var onPreviewEnded: (([URL]) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        func setPreviewURLs(_ urls: [URL]) {\n            let changed = previewURLs != urls\n            DebugLogger.verbose("QuickLook set URLs: count=\(urls.count), changed=\(changed), controlling=\(isControllingPreviewPanel), names=\(urls.map(\\.lastPathComponent).joined(separator: "|"))")\n            previewURLs = urls\n            guard changed else { return }
            if isControllingPreviewPanel {
                guard let panel = QLPreviewPanel.shared() else { return }
                if urls.isEmpty {
                    panel.orderOut(nil)
                } else {
                    // Reclaim keyboard focus after replacing the data source.
                    // Otherwise the item changes but Space is no longer routed
                    // to the preview delegate.
                    panel.dataSource = self
                    panel.delegate = self
                    window?.makeFirstResponder(self)
                    panel.makeKeyAndOrderFront(nil)
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

        override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {\n            DebugLogger.verbose("QuickLook begin control")\n            isControllingPreviewPanel = true\n            panel.dataSource = self
            panel.delegate = self
            panel.reloadData()
        }

        override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {\n            DebugLogger.verbose("QuickLook end control")\n            let endedURLs = previewURLs\n            panel.dataSource = nil
            panel.delegate = nil
            isControllingPreviewPanel = false
            previewURLs = []
            onPreviewEnded?(endedURLs)
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
