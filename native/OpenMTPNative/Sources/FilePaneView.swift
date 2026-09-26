import SwiftUI
import AppKit
import UniformTypeIdentifiers

private final class MTPShuttleFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let fileName: String
    let writePromise: (URL, @escaping (Error?) -> Void) -> Void
    private let writeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "MTPShuttle.FilePromise"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    init(fileName: String, writePromise: @escaping (URL, @escaping (Error?) -> Void) -> Void) {
        self.fileName = fileName
        self.writePromise = writePromise
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        DebugLogger.info("Android file promise name requested: \(fileName)")
        return fileName
    }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { writeQueue }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        DebugLogger.info("Android file promise requested: \(fileName)")
        writePromise(url, completionHandler)
    }
}
final class MTPShuttleFilePromiseProvider: NSFilePromiseProvider {
    // AppKit's init(fileType:delegate:) is a convenience initializer that calls
    // self.init(). Keep that initializer available on this Swift subclass.
    private var promiseDelegate: MTPShuttleFilePromiseDelegate?
    // Used only by another pane in this process; never advertise it to Finder.
    private(set) var internalPayload: String?

    override init() {
        super.init()
    }

    convenience init(fileType: String, fileName: String, encodedPayload: String?, writePromise: @escaping (URL, @escaping (Error?) -> Void) -> Void) {
        self.init()
        let promiseDelegate = MTPShuttleFilePromiseDelegate(fileName: fileName, writePromise: writePromise)
        self.promiseDelegate = promiseDelegate // NSFilePromiseProvider holds its delegate weakly.
        self.internalPayload = encodedPayload
        self.fileType = fileType
        self.delegate = promiseDelegate
    }
}
struct MTPShuttleFilePromiseDragSource: NSViewRepresentable {
    let makeProviders: () -> [NSFilePromiseProvider]
    let onClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DragSourceView {
        DragSourceView(makeProviders: makeProviders, onClick: onClick, onDoubleClick: onDoubleClick)
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.makeProviders = makeProviders
        nsView.onClick = onClick
        nsView.onDoubleClick = onDoubleClick
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var makeProviders: () -> [NSFilePromiseProvider]
        var onClick: () -> Void
        var onDoubleClick: () -> Void
        private var mouseDownEvent: NSEvent?
        private var hasDraggingSession = false
        // AppKit consumes NSDraggingItem instances when the session begins. Keep
        // the promise writers and their delegates alive until the next drag.
        private var retainedProviders: [NSFilePromiseProvider] = []
        private(set) var internalPayload: String?
        private var lastDragContext: NSDraggingContext?
        private let dragDistance: CGFloat = 6

        init(makeProviders: @escaping () -> [NSFilePromiseProvider], onClick: @escaping () -> Void, onDoubleClick: @escaping () -> Void) {
            self.makeProviders = makeProviders
            self.onClick = onClick
            self.onDoubleClick = onDoubleClick
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Leave the SwiftUI row's context menu in charge of right clicks.
            if NSApp.currentEvent?.type == .rightMouseDown { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownEvent, !hasDraggingSession else { return }
            let deltaX = event.locationInWindow.x - start.locationInWindow.x
            let deltaY = event.locationInWindow.y - start.locationInWindow.y
            guard hypot(deltaX, deltaY) >= dragDistance else { return }

            // Once the pointer moves far enough, it is no longer a click.
            mouseDownEvent = nil
            let providers = makeProviders()
            guard !providers.isEmpty else { return }
            let items = providers.map { provider -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: provider)
                let symbol = provider.fileType == UTType.directory.identifier ? "folder.fill" : "doc.fill"
                let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                    ?? NSWorkspace.shared.icon(forFileType: provider.fileType)
                let frame = NSRect(
                    x: max(0, (bounds.width - 32) / 2),
                    y: max(0, (bounds.height - 32) / 2),
                    width: 32,
                    height: 32
                )
                item.setDraggingFrame(frame, contents: icon)
                return item
            }
            retainedProviders = providers
            internalPayload = (providers.first as? MTPShuttleFilePromiseProvider)?.internalPayload
            hasDraggingSession = true
            lastDragContext = nil
            DebugLogger.info("Android file drag started: count=\(providers.count)")
            let session = beginDraggingSession(with: items, event: start, source: self)
            DebugLogger.info("Android drag pasteboard types: \(session.draggingPasteboard.types?.map(\.rawValue).joined(separator: "|") ?? "")")
        }

        override func mouseUp(with event: NSEvent) {
            guard let start = mouseDownEvent else { return }
            mouseDownEvent = nil
            let deltaX = event.locationInWindow.x - start.locationInWindow.x
            let deltaY = event.locationInWindow.y - start.locationInWindow.y
            guard hypot(deltaX, deltaY) < dragDistance else { return }
            if event.clickCount >= 2 {
                onDoubleClick()
            } else {
                onClick()
            }
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            if lastDragContext != context {
                lastDragContext = context
                DebugLogger.info("Android file drag context: \(context == .outsideApplication ? "outside application" : "inside application")")
            }
            return .copy
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            DebugLogger.info("Android file drag ended: operation=\(operation.rawValue)")
            hasDraggingSession = false
            mouseDownEvent = nil
            internalPayload = nil
            lastDragContext = nil
            // Finder may request the promised file after this callback.
            // Retain the providers until the next drag or this row disappears.
        }
    }
}

private struct MTPShuttleLocalPaneDrag: ViewModifier {
    let enabled: Bool
    let provider: () -> NSItemProvider

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.onDrag(provider)
        } else {
            content
        }
    }
}



enum MTPShuttleDNDLogger {
    private static let queue = DispatchQueue(label: "com.pew2018.mtpshuttle.dnd-log")
    private static let url = URL(fileURLWithPath: "/tmp/mtp-shuttle-dnd.log")

    static func reset() {
        queue.sync {
            try? Data().write(to: url, options: .atomic)
        }
    }

    static func log(_ message: String) {
        queue.async {
            let line = "[MTP-Shuttle-DND] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                return
            }

            try? data.write(to: url, options: .atomic)
        }
    }
}

enum FinderOpenTarget: Equatable {
    case selectFileInContainingFolder(URL)
    case openDirectory(URL)

    static func target(for item: DemoEntry, isPackage packageOverride: Bool? = nil) -> FinderOpenTarget? {
        guard let localURL = item.localURL else { return nil }
        let url = localURL.standardizedFileURL
        let isPackage = packageOverride ?? NSWorkspace.shared.isFilePackage(atPath: url.path)
        return item.isDirectory && !isPackage ? .openDirectory(url) : .selectFileInContainingFolder(url)
    }
}

struct FilePaneView: View {
    let pane: PaneKind
    var subtitle: String? = nil
    var refreshTitle: String = "Refresh"
    var isLoading = false
    var errorMessage: String? = nil
    var emptyMessage: String? = nil
    var breadcrumbs: [BreadcrumbComponent]? = nil
    var canModifyFiles = false
    let path: String
    let items: [DemoEntry]
    @Binding var selection: Set<UUID>
    let canGoBack: Bool
    let canGoForward: Bool
    let canPaste: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onRefresh: () -> Void
    let onNavigate: (String) -> Void
    let onOpen: (DemoEntry) -> Void
    let onAction: (PaneAction, DemoEntry?) -> Void
    let onNewFolder: () -> Void
    let onPaste: () -> Void
    let showCrossPaneActions: Bool
    let onInternalDrop: (String) -> Void
    let onExternalFileDrop: ([URL]) -> Void
    let onDragProvider: (DemoEntry, Set<UUID>) -> NSItemProvider
    let onFilePromiseProviders: (DemoEntry, Set<UUID>) -> [NSFilePromiseProvider]

    @State private var viewMode: FileViewMode = .list
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            paneHeader

            Divider()

            if isLoading && items.isEmpty {
                ProgressView("Loading folder…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = items.isEmpty ? (errorMessage ?? emptyMessage) : nil {
                VStack(spacing: 12) {
                    Image(systemName: errorMessage == nil ? "externaldrive" : "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text(message).multilineTextAlignment(.center).textSelection(.enabled)
                    Button(refreshTitle, action: onRefresh)
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                emptyState
            } else if viewMode == .list {
                VStack(spacing: 0) {
                    if isLoading { Text("正在加载，已显示 \(items.count) 个项目；点按右侧 Refresh 可暂停")
                        .font(.caption).foregroundStyle(.secondary).padding(6) }
                    if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.orange).padding(6) }
                    listView
                }
            } else {
                gridView
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 2)
                    }
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            OpenMTPExternalDropReceiver(
                isTargeted: $isDropTargeted,
                onInternalDrop: onInternalDrop,
                onExternalFileDrop: onExternalFileDrop
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            MTPShuttleDNDLogger.reset()
            MTPShuttleDNDLogger.log("FilePane appeared")
        }
    }

    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: pane.deviceSymbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(deviceColor)
                    .frame(width: 29, height: 29)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.title)
                        .font(.headline)

                    Text(subtitle ?? pane.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: onRefresh) {
                    Label(refreshTitle, systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading && pane == .mac)
                .help(isLoading && pane == .android ? "暂停加载并显示已读取项目" : (refreshTitle == "Connect" ? "Connect to the Android device" : "Refresh this pane"))

                Spacer(minLength: 8)

                HStack(spacing: 2) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canGoBack)
                    .help("Back")

                    Button(action: onForward) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canGoForward)
                    .help("Forward")

                    Picker("", selection: $viewMode) {
                        ForEach(FileViewMode.allCases) { mode in
                            Image(systemName: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 78)
                    .accessibilityLabel("View")
                    .help("Change view")
                }
            }

            pathBreadcrumb
        }
        .padding(12)
        .background(.bar)
    }

    private var pathBreadcrumb: some View {
        let components = breadcrumbs ?? ((pane == .mac && path != "/" ? [BreadcrumbComponent(id: "/", name: "/", path: "/")] : []) + DemoFileSystem.breadcrumbComponents(for: path))

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                Image(systemName: "folder")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .frame(width: 20)

                ForEach(components.indices, id: \.self) { index in
                    let component = components[index]

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(index == 0 ? 0 : 1)

                    Button {
                        onNavigate(component.path)
                    } label: {
                        Text(component.name)
                            .font(.system(.subheadline, design: .monospaced))
                            .lineLimit(1)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(
                        component.path == path
                            ? Color.primary
                            : Color(nsColor: .controlAccentColor)
                    )
                    .disabled(component.path == path)
                    .help("Open \(component.path)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(items) { item in
                    FileRowView(
                        item: item,
                        isSelected: selection.contains(item.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        updateSelection(for: item.id)
                    }
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            onOpen(item)
                        }
                    )
                    .contextMenu {
                        itemContextMenu(for: item)
                    }
                    .overlay {
                        if pane == .android {
                            MTPShuttleFilePromiseDragSource(
                                makeProviders: { onFilePromiseProviders(item, selection) },
                                onClick: { updateSelection(for: item.id) },
                                onDoubleClick: { onOpen(item) }
                            )
                        }
                    }
                    .modifier(MTPShuttleLocalPaneDrag(enabled: pane == .mac) {
                        onDragProvider(item, selection)
                    })
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .contextMenu {
            Button("New Folder", action: onNewFolder).disabled(!canModifyFiles)

            Button("Select All") {
                selection = Set(items.map(\.id))
            }
            .disabled(items.isEmpty)

            Divider()

            Button("Paste", action: onPaste)
                .disabled(!canPaste || !canModifyFiles)
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 140), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(items) { item in
                    FileGridItemView(
                        item: item,
                        isSelected: selection.contains(item.id)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        updateSelection(for: item.id)
                    }
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            onOpen(item)
                        }
                    )
                    .contextMenu {
                        itemContextMenu(for: item)
                    }
                    .overlay {
                        if pane == .android {
                            MTPShuttleFilePromiseDragSource(
                                makeProviders: { onFilePromiseProviders(item, selection) },
                                onClick: { updateSelection(for: item.id) },
                                onDoubleClick: { onOpen(item) }
                            )
                        }
                    }
                    .modifier(MTPShuttleLocalPaneDrag(enabled: pane == .mac) {
                        onDragProvider(item, selection)
                    })
                }
            }
            .padding(14)
        }
        .contextMenu {
            Button("New Folder", action: onNewFolder).disabled(!canModifyFiles)

            Button("Select All") {
                selection = Set(items.map(\.id))
            }
            .disabled(items.isEmpty)

            Divider()

            Button("Paste", action: onPaste)
                .disabled(!canPaste || !canModifyFiles)
        }
    }

    private func updateSelection(for id: UUID) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(id) { selection.remove(id) }
            else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    @ViewBuilder
    private func itemContextMenu(for item: DemoEntry) -> some View {
        if pane == .mac, FinderOpenTarget.target(for: item) != nil {
            Button("Show in Finder", systemImage: "folder") {
                openInFinder(item)
            }
            Divider()
        }

        Button("New Folder", action: onNewFolder).disabled(!canModifyFiles)

        Divider()

        Button("Properties") {
            onAction(.properties, item)
        }
        .disabled(!canModifyFiles)

        Divider()

        Button("Copy") {
            onAction(.copy, item)
        }.disabled(!canModifyFiles)

        Button("Cut") {
            onAction(.cut, item)
        }.disabled(!canModifyFiles)

        Divider()

        if showCrossPaneActions {
            Button("Copy to \(otherPaneTitle)") {
                onAction(.copyToOther, item)
            }.disabled(!canModifyFiles)

            Button("Move to \(otherPaneTitle)") {
                onAction(.moveToOther, item)
            }.disabled(!canModifyFiles)

            Divider()
        }

        Button("Delete", role: .destructive) {
            onAction(.delete, item)
        }.disabled(!canModifyFiles)
    }

    private func openInFinder(_ item: DemoEntry) {
        guard let target = FinderOpenTarget.target(for: item) else { return }
        switch target {
        case .selectFileInContainingFolder(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openDirectory(let url):
            _ = NSWorkspace.shared.open(url)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            Text("This folder is empty")
                .font(.headline)

            Text("No visible files in this folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var otherPaneTitle: String {
        pane == .mac ? "Android Device" : "This Mac"
    }

    private var deviceColor: Color {
        switch pane {
        case .mac:
            return Color(nsColor: .controlAccentColor)
        case .android:
            return Color.secondary
        }
    }
}

private struct OpenMTPExternalDropReceiver: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onInternalDrop: (String) -> Void
    let onExternalFileDrop: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> DropReceiverView {
        let view = DropReceiverView()
        view.registerForDraggedTypes([
            NSPasteboard.PasteboardType(OpenMTPDragType.payload.identifier),
            .string,
            .fileURL
        ])
        context.coordinator.parent = self
        view.coordinator = context.coordinator
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        MTPShuttleDNDLogger.log("AppKit receiver created")
        return view
    }

    func updateNSView(_ nsView: DropReceiverView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSDraggingDestination {
        var parent: OpenMTPExternalDropReceiver
        var activeDragSession = false

        init(_ parent: OpenMTPExternalDropReceiver) {
            self.parent = parent
        }

        private var internalPasteboardType: NSPasteboard.PasteboardType {
            NSPasteboard.PasteboardType(OpenMTPDragType.payload.identifier)
        }

        private func hasInternalPayload(_ draggingInfo: NSDraggingInfo) -> Bool {
            let types = draggingInfo.draggingPasteboard.types ?? []
            return types.contains(internalPasteboardType)
                || types.contains(.string)
        }

        private func localPromisePayload(_ draggingInfo: NSDraggingInfo) -> String? {
            guard let source = draggingInfo.draggingSource as? MTPShuttleFilePromiseDragSource.DragSourceView,
                  let encoded = source.internalPayload,
                  DemoDragPayload.decode(encoded) != nil else { return nil }
            return encoded
        }

        private func isInternalDrag(_ draggingInfo: NSDraggingInfo) -> Bool {
            if localPromisePayload(draggingInfo) != nil { return true }
            let pasteboard = draggingInfo.draggingPasteboard

            if pasteboard.types?.contains(internalPasteboardType) == true {
                return true
            }

            guard pasteboard.types?.contains(.string) == true else {
                return false
            }

            if let value = pasteboard.string(forType: .string) {
                return DemoDragPayload.decode(value) != nil
            }

            return false
        }

        private func acceptsFinderFiles(_ draggingInfo: NSDraggingInfo) -> Bool {
            guard !isInternalDrag(draggingInfo) else {
                return false
            }

            return draggingInfo.draggingPasteboard.types?.contains(.fileURL) == true
        }

        private func readInternalPayload(from pasteboard: NSPasteboard) -> String? {
            if let data = pasteboard.data(forType: internalPasteboardType),
               let encoded = String(data: data, encoding: .utf8),
               DemoDragPayload.decode(encoded) != nil {
                return encoded
            }

            if let encoded = pasteboard.string(forType: .string),
               DemoDragPayload.decode(encoded) != nil {
                return encoded
            }

            for item in pasteboard.pasteboardItems ?? [] {
                if let data = item.data(forType: internalPasteboardType),
                   let encoded = String(data: data, encoding: .utf8),
                   DemoDragPayload.decode(encoded) != nil {
                    return encoded
                }

                if let encoded = item.string(forType: .string),
                   DemoDragPayload.decode(encoded) != nil {
                    return encoded
                }
            }

            if let objects = pasteboard.readObjects(
                forClasses: [NSString.self],
                options: nil
            ) as? [NSString],
               let encoded = objects.first as String?,
               DemoDragPayload.decode(encoded) != nil {
                return encoded
            }

            return nil
        }

        func draggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
            MTPShuttleDNDLogger.log("AppKit draggingEntered types=\(draggingInfo.draggingPasteboard.types ?? [])")

            if isInternalDrag(draggingInfo) {
                activeDragSession = true
                parent.isTargeted = true
                MTPShuttleDNDLogger.log("AppKit draggingEntered INTERNAL accepted")
                return .copy
            }

            guard acceptsFinderFiles(draggingInfo) else {
                activeDragSession = false
                parent.isTargeted = false
                MTPShuttleDNDLogger.log("AppKit draggingEntered rejected")
                return []
            }

            activeDragSession = true
            parent.isTargeted = true
            MTPShuttleDNDLogger.log("AppKit draggingEntered FINDER accepted")
            return .copy
        }

        func draggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
            if isInternalDrag(draggingInfo) {
                activeDragSession = true
                parent.isTargeted = true
                return .copy
            }

            guard acceptsFinderFiles(draggingInfo) else {
                activeDragSession = false
                parent.isTargeted = false
                return []
            }

            activeDragSession = true
            parent.isTargeted = true
            return .copy
        }

        func draggingExited(_ draggingInfo: NSDraggingInfo?) {
            activeDragSession = false
            parent.isTargeted = false
            MTPShuttleDNDLogger.log("AppKit draggingExited")
        }

        func prepareForDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
            let accepted = isInternalDrag(draggingInfo) || acceptsFinderFiles(draggingInfo)
            MTPShuttleDNDLogger.log("AppKit prepareForDragOperation accepted=\(accepted)")
            return accepted
        }

        func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
            defer {
                activeDragSession = false
                parent.isTargeted = false
            }

            let pasteboard = draggingInfo.draggingPasteboard

            if isInternalDrag(draggingInfo) {
                MTPShuttleDNDLogger.log("AppKit perform INTERNAL types=\\(pasteboard.types ?? [])")

                guard let encoded = localPromisePayload(draggingInfo) ?? readInternalPayload(from: pasteboard) else {
                    MTPShuttleDNDLogger.log("AppKit INTERNAL payload read FAILED")
                    return false
                }

                MTPShuttleDNDLogger.log("AppKit INTERNAL payload read OK length=\(encoded.count)")
                parent.onInternalDrop(encoded)
                return true
            }

            guard acceptsFinderFiles(draggingInfo) else {
                MTPShuttleDNDLogger.log("AppKit perform rejected")
                return false
            }

            let objects = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            )

            let urls = (objects as? [NSURL])?.map { $0 as URL } ?? []
            MTPShuttleDNDLogger.log("AppKit Finder URLs=\\(urls)")

            guard !urls.isEmpty else {
                MTPShuttleDNDLogger.log("AppKit Finder URL read FAILED")
                return false
            }

            parent.onExternalFileDrop(urls)
            return true
        }
    }

    final class DropReceiverView: NSView {
        var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else {
                return super.hitTest(point)
            }

            switch event.type {
            case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                 .leftMouseUp, .rightMouseUp, .otherMouseUp:
                // Keep the receiver in the hit-test path through mouse-up. AppKit
                // can send draggingExited while the cursor crosses the SwiftUI
                // overlay, even though the drop is still being completed.
                return self

            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                return nil

            default:
                return super.hitTest(point)
            }
        }
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            coordinator?.draggingEntered(sender) ?? []
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            coordinator?.draggingUpdated(sender) ?? []
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            coordinator?.draggingExited(sender)
        }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            coordinator?.prepareForDragOperation(sender) ?? false
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            coordinator?.performDragOperation(sender) ?? false
        }
    }
}

private struct FileRowView: View {
    let item: DemoEntry
    let isSelected: Bool

    private var selectionBackground: Color {
        Color(nsColor: .selectedContentBackgroundColor)
    }

    private var selectionText: Color {
        Color(nsColor: .selectedMenuItemTextColor)
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isSelected
                        ? selectionText
                        : (item.isDirectory
                            ? Color(nsColor: .controlAccentColor)
                            : Color.secondary)
                )
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? selectionText : .primary)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        isSelected
                            ? selectionText.opacity(0.82)
                            : Color.secondary
                    )
            }

            Spacer()

            if let size = item.sizeLabel {
                Text(size)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(
                        isSelected
                            ? selectionText.opacity(0.82)
                            : Color.secondary
                    )
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        isSelected
                            ? selectionText.opacity(0.82)
                            : Color.secondary
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? selectionBackground : Color.clear)
        )
    }
}

private struct FileGridItemView: View {
    let item: DemoEntry
    let isSelected: Bool

    private var selectionBackground: Color {
        Color(nsColor: .selectedContentBackgroundColor)
    }

    private var selectionText: Color {
        Color(nsColor: .selectedMenuItemTextColor)
    }

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: item.systemImage)
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isSelected
                        ? selectionText
                        : (item.isDirectory
                            ? Color(nsColor: .controlAccentColor)
                            : Color.secondary)
                )

            Text(item.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? selectionText : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let size = item.sizeLabel {
                Text(size)
                    .font(.caption)
                    .foregroundStyle(
                        isSelected
                            ? selectionText.opacity(0.82)
                            : Color.secondary
                    )
            } else {
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        isSelected
                            ? selectionText.opacity(0.82)
                            : Color.secondary
                    )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? selectionBackground
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
    }
}
