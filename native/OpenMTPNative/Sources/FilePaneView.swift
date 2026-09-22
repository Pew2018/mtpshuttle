import SwiftUI

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
    let onOpen: (DemoEntry) -> Void
    let onAction: (PaneAction, DemoEntry?) -> Void
    let onNewFolder: () -> Void
    let onPaste: () -> Void

    @State private var viewMode: FileViewMode = .list

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

            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)

                Text(path)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .padding(12)
        .background(.bar)
    }

    private var listView: some View {
        List(selection: $selection) {
            ForEach(items) { item in
                FileRowView(item: item)
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        onOpen(item)
                    }
                    .contextMenu {
                        itemContextMenu(for: item)
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
                    .onTapGesture(count: 2) {
                        onOpen(item)
                    }
                    .onTapGesture {
                        selection = [item.id]
                    }
                    .contextMenu {
                        itemContextMenu(for: item)
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

            Text("Create a folder or paste items here to continue testing.")
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

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.isDirectory ? Color.accentColor.opacity(0.82) : .secondary)
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
                .foregroundStyle(item.isDirectory ? Color.accentColor.opacity(0.82) : .secondary)

            Text(item.name)
                .font(.subheadline.weight(.medium))
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
                        ? Color.accentColor.opacity(0.10)
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.45) : .clear,
                    lineWidth: 1
                )
        }
    }
}
