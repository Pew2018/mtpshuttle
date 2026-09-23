import SwiftUI
import UniformTypeIdentifiers

struct FilePaneView: View {
    let pane: PaneKind
    let path: String
    let items: [DemoEntry]
    @Binding var selection: Set<UUID>
    let canGoBack: Bool
    let canGoForward: Bool
    let canGoUp: Bool
    let canPaste: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onUp: () -> Void
    let onNavigate: (String) -> Void
    let onOpen: (DemoEntry) -> Void
    let onAction: (PaneAction, DemoEntry?) -> Void
    let onNewFolder: () -> Void
    let onPaste: () -> Void
    let onDrop: ([NSItemProvider]) -> Bool

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
        .onDrop(
            of: [UTType.plainText.identifier],
            isTargeted: $isDropTargeted,
            perform: onDrop
        )
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

                Spacer(minLength: 8)

                HStack(spacing: 4) {
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

                    Button(action: onUp) {
                        Image(systemName: "arrow.turn.up.left")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canGoUp)
                    .help("Open parent folder")

                    Menu {
                        Button("New Folder", action: onNewFolder)
                        Button("Paste", action: onPaste)
                            .disabled(!canPaste)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Folder actions")

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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                Image(systemName: "folder")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)

                ForEach(DemoFileSystem.breadcrumbComponents(for: path)) { component in
                    if component.path != DemoFileSystem.breadcrumbComponents(for: path).first?.path {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

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
                            ? .primary
                            : Color.accentColor
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
            LazyVStack(spacing: 2) {
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
                        dragProvider(for: item)
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
                        dragProvider(for: item)
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

    private func dragProvider(for item: DemoEntry) -> NSItemProvider {
        let ids = selection.contains(item.id) ? Array(selection) : [item.id]
        let payload = DemoDragPayload(
            sourcePane: pane,
            sourcePath: path,
            itemIDs: ids
        )

        guard let encoded = payload.encoded else {
            return NSItemProvider(object: NSString(string: item.name))
        }

        return NSItemProvider(object: NSString(string: encoded))
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

        Button("Copy to \(otherPaneTitle)") {
            onAction(.copyToOther, item)
        }

        Button("Move to \(otherPaneTitle)") {
            onAction(.moveToOther, item)
        }

        Divider()

        Button("Delete", role: .destructive) {
            onAction(.delete, item)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor.opacity(0.72))

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
        pane == .mac
            ? Color.blue.opacity(0.74)
            : Color.purple.opacity(0.70)
    }
}

private struct FileRowView: View {
    let item: DemoEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isSelected
                        ? Color.accentColor
                        : (item.isDirectory ? Color.accentColor.opacity(0.82) : .secondary)
                )
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.86) : .secondary)
            }

            Spacer()

            if let size = item.sizeLabel {
                Text(size)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.86) : .secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.86) : Color.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.14)
                        : Color.clear
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.accentColor.opacity(0.30)
                        : Color.clear,
                    lineWidth: 1
                )
        }
        .animation(.easeOut(duration: 0.10), value: isSelected)
    }
}

private struct FileGridItemView: View {
    let item: DemoEntry
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: item.systemImage)
                .font(.system(size: 34))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isSelected
                        ? Color.accentColor
                        : (item.isDirectory ? Color.accentColor.opacity(0.82) : .secondary)
                )

            Text(item.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let size = item.sizeLabel {
                Text(size)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.86) : .secondary)
            } else {
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.86) : .secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.11)
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.42) : .clear,
                    lineWidth: 1
                )
        }
        .animation(.easeOut(duration: 0.10), value: isSelected)
    }
}
