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
    let canGoUp: Bool
    let canPaste: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onUp: () -> Void
    let onRefresh: () -> Void
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

                    Button(action: onUp) {
                        Image(systemName: "arrow.turn.up.left")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canGoUp)
                    .help("Open parent folder")

                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh this pane")

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
        List(selection: $selection) {
            ForEach(items) { item in
                FileRowView(item: item)
                    .tag(item.id)
                    .contentShape(Rectangle())
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
        .listStyle(.inset)
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

private struct FileRowView: View {
    let item: DemoEntry

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.isDirectory ? Color(nsColor: .controlAccentColor) : Color.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.medium))

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let size = item.sizeLabel {
                Text(size)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
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
                .foregroundStyle(item.isDirectory ? Color(nsColor: .controlAccentColor) : Color.secondary)

            Text(item.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .primary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let size = item.sizeLabel {
                Text(size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    isSelected
                        ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18)
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected
                        ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.40)
                        : .clear,
                    lineWidth: 1
                )
        }
    }
}
