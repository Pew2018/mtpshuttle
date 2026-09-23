import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow

    @State private var fileSystem = DemoFileSystem()
    @State private var leftPane = PaneNavigationState(path: PaneKind.mac.rootPath)
    @State private var rightPane = PaneNavigationState(path: PaneKind.android.rootPath)
    @State private var clipboard: ClipboardPayload?
    @State private var pendingDrop: PendingDrop?
    @State private var operation: DemoOperation?
    @State private var propertyItem: DemoEntry?
    @State private var statusMessage = "Ready"

    @AppStorage("dragDropMode")
    private var dragDropMode = DragDropMode.copy.rawValue

    private var currentDragDropMode: DragDropMode {
        DragDropMode(rawValue: dragDropMode) ?? .copy
    }

    var body: some View {
        WorkspaceView(
            fileSystem: $fileSystem,
            leftPane: $leftPane,
            rightPane: $rightPane,
            clipboard: $clipboard,
            operation: operation,
            statusMessage: statusMessage,
            onOpen: open,
            onBack: goBack,
            onForward: goForward,
            onRefresh: refresh,
            onNavigate: navigateTo,
            onAction: performAction,
            onNewFolder: createFolder,
            onPaste: paste,
            onDrop: handleDrop
        )
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    openWindow(id: "settings")
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .alert(item: $propertyItem) { item in
            Alert(
                title: Text(item.name),
                message: Text(propertyDescription(for: item)),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            pendingDropTitle,
            isPresented: Binding(
                get: { pendingDrop != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDrop = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Copy") {
                finishPendingDrop(mode: .copy)
            }

            Button("Move (Cut)") {
                finishPendingDrop(mode: .move)
            }

            Button("Cancel", role: .cancel) {
                pendingDrop = nil
            }
        } message: {
            Text(pendingDropMessage)
        }
    }

    private var pendingDropTitle: String {
        guard let pendingDrop else {
            return "Drop items"
        }

        let count = pendingDrop.payload.itemIDs.count
        let noun = count == 1 ? "item" : "items"
        return "Drop \(count) \(noun) into \(pendingDrop.targetPane.title)?"
    }

    private var pendingDropMessage: String {
        guard let pendingDrop else {
            return ""
        }

        return "\(pendingDrop.payload.sourcePane.title) → \(pendingDrop.targetPane.title)"
    }

    private func open(_ pane: PaneKind, _ item: DemoEntry) {
        guard item.isDirectory else {
            propertyItem = item
            return
        }

        switch pane {
        case .mac:
            let nextPath = DemoFileSystem.childPath(leftPane.path, item.name)
            navigate(state: &leftPane, to: nextPath)
        case .android:
            let nextPath = DemoFileSystem.childPath(rightPane.path, item.name)
            navigate(state: &rightPane, to: nextPath)
        }
    }

    private func goBack(_ pane: PaneKind) {
        switch pane {
        case .mac:
            guard let previous = leftPane.back.popLast() else { return }
            leftPane.forward.append(leftPane.path)
            leftPane.path = previous
            leftPane.selection.removeAll()
        case .android:
            guard let previous = rightPane.back.popLast() else { return }
            rightPane.forward.append(rightPane.path)
            rightPane.path = previous
            rightPane.selection.removeAll()
        }

        statusMessage = "\(pane.title) went back"
    }

    private func goForward(_ pane: PaneKind) {
        switch pane {
        case .mac:
            guard let next = leftPane.forward.popLast() else { return }
            leftPane.back.append(leftPane.path)
            leftPane.path = next
            leftPane.selection.removeAll()
        case .android:
            guard let next = rightPane.forward.popLast() else { return }
            rightPane.back.append(rightPane.path)
            rightPane.path = next
            rightPane.selection.removeAll()
        }

        statusMessage = "\(pane.title) went forward"
    }

    private func navigateTo(_ pane: PaneKind, _ path: String) {
        switch pane {
        case .mac:
            navigate(state: &leftPane, to: path)
        case .android:
            navigate(state: &rightPane, to: path)
        }

        statusMessage = "\(pane.title) opened \(path)"
    }

    private func navigate(state: inout PaneNavigationState, to path: String) {
        guard path != state.path else {
            state.selection.removeAll()
            return
        }

        state.back.append(state.path)
        state.path = path
        state.forward.removeAll()
        state.selection.removeAll()
    }

    private func performAction(_ action: PaneAction, pane: PaneKind, item: DemoEntry?) {
        guard operation == nil else { return }

        let ids = selectedIDs(for: pane, item: item)
        guard !ids.isEmpty else { return }

        switch action {
        case .properties:
            let fallback = fileSystem.entries(
                for: pane,
                at: paneState(for: pane).path
            ).first { ids.contains($0.id) }
            propertyItem = item ?? fallback

        case .copy:
            clipboard = ClipboardPayload(
                sourcePane: pane,
                sourcePath: paneState(for: pane).path,
                itemIDs: ids,
                mode: .copy
            )
            statusMessage = "\(ids.count) item(s) copied"

        case .cut:
            clipboard = ClipboardPayload(
                sourcePane: pane,
                sourcePath: paneState(for: pane).path,
                itemIDs: ids,
                mode: .move
            )
            statusMessage = "\(ids.count) item(s) ready to move"

        case .delete:
            let path = paneState(for: pane).path
            runOperation(title: "Deleting", count: ids.count) {
                _ = fileSystem.delete(itemIDs: ids, at: path, in: pane)
                clearSelection(for: pane)
                statusMessage = "\(ids.count) item(s) deleted"
            }

        case .copyToOther:
            let other = pane == .mac ? PaneKind.android : .mac
            transfer(
                itemIDs: ids,
                sourcePane: pane,
                sourcePath: paneState(for: pane).path,
                targetPane: other,
                targetPath: paneState(for: other).path,
                mode: .copy
            )

        case .moveToOther:
            let other = pane == .mac ? PaneKind.android : .mac
            transfer(
                itemIDs: ids,
                sourcePane: pane,
                sourcePath: paneState(for: pane).path,
                targetPane: other,
                targetPath: paneState(for: other).path,
                mode: .move
            )
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], targetPane: PaneKind) -> Bool {
        guard operation == nil, let provider = providers.first else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let object = object as? NSString else { return }

            let raw = object as String
            guard let payload = DemoDragPayload.decode(raw) else {
                return
            }

            DispatchQueue.main.async {
                receiveDrop(payload, targetPane: targetPane)
            }
        }

        return true
    }

    private func receiveDrop(_ payload: DemoDragPayload, targetPane: PaneKind) {
        guard operation == nil else { return }
        guard payload.sourcePane != targetPane else {
            statusMessage = "Drop between the two panes to transfer items"
            return
        }

        let targetPath = paneState(for: targetPane).path
        let pending = PendingDrop(
            payload: payload,
            targetPane: targetPane,
            targetPath: targetPath
        )

        switch currentDragDropMode {
        case .copy:
            executeTransfer(for: pending, mode: .copy)
        case .move:
            executeTransfer(for: pending, mode: .move)
        case .ask:
            pendingDrop = pending
        }
    }

    private func finishPendingDrop(mode: ClipboardMode) {
        guard let pendingDrop else { return }
        self.pendingDrop = nil
        executeTransfer(for: pendingDrop, mode: mode)
    }

    private func executeTransfer(for pendingDrop: PendingDrop, mode: ClipboardMode) {
        transfer(
            itemIDs: pendingDrop.payload.itemIDs,
            sourcePane: pendingDrop.payload.sourcePane,
            sourcePath: pendingDrop.payload.sourcePath,
            targetPane: pendingDrop.targetPane,
            targetPath: pendingDrop.targetPath,
            mode: mode
        )
    }

    private func createFolder(_ pane: PaneKind) {
        guard operation == nil else { return }

        let path = paneState(for: pane).path
        let created = fileSystem.createFolder(at: path, in: pane)
        setSelection([created.id], for: pane)
        statusMessage = "Created \(created.name)"
    }

    private func paste(_ targetPane: PaneKind) {
        guard operation == nil, let clipboard else { return }

        let targetPath = paneState(for: targetPane).path
        if clipboard.sourcePane == targetPane,
           clipboard.sourcePath == targetPath,
           clipboard.mode == .move {
            statusMessage = "Nothing to move inside the same folder"
            return
        }

        transfer(
            itemIDs: clipboard.itemIDs,
            sourcePane: clipboard.sourcePane,
            sourcePath: clipboard.sourcePath,
            targetPane: targetPane,
            targetPath: targetPath,
            mode: clipboard.mode,
            clearClipboardAfterMove: clipboard.mode == .move
        )
    }

    private func transfer(
        itemIDs: [UUID],
        sourcePane: PaneKind,
        sourcePath: String,
        targetPane: PaneKind,
        targetPath: String,
        mode: ClipboardMode,
        clearClipboardAfterMove: Bool = false
    ) {
        let noun = mode == .copy ? "Copying" : "Moving"

        runOperation(title: noun, count: itemIDs.count) {
            let transferred = fileSystem.transfer(
                itemIDs: itemIDs,
                from: sourcePane,
                sourcePath: sourcePath,
                to: targetPane,
                targetPath: targetPath,
                mode: mode
            )

            clearSelection(for: sourcePane)

            if clearClipboardAfterMove {
                clipboard = nil
            }

            statusMessage = transferred == 0
                ? "No items transferred"
                : "\(transferred) item(s) \(mode == .copy ? "copied" : "moved") to \(targetPane.title)"
        }
    }

    private func runOperation(title: String, count: Int, mutation: @escaping () -> Void) {
        let steps = max(12, min(24, count * 4))

        Task { @MainActor in
            operation = DemoOperation(
                title: title,
                detail: "\(count) item(s)",
                progress: 0
            )

            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 45_000_000)
                operation?.progress = Double(step) / Double(steps)
            }

            mutation()

            try? await Task.sleep(nanoseconds: 120_000_000)
            operation = nil
        }
    }

    private func selectedIDs(for pane: PaneKind, item: DemoEntry?) -> [UUID] {
        let state = paneState(for: pane)

        if let item, state.selection.contains(item.id) {
            return Array(state.selection)
        }

        return item.map { [$0.id] } ?? Array(state.selection)
    }

    private func paneState(for pane: PaneKind) -> PaneNavigationState {
        switch pane {
        case .mac:
            return leftPane
        case .android:
            return rightPane
        }
    }

    private func clearSelection(for pane: PaneKind) {
        switch pane {
        case .mac:
            leftPane.selection.removeAll()
        case .android:
            rightPane.selection.removeAll()
        }
    }

    private func setSelection(_ ids: Set<UUID>, for pane: PaneKind) {
        switch pane {
        case .mac:
            leftPane.selection = ids
        case .android:
            rightPane.selection = ids
        }
    }

    private func refresh(_ pane: PaneKind) {
        guard operation == nil else { return }

        switch pane {
        case .mac:
            leftPane.selection.removeAll()
            statusMessage = "This Mac refreshed"
        case .android:
            rightPane.selection.removeAll()
            statusMessage = "Android Device refreshed"
        }
    }

    private func propertyDescription(for item: DemoEntry) -> String {
        let type = item.isDirectory ? "Folder" : item.subtitle
        let size = item.sizeLabel ?? "—"
        return "Type: \(type)\\nSize: \(size)\\nID: \(item.id.uuidString)"
    }
}

private struct DemoOperation: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    var progress: Double
}

private struct WorkspaceView: View {
    @Binding var fileSystem: DemoFileSystem
    @Binding var leftPane: PaneNavigationState
    @Binding var rightPane: PaneNavigationState
    @Binding var clipboard: ClipboardPayload?

    let operation: DemoOperation?
    let statusMessage: String
    let onOpen: (PaneKind, DemoEntry) -> Void
    let onBack: (PaneKind) -> Void
    let onForward: (PaneKind) -> Void
    let onRefresh: (PaneKind) -> Void
    let onNavigate: (PaneKind, String) -> Void
    let onAction: (PaneAction, PaneKind, DemoEntry?) -> Void
    let onNewFolder: (PaneKind) -> Void
    let onPaste: (PaneKind) -> Void
    let onDrop: ([NSItemProvider], PaneKind) -> Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                FilePaneView(
                    pane: .mac,
                    path: leftPane.path,
                    items: fileSystem.entries(for: .mac, at: leftPane.path),
                    selection: $leftPane.selection,
                    canGoBack: !leftPane.back.isEmpty,
                    canGoForward: !leftPane.forward.isEmpty,
                    canPaste: clipboard != nil,
                    onBack: { onBack(.mac) },
                    onForward: { onForward(.mac) },
                    onRefresh: { onRefresh(.mac) },
                    onNavigate: { onNavigate(.mac, $0) },
                    onOpen: { onOpen(.mac, $0) },
                    onAction: { action, item in onAction(action, .mac, item) },
                    onNewFolder: { onNewFolder(.mac) },
                    onPaste: { onPaste(.mac) },
                    onDrop: { providers in onDrop(providers, .mac) }
                )

                Divider()

                FilePaneView(
                    pane: .android,
                    path: rightPane.path,
                    items: fileSystem.entries(for: .android, at: rightPane.path),
                    selection: $rightPane.selection,
                    canGoBack: !rightPane.back.isEmpty,
                    canGoForward: !rightPane.forward.isEmpty,
                    canPaste: clipboard != nil,
                    onBack: { onBack(.android) },
                    onForward: { onForward(.android) },
                    onRefresh: { onRefresh(.android) },
                    onNavigate: { onNavigate(.android, $0) },
                    onOpen: { onOpen(.android, $0) },
                    onAction: { action, item in onAction(action, .android, item) },
                    onNewFolder: { onNewFolder(.android) },
                    onPaste: { onPaste(.android) },
                    onDrop: { providers in onDrop(providers, .android) }
                )
            }

            Divider()

            if let operation {
                OperationProgressView(operation: operation)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: clipboard == nil ? "checkmark.circle" : "doc.on.clipboard")
                        .foregroundStyle(Color.accentColor.opacity(0.78))

                    Text(statusMessage)
                        .font(.caption)

                    Spacer()

                    Text("SwiftUI demo • MTP bridge next")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.bar)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct OperationProgressView: View {
    let operation: DemoOperation

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: operation.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: 360)

            VStack(alignment: .leading, spacing: 1) {
                Text(operation.title)
                    .font(.caption.weight(.semibold))

                Text(operation.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(Int(operation.progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

#Preview {
    ContentView()
}
