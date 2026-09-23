import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FilePaneView: View {
    let pane: PaneKind
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
    let onDragProvider: (DemoEntry) -> NSItemProvider

    @State private var viewMode: FileViewMode = .list
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            paneHeader

            Divider()

            if items.isEmpty {
                emptyState
            } else if viewMode == .list {
                listView
            } else {
                gridView
            }

            Divider()

            paneFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .onDrop(
            of: [OpenMTPDragType.payload.identifier],
            isTargeted: $isDropTargeted
        ) { providers in
            handleInternalDrop(providers)
        }
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
        .background {
            OpenMTPExternalDropReceiver(
                isTargeted: $isDropTargeted,
                onExternalFileDrop: onExternalFileDrop
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func handleInternalDrop(_ providers: [NSItemProvider]) -> Bool {
        let typeIdentifier = OpenMTPDragType.payload.identifier

        print("[OpenMTP-DND] SwiftUI onDrop fired, providers=\\(providers.count)")
        for (index, provider) in providers.enumerated() {
            print("[OpenMTP-DND] provider[\\(index)] types=\\(provider.registeredTypeIdentifiers)")
        }

        guard let provider = providers.first(where: {
            $0.registeredTypeIdentifiers.contains(typeIdentifier)
        }) else {
            print("[OpenMTP-DND] SwiftUI onDrop: internal UTI NOT found")
            return false
        }

        print("[OpenMTP-DND] SwiftUI onDrop: internal UTI found")

        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
            print("[OpenMTP-DND] SwiftUI payload callback data=\\(data?.count ?? -1) error=\\(String(describing: error))")

            guard let data,
                  let encoded = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    print("[OpenMTP-DND] SwiftUI payload decode FAILED")
                    onInternalDrop("")
                }
                return
            }

            print("[OpenMTP-DND] SwiftUI payload decode OK length=\\(encoded.count)")

            DispatchQueue.main.async {
                print("[OpenMTP-DND] SwiftUI -> ContentView")
                onInternalDrop(encoded)
            }
        }

        return true
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

                    Text(pane.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Refresh this pane")

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
        let components = DemoFileSystem.breadcrumbComponents(for: path)

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
                        selection = [item.id]
                    }
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            onOpen(item)
                        }
                    )
                    .contextMenu {
                        itemContextMenu(for: item)
                    }
                    .onDrag {
                        onDragProvider(item)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .contextMenu {
            Button("New Folder", action: onNewFolder)

            Divider()

            Button("Paste", action: onPaste)
                .disabled(!canPaste)
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
                        selection = [item.id]
                    }
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            onOpen(item)
                        }
                    )
                    .contextMenu {
                        itemContextMenu(for: item)
                    }
                    .onDrag {
                        onDragProvider(item)
                    }
                }
            }
            .padding(14)
        }
        .contextMenu {
            Button("New Folder", action: onNewFolder)

            Divider()

            Button("Paste", action: onPaste)
                .disabled(!canPaste)
        }
    }

    @ViewBuilder
    private func itemContextMenu(for item: DemoEntry) -> some View {
        Button("Properties") {
            onAction(.properties, item)
        }

        Divider()

        Button("Copy") {
            onAction(.copy, item)
        }

        Button("Cut") {
            onAction(.cut, item)
        }

        Divider()

        if showCrossPaneActions {
            Button("Copy to \(otherPaneTitle)") {
                onAction(.copyToOther, item)
            }

            Button("Move to \(otherPaneTitle)") {
                onAction(.moveToOther, item)
            }

            Divider()
        }

        Button("Delete", role: .destructive) {
            onAction(.delete, item)
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

            Text("Create a folder, paste items, or drop something here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var paneFooter: some View {
        HStack(spacing: 8) {
            Text("\(items.count) items")

            if !selection.isEmpty {
                Text("•")
                    .foregroundStyle(.tertiary)

                Text("\(selection.count) selected")
            }

            Spacer()

            Text(path == pane.rootPath ? "Root folder" : "Ready")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
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
    let onExternalFileDrop: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> DropReceiverView {
        let view = DropReceiverView()
        view.registerForDraggedTypes([.fileURL])
        context.coordinator.parent = self
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DropReceiverView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, NSDraggingDestination {
        var parent: OpenMTPExternalDropReceiver

        init(_ parent: OpenMTPExternalDropReceiver) {
            self.parent = parent
        }

        private func isInternalDrag(_ draggingInfo: NSDraggingInfo) -> Bool {
            let type = NSPasteboard.PasteboardType(OpenMTPDragType.payload.identifier)
            return draggingInfo.draggingPasteboard.types?.contains(type) == true
        }

        private func acceptsFinderFiles(_ draggingInfo: NSDraggingInfo) -> Bool {
            guard !isInternalDrag(draggingInfo) else {
                return false
            }

            return draggingInfo.draggingPasteboard.types?.contains(.fileURL) == true
        }

        func draggingEntered(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
            print("[OpenMTP-DND] AppKit draggingEntered types=\\(draggingInfo.draggingPasteboard.types ?? [])")
            let accepts = acceptsFinderFiles(draggingInfo)
            print("[OpenMTP-DND] AppKit draggingEntered acceptsFinder=\\(accepts)")
            guard accepts else {
                parent.isTargeted = false
                return []
            }

            parent.isTargeted = true
            return .copy
        }

        func draggingUpdated(_ draggingInfo: NSDraggingInfo) -> NSDragOperation {
            print("[OpenMTP-DND] AppKit draggingUpdated types=\\(draggingInfo.draggingPasteboard.types ?? [])")
            let accepts = acceptsFinderFiles(draggingInfo)
            guard accepts else {
                parent.isTargeted = false
                return []
            }

            parent.isTargeted = true
            return .copy
        }

        func draggingExited(_ draggingInfo: NSDraggingInfo?) {
            print("[OpenMTP-DND] AppKit draggingExited")
            parent.isTargeted = false
        }

        func prepareForDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
            let accepts = acceptsFinderFiles(draggingInfo)
            print("[OpenMTP-DND] AppKit prepareForDragOperation acceptsFinder=\\(accepts)")
            return accepts
        }

        func performDragOperation(_ draggingInfo: NSDraggingInfo) -> Bool {
            defer {
                parent.isTargeted = false
            }

            print("[OpenMTP-DND] AppKit performDragOperation types=\\(draggingInfo.draggingPasteboard.types ?? [])")

            guard acceptsFinderFiles(draggingInfo) else {
                print("[OpenMTP-DND] AppKit perform rejected")
                return false
            }

            let pasteboard = draggingInfo.draggingPasteboard
            let objects = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            )

            let urls = (objects as? [NSURL])?.map { $0 as URL } ?? []
            print("[OpenMTP-DND] AppKit Finder URLs=\\(urls)")

            guard !urls.isEmpty else {
                print("[OpenMTP-DND] AppKit Finder URL read FAILED")
                return false
            }

            parent.onExternalFileDrop(urls)
            return true
        }
    }

    final class DropReceiverView: NSView {
        weak var coordinator: Coordinator?

        override func hitTest(_ point: NSPoint) -> NSView? {
            if let event = NSApp.currentEvent {
                switch event.type {
                case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
                    return nil
                default:
                    break
                }
            }

            let result = super.hitTest(point)
            if NSApp.currentEvent?.type == .leftMouseDragged {
                print("[OpenMTP-DND] DropReceiver hitTest result=\\(String(describing: result))")
            }
            return result
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
