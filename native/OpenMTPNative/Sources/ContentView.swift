import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow

    @State private var fileSystem = DemoFileSystem()
    @State private var leftPane = PaneNavigationState(path: PaneKind.mac.rootPath)
    @State private var rightPane = PaneNavigationState(path: PaneKind.android.rootPath)
    @State private var clipboard: ClipboardPayload?
    @State private var pendingDrop: PendingDrop?
    @State private var pendingFolderDrop: FolderDropRequest?
    @State private var pendingConflict: TransferConflictRequest?
    @State private var pendingExternalDrop: ExternalDropConflictRequest?
    @State private var newFolderPane: PaneKind?
    @State private var newFolderName = "New Folder"
    @State private var operation: DemoOperation?
    @State private var propertyItem: DemoEntry?
    @State private var statusMessage = "Ready"
    @State private var activePane: PaneKind = .mac
    @State private var quickLookURLs: [URL] = []
    @StateObject private var localBrowser = LocalBrowserService()
    @StateObject private var mtpService = MTPService()
    @ObservedObject private var tasks = TaskActivityStore.shared

    @AppStorage("dragDropMode")
    private var dragDropMode = DragDropMode.copy.rawValue

    @AppStorage("androidOnlyMode")
    private var androidOnlyMode = false

    @AppStorage("quickLookPreviewEnabled")
    private var quickLookPreviewEnabled = true

    @State private var suppressFolderPromptThisSession = false
    @State private var folderDragSessionMode: ClipboardMode = .copy

    private var currentDragDropMode: DragDropMode {
        DragDropMode(rawValue: dragDropMode) ?? .copy
    }

    private var workspaceView: some View {
        WorkspaceView(
            fileSystem: $fileSystem,
            leftPane: $leftPane,
            rightPane: $rightPane,
            clipboard: $clipboard,
            androidOnlyMode: androidOnlyMode,
            operation: tasks.current.map { DemoOperation(title: $0.title, detail: $0.step, progress: $0.fraction ?? 0) } ?? operation,
            operationIndeterminate: tasks.current != nil && tasks.current?.fraction == nil,
            onShowTasks: { openWindow(id: "tasks") },
            onCancelTask: { tasks.cancel() },
            statusMessage: statusMessage,
            onOpen: open,
            onBack: goBack,
            onForward: goForward,
            onRefresh: refresh,
            onNavigate: navigateTo,
            onAction: performAction,
            onNewFolder: createFolder,
            onPaste: paste,
            onInternalDrop: handleInternalDrop,
            onExternalFileDrop: handleExternalFileDrop,
            onExternalDragProvider: makeExternalDragProvider,
            mtpService: mtpService,
            localBrowser: localBrowser
        )
    }

    var body: some View {
        AnyView(workspaceView)
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
        .sheet(item: $pendingFolderDrop) { request in
            FolderDropConfirmationView(
                request: request,
                onDecision: finishFolderDrop,
                onCancel: {
                    pendingFolderDrop = nil
                }
            )
        }
        .alert(item: $propertyItem) { item in
            Alert(
                title: Text(item.name),
                message: Text(propertyDescription(for: item)),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            transferConflictTitle,
            isPresented: Binding(
                get: { pendingConflict != nil },
                set: { if !$0 { pendingConflict = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("覆盖已有文件") { resolveConflict(.overwrite) }
            Button("全部重命名（添加 .1、.2…）") { resolveConflict(.rename) }
            Button("取消", role: .cancel) { pendingConflict = nil }
        } message: {
            Text(transferConflictMessage)
        }
        .confirmationDialog(
            externalConflictTitle,
            isPresented: Binding(
                get: { pendingExternalDrop != nil },
                set: { if !$0 { pendingExternalDrop = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("覆盖已有项目") { resolveExternalConflict(.overwrite) }
            Button("重命名冲突项目") { resolveExternalConflict(.rename) }
            Button("取消", role: .cancel) { pendingExternalDrop = nil }
        } message: {
            Text(externalConflictMessage)
        }
        .alert(
            "新建文件夹",
            isPresented: Binding(
                get: { newFolderPane != nil },
                set: { if !$0 { newFolderPane = nil } }
            )
        ) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) {}
            Button("创建") { commitNewFolder() }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("将在当前目录创建文件夹")
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
        .background {
            OpenMTPQuickLookHost(
                urls: $quickLookURLs,
                onPreviewEnded: handleQuickLookEnded
            )
            .frame(width: 1, height: 1)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .openMTPQuickLook)
        ) { _ in
            presentQuickLook()
        }
        .focusedSceneValue(
            \.openMTPEditActions,
            editActions
        )
        .task {
            DebugLogger.startSession()
            await localBrowser.load(path: leftPane.path)
        }
        .onChange(of: leftPane.path) { path in
            Task { await localBrowser.load(path: path) }
        }
        .onChange(of: rightPane.path) { path in
            Task { await mtpService.browse(path: path) }
        }
        .onChange(of: mtpService.isConnected) { _ in
            Task { await mtpService.browse(path: rightPane.path) }
        }
        .onChange(of: leftPane.selection) { selection in
            DebugLogger.verbose("Local selection changed: count=\(selection.count), ids=\(selection.map(String.init).joined(separator: "|"))")
            if !selection.isEmpty {
                rightPane.selection.removeAll()
                activePane = .mac
            }
            if !quickLookURLs.isEmpty {
                updateQuickLookSelection()
            }
        }
        .onChange(of: rightPane.selection) { selection in
            if !selection.isEmpty {
                leftPane.selection.removeAll()
                activePane = .android
            }
        }
    }

    private var transferConflictTitle: String {
        let count = pendingConflict?.conflictNames.count ?? 0
        return count == 1 ? "发现同名项目" : "发现 (count) 个同名项目"
    }

    private var transferConflictMessage: String {
        guard let pendingConflict else { return "" }
        return "\(pendingConflict.conflictNames.joined(separator: "、")) 已存在于 \(pendingConflict.targetPane.title)。选择覆盖原有项目，或将本次操作中的冲突项目重命名。"
    }

    private var externalConflictTitle: String {
        let count = pendingExternalDrop?.conflictNames.count ?? 0
        return count == 1 ? "Finder 项目已存在" : "Finder 项目冲突（\(count) 项）"
    }

    private var externalConflictMessage: String {
        guard let pendingExternalDrop else { return "" }
        return "\(pendingExternalDrop.conflictNames.joined(separator: "、")) 已存在于当前 Android 目录。请选择覆盖已有项目、重命名本次拖入项目，或取消操作。"
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

    private func copySelection() {
        guard !activePaneSelection.isEmpty else { return }
        performAction(.copy, pane: activePane, item: nil)
    }

    private func cutSelection() {
        guard !activePaneSelection.isEmpty else { return }
        performAction(.cut, pane: activePane, item: nil)
    }

    private func pasteSelection() {
        paste(activePane)
    }

    private var editActions: OpenMTPEditActions {
        OpenMTPEditActions(
            copy: copySelection,
            cut: cutSelection,
            paste: pasteSelection,
            selectAll: selectAllCurrentDirectory,
            canCopy: !activePaneSelection.isEmpty,
            canPaste: clipboard != nil,
            canSelectAll: !activePaneEntries.isEmpty
        )
    }

    private var activePaneEntries: [DemoEntry] {
        switch activePane {
        case .mac:
            return localBrowser.entries
        case .android:
            return rightPane.path == PaneKind.android.rootPath ? mtpService.storageEntries : mtpService.entries
        }
    }

    private func selectAllCurrentDirectory() {
        setSelection(Set(activePaneEntries.map(\.id)), for: activePane)
    }

    private var activePaneSelection: Set<UUID> {
        switch activePane {
        case .mac:
            return leftPane.selection
        case .android:
            return rightPane.selection
        }
    }

    private func presentQuickLook() {
        guard quickLookPreviewEnabled, activePane == .mac else { return }
        updateQuickLookSelection()
    }

    private func updateQuickLookSelection() {
        quickLookURLs = localBrowser.entries.filter {
            leftPane.selection.contains($0.id) && !$0.isDirectory
        }.compactMap(\.localURL)
    }

    private func handleQuickLookEnded(_ urls: [URL]) {
        // These are real local files, not temporary demo exports.
        quickLookURLs = []
    }

    private func open(_ pane: PaneKind, _ item: DemoEntry) {
        guard item.isDirectory else {
            if pane == .mac, let url = item.localURL {
                NSWorkspace.shared.open(url)
                return
            }
            propertyItem = item
            return
        }

        switch pane {
        case .mac:
            let nextPath = DemoFileSystem.childPath(leftPane.path, item.name)
            navigate(state: &leftPane, to: nextPath)
        case .android:
            guard let storageID = item.storageID, let remotePath = item.remotePath else { return }
            let suffix = remotePath.split(separator: "/").joined(separator: "/")
            let nextPath = "/\(storageID)/" + (suffix.isEmpty ? "" : suffix + "/")
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
        guard !ids.isEmpty || action == .properties else { return }

        switch action {
        case .properties:
            let items = pane == .mac ? localBrowser.entries : (rightPane.path == "/" ? mtpService.storageEntries : mtpService.entries)
            let fallback = items.first { ids.contains($0.id) }
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
            deleteItems(ids, pane: pane)

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

    private func handleInternalDrop(_ encoded: String, targetPane: PaneKind) {
        guard let payload = DemoDragPayload.decode(encoded) else { return }
        receiveDrop(payload, targetPane: targetPane)
    }

    private func handleExternalFileDrop(_ urls: [URL], targetPane: PaneKind) {
        guard !urls.isEmpty else { return }
        receiveExternalFileDrop(urls, targetPane: targetPane)
    }

    private func receiveExternalFileDrop(
        _ urls: [URL],
        targetPane: PaneKind
    ) {
        guard operation == nil else { return }

        guard targetPane == .android else {
            statusMessage = "Finder items can be dropped into Android Device"
            return
        }

        guard mtpService.isConnected else {
            statusMessage = "Connect an Android device before dropping Finder items"
            return
        }

        guard MTPBrowsePath(browserPath: rightPane.path) != nil else {
            statusMessage = "Open an Android storage folder before dropping Finder items"
            return
        }

        let validURLs = urls
            .map(\.standardizedFileURL)
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        guard !validURLs.isEmpty else {
            statusMessage = "The dropped Finder items are no longer available"
            return
        }

        let destinationNames = Set(entries(for: .android, path: rightPane.path).map(\.name))
        let names = validURLs.map(\.lastPathComponent)
        let conflicts = names.filter { destinationNames.contains($0) }
        if !conflicts.isEmpty {
            pendingExternalDrop = ExternalDropConflictRequest(
                urls: validURLs,
                targetPath: rightPane.path,
                conflictNames: Array(NSOrderedSet(array: conflicts)) as? [String] ?? conflicts
            )
            return
        }

        transferExternal(validURLs, targetPath: rightPane.path, resolution: nil)
    }

    private func resolveExternalConflict(_ resolution: TransferConflictResolution) {
        guard let request = pendingExternalDrop else { return }
        pendingExternalDrop = nil
        transferExternal(request.urls, targetPath: request.targetPath, resolution: resolution)
    }

    private func receiveDrop(_ payload: DemoDragPayload, targetPane: PaneKind) {
        OpenMTPDNDLogger.log("ContentView.receiveDrop source=\(payload.sourcePane) target=\(targetPane) path=\(payload.sourcePath) ids=\(payload.itemIDs.count)")
        guard operation == nil else {
            OpenMTPDNDLogger.log("receiveDrop ignored: operation active")
            return
        }
        guard payload.sourcePane != targetPane else {
            OpenMTPDNDLogger.log("receiveDrop rejected: same pane")
            statusMessage = "Drop between the two panes to transfer items"
            return
        }

        let targetPath = paneState(for: targetPane).path
        let pending = PendingDrop(
            payload: payload,
            targetPane: targetPane,
            targetPath: targetPath
        )

        if let folderRequest = makeFolderDropRequest(
            payload: payload,
            targetPane: targetPane,
            targetPath: targetPath
        ) {
            if !suppressFolderPromptThisSession {
                pendingFolderDrop = folderRequest
            } else {
                executeTransfer(for: pending, mode: folderDragSessionMode)
            }
            return
        }

        switch currentDragDropMode {
        case .copy:
            executeTransfer(for: pending, mode: .copy)
        case .move:
            executeTransfer(for: pending, mode: .move)
        case .ask:
            pendingDrop = pending
        }
    }

    private func makeFolderDropRequest(
        payload: DemoDragPayload,
        targetPane: PaneKind,
        targetPath: String
    ) -> FolderDropRequest? {
        let sourceItems = entries(for: payload.sourcePane, path: payload.sourcePath)
        let selected = sourceItems.filter { payload.itemIDs.contains($0.id) }
        let folders = selected.filter(\.isDirectory)

        guard !folders.isEmpty else {
            return nil
        }

        return FolderDropRequest(
            payload: payload,
            targetPane: targetPane,
            targetPath: targetPath,
            itemNames: folders.map(\.name)
        )
    }

    private func finishFolderDrop(
        mode: ClipboardMode,
        suppressFuturePrompts: Bool
    ) {
        guard let request = pendingFolderDrop else {
            return
        }

        pendingFolderDrop = nil

        if suppressFuturePrompts {
            suppressFolderPromptThisSession = true
            folderDragSessionMode = mode
        }

        executeTransfer(
            for: PendingDrop(
                payload: request.payload,
                targetPane: request.targetPane,
                targetPath: request.targetPath
            ),
            mode: mode
        )
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

    private func makeExternalDragProvider(pane: PaneKind, path: String, item: DemoEntry, selectedIDs: Set<UUID>) -> NSItemProvider {
        let itemIDs = selectedIDs.contains(item.id) ? Array(selectedIDs) : [item.id]
        let payload = DemoDragPayload(sourcePane: pane, sourcePath: path, itemIDs: itemIDs)
        if let encoded = payload.encoded {
            // Register the payload as a concrete NSString as well as a custom
            // data representation. AppKit may expose the custom type during
            // dragging but omit its lazy data when the drop is performed.
            let provider = NSItemProvider(object: encoded as NSString)
            provider.registerDataRepresentation(forTypeIdentifier: OpenMTPDragType.payload.identifier,
                                                visibility: .all) { completion in
                completion(encoded.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        return item.localURL.map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
    }

    private func createFolder(_ pane: PaneKind) {
        newFolderPane = pane
        newFolderName = "New Folder"
    }

    private func commitNewFolder() {
        guard let pane = newFolderPane else { return }
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newFolderPane = nil
        let path = paneState(for: pane).path
        Task { @MainActor in
            do {
                if pane == .mac {
                    let destination = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent(name, isDirectory: true)
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                    await localBrowser.load(path: path)
                } else if let location = MTPBrowsePath(browserPath: path) {
                    let base = location.fullPath.hasSuffix("/") ? location.fullPath : location.fullPath + "/"
                    try await mtpService.makeDirectory(path: base + name + "/", storageID: location.storageID)
                    await mtpService.browse(path: path)
                }
                statusMessage = "Created folder \(name)"
                tasks.record("创建文件夹：\(name)", state: "已完成")
            } catch {
                statusMessage = error.localizedDescription
                tasks.record("创建文件夹：\(name)", state: "失败：\(error.localizedDescription)")
            }
        }
    }

    private func deleteItems(_ ids: [UUID], pane: PaneKind) {
        let items = entries(for: pane, path: paneState(for: pane).path).filter { ids.contains($0.id) }
        guard !items.isEmpty else { return }
        let path = paneState(for: pane).path
        Task { @MainActor in
            operation = DemoOperation(title: "Deleting", detail: "\(items.count) item(s)", progress: 0.2)
            do {
                if pane == .mac {
                    for item in items {
                        if let url = item.localURL { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
                    }
                } else if let storage = MTPBrowsePath(browserPath: path) {
                    try await mtpService.delete(files: items.compactMap(\.remotePath), storageID: storage.storageID)
                }
                clearSelection(for: pane)
                statusMessage = "\(items.count) item(s) deleted"
                tasks.record("删除 \(items.count) 个项目", state: "已完成")
                await localBrowser.load(path: leftPane.path)
                await mtpService.browse(path: rightPane.path)
            } catch {
                statusMessage = error.localizedDescription
                tasks.record("删除 \(items.count) 个项目", state: "失败：\(error.localizedDescription)")
            }
            operation = nil
        }
    }

    private func paste(_ targetPane: PaneKind) {
        guard let clipboard else { return }
        transfer(itemIDs: clipboard.itemIDs, sourcePane: clipboard.sourcePane,
                 sourcePath: clipboard.sourcePath, targetPane: targetPane,
                 targetPath: paneState(for: targetPane).path, mode: clipboard.mode,
                 clearClipboardAfterMove: clipboard.mode == .move)
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
        let sources = entries(for: sourcePane, path: sourcePath).filter { itemIDs.contains($0.id) }
        guard !sources.isEmpty else { statusMessage = "No items selected"; return }
        let existing = Set(entries(for: targetPane, path: targetPath).map(\.name))
        let conflicts = sources.map(\.name).filter { existing.contains($0) }
        if !conflicts.isEmpty {
            pendingConflict = TransferConflictRequest(
                itemIDs: itemIDs, sourcePane: sourcePane, sourcePath: sourcePath,
                targetPane: targetPane, targetPath: targetPath, mode: mode,
                clearClipboardAfterMove: clearClipboardAfterMove,
                conflictNames: Array(NSOrderedSet(array: conflicts)) as? [String] ?? conflicts
            )
            return
        }
        beginTransfer(itemIDs: itemIDs, sourcePane: sourcePane, sourcePath: sourcePath,
                      targetPane: targetPane, targetPath: targetPath, mode: mode,
                      clearClipboardAfterMove: clearClipboardAfterMove, resolution: nil)
    }

    private func resolveConflict(_ resolution: TransferConflictResolution) {
        guard let request = pendingConflict else { return }
        pendingConflict = nil
        beginTransfer(itemIDs: request.itemIDs, sourcePane: request.sourcePane, sourcePath: request.sourcePath,
                      targetPane: request.targetPane, targetPath: request.targetPath, mode: request.mode,
                      clearClipboardAfterMove: request.clearClipboardAfterMove, resolution: resolution)
    }

    private func beginTransfer(
        itemIDs: [UUID], sourcePane: PaneKind, sourcePath: String,
        targetPane: PaneKind, targetPath: String, mode: ClipboardMode,
        clearClipboardAfterMove: Bool, resolution: TransferConflictResolution?
    ) {
        let sources = entries(for: sourcePane, path: sourcePath).filter { itemIDs.contains($0.id) }
        guard !sources.isEmpty else { statusMessage = "No items selected"; return }
        let noun = mode == .copy ? "Copying" : "Moving"
        Task { @MainActor in
            guard tasks.current == nil else {
                statusMessage = "请等待当前传输结束"
                return
            }
            let knownBytes = transferByteCount(
                sources,
                sourcePane: sourcePane
            )
            tasks.begin("\(noun) \(sources.count) item(s)", total: knownBytes)
            do {
                try await performTransfer(sources: sources, sourcePane: sourcePane, sourcePath: sourcePath,
                                          targetPane: targetPane, targetPath: targetPath, mode: mode,
                                          resolution: resolution)
                clearSelection(for: sourcePane)
                if clearClipboardAfterMove { clipboard = nil }
                statusMessage = "\(sources.count) item(s) \(mode == .copy ? "copied" : "moved") to \(targetPane.title)"
                await localBrowser.load(path: leftPane.path)
                await mtpService.browse(path: rightPane.path)
                tasks.finish("已完成")
            } catch {
                statusMessage = tasks.cancellationRequested ? "操作已取消" : error.localizedDescription
                tasks.finish(tasks.cancellationRequested ? "已取消" : "失败：\(error.localizedDescription)")
            }
        }
    }

    private func entries(for pane: PaneKind, path: String) -> [DemoEntry] {
        switch pane {
        case .mac: return localBrowser.entries
        case .android: return path == "/" ? mtpService.storageEntries : mtpService.entries
        }
    }

    private func transferExternal(
        _ urls: [URL],
        targetPath: String,
        resolution: TransferConflictResolution?
    ) {
        guard let storage = MTPBrowsePath(browserPath: targetPath) else {
            statusMessage = "Open an Android storage folder before dropping Finder items"
            return
        }

        Task { @MainActor in
            guard tasks.current == nil else {
                statusMessage = "请等待当前传输结束"
                return
            }

            let destinationEntries = entries(for: .android, path: targetPath)
            let knownBytes = urls.reduce(Int64(0)) { sum, url in
                sum + localByteCount(at: url)
            }
            var reserved = Set(destinationEntries.map(\.name))
            var targetNames: [String] = []

            for url in urls {
                let originalName = url.lastPathComponent
                var candidate = originalName
                if resolution == .rename {
                    var index = 1
                    while reserved.contains(candidate) {
                        candidate = "\(originalName).\(index)"
                        index += 1
                    }
                }
                targetNames.append(candidate)
                reserved.insert(candidate)
            }

            tasks.begin("Copying \(urls.count) Finder item(s)", total: knownBytes)

            do {
                if resolution == .overwrite {
                    let names = Set(urls.map(\.lastPathComponent))
                    let conflictingRemote = destinationEntries
                        .filter { names.contains($0.name) }
                        .compactMap(\.remotePath)
                    if !conflictingRemote.isEmpty {
                        try await mtpService.delete(
                            files: conflictingRemote,
                            storageID: storage.storageID
                        )
                    }
                }

                for (index, originalURL) in urls.enumerated() {
                    if tasks.cancellationRequested {
                        throw MTPServiceError.cancelled
                    }

                    let url = originalURL.standardizedFileURL
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        throw CocoaError(.fileNoSuchFile)
                    }

                    let secured = url.startAccessingSecurityScopedResource()
                    defer {
                        if secured {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    let targetName = targetNames[index]
                    if resolution == .rename && targetName != url.lastPathComponent {
                        if FileManager.default.fileExists(atPath: url.path) {
                            if url.hasDirectoryPath {
                                let remoteFolder = storage.fullPath + "/" + targetName
                                try await mtpService.makeDirectory(
                                    path: remoteFolder,
                                    storageID: storage.storageID
                                )
                                try await uploadLocalFolderContents(
                                    url,
                                    remotePath: remoteFolder,
                                    storageID: storage.storageID
                                )
                            } else {
                                let temporary = FileManager.default.temporaryDirectory
                                    .appendingPathComponent("MTP-Shuttle-rename-\(UUID().uuidString)", isDirectory: true)
                                try FileManager.default.createDirectory(
                                    at: temporary,
                                    withIntermediateDirectories: true
                                )
                                defer { try? FileManager.default.removeItem(at: temporary) }

                                let renamedURL = temporary.appendingPathComponent(targetName)
                                try FileManager.default.copyItem(at: url, to: renamedURL)
                                try await mtpService.upload(
                                    sources: [renamedURL.path],
                                    destination: storage.fullPath,
                                    storageID: storage.storageID
                                )
                            }
                        }
                    } else {
                        try await mtpService.upload(
                            sources: [url.path],
                            destination: storage.fullPath,
                            storageID: storage.storageID
                        )
                    }
                }

                if tasks.cancellationRequested {
                    throw MTPServiceError.cancelled
                }
                statusMessage = "\(urls.count) Finder item(s) copied to Android Device"
                await mtpService.browse(path: targetPath)
                tasks.finish("已完成")
            } catch {
                statusMessage = tasks.cancellationRequested
                    ? "操作已取消"
                    : "Finder 拖拽失败：\(error.localizedDescription)"
                tasks.finish(tasks.cancellationRequested ? "已取消" : "失败：\(error.localizedDescription)")
            }
        }
    }

    private func uploadLocalFolderContents(
        _ folderURL: URL,
        remotePath: String,
        storageID: UInt32
    ) async throws {
        let children = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for child in children {
            if tasks.cancellationRequested { throw MTPServiceError.cancelled }
            let values = try child.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                let remoteFolder = remotePath + "/" + child.lastPathComponent
                try await mtpService.makeDirectory(path: remoteFolder, storageID: storageID)
                try await uploadLocalFolderContents(
                    child,
                    remotePath: remoteFolder,
                    storageID: storageID
                )
            } else {
                try await mtpService.upload(
                    sources: [child.path],
                    destination: remotePath,
                    storageID: storageID
                )
            }
        }
    }

    private func transferByteCount(_ sources: [DemoEntry], sourcePane: PaneKind) -> Int64 {
        var total: Int64 = 0

        for item in sources {
            switch sourcePane {
            case .mac:
                guard let url = item.localURL else { return -1 }
                total += localByteCount(at: url)
            case .android:
                guard let size = item.sizeBytes else { return -1 }
                total += Int64(size)
            }
        }

        return total
    }

    private func localByteCount(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
              values.isDirectory == true else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func performTransfer(sources: [DemoEntry], sourcePane: PaneKind, sourcePath: String,
                                 targetPane: PaneKind, targetPath: String, mode: ClipboardMode,
                                 resolution: TransferConflictResolution?) async throws {
        let destinationEntries = entries(for: targetPane, path: targetPath)
        var reserved = Set(destinationEntries.map(\.name))
        var targetNames: [String] = []
        for item in sources {
            if resolution == .rename && reserved.contains(item.name) {
                var index = 1
                var candidate = "\(item.name).\(index)"
                while reserved.contains(candidate) { index += 1; candidate = "\(item.name).\(index)" }
                targetNames.append(candidate)
                reserved.insert(candidate)
            } else {
                targetNames.append(item.name)
                reserved.insert(item.name)
            }
        }
        let conflictNames = Set(sources.map(\.name).filter { name in destinationEntries.contains(where: { $0.name == name }) })
        if sourcePane == .mac && targetPane == .mac {
            let destination = URL(fileURLWithPath: targetPath, isDirectory: true)
            for (index, item) in sources.enumerated() {
                if tasks.cancellationRequested { throw MTPServiceError.cancelled }
                guard let url = item.localURL else { continue }
                let target = destination.appendingPathComponent(targetNames[index])
                if resolution == .overwrite && FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                if mode == .move { try FileManager.default.moveItem(at: url, to: target) }
                else { try FileManager.default.copyItem(at: url, to: target) }
            }
            return
        }
        if sourcePane == .mac && targetPane == .android {
            guard let storage = MTPBrowsePath(browserPath: targetPath) else { throw KalamBridgeError.invalidResponse("Invalid Android destination") }
            let conflictingRemote = destinationEntries.filter { conflictNames.contains($0.name) }.compactMap(\.remotePath)
            if resolution == .overwrite && !conflictingRemote.isEmpty {
                try await mtpService.delete(files: conflictingRemote, storageID: storage.storageID)
            }

            // Kalam can time out when a renamed local folder is handed to its
            // recursive uploader. Materialize renamed folders on the device
            // first, then upload their contents into the new remote path.
            if resolution == .rename {
                for (index, item) in sources.enumerated() {
                    if tasks.cancellationRequested { throw MTPServiceError.cancelled }
                    guard let url = item.localURL else { continue }
                    let remoteName = targetNames[index]
                    if item.isDirectory {
                        let remoteFolder = storage.fullPath + "/" + remoteName
                        try await mtpService.makeDirectory(path: remoteFolder, storageID: storage.storageID)
                        try await uploadLocalFolderContents(
                            url,
                            remotePath: remoteFolder,
                            storageID: storage.storageID
                        )
                    } else {
                        // Upload a temporary copy whose basename is the resolved
                        // conflict name. Uploading the original URL here would
                        // silently recreate the source basename on the device.
                        let temporary = FileManager.default.temporaryDirectory
                            .appendingPathComponent("MTP-Shuttle-rename-(UUID().uuidString)", isDirectory: true)
                        try FileManager.default.createDirectory(
                            at: temporary,
                            withIntermediateDirectories: true
                        )
                        defer { try? FileManager.default.removeItem(at: temporary) }

                        let renamedURL = temporary.appendingPathComponent(remoteName)
                        try FileManager.default.copyItem(at: url, to: renamedURL)
                        try await mtpService.upload(
                            sources: [renamedURL.path],
                            destination: storage.fullPath,
                            storageID: storage.storageID
                        )
                    }
                }
            } else {
                for item in sources {
                    if tasks.cancellationRequested { throw MTPServiceError.cancelled }
                    guard let url = item.localURL else { continue }
                    try await mtpService.upload(
                        sources: [url.path],
                        destination: storage.fullPath,
                        storageID: storage.storageID
                    )
                }
            }

            if mode == .move {
                if tasks.cancellationRequested { throw MTPServiceError.cancelled }
                for item in sources {
                    if let url = item.localURL { try FileManager.default.removeItem(at: url) }
                }
            }
            return
        }
        guard sourcePane == .android && targetPane == .mac,
              let storage = MTPBrowsePath(browserPath: sourcePath) else { throw KalamBridgeError.invalidResponse("Invalid MTP source") }
        let remoteSources = sources.compactMap(\.remotePath)
        let destination = URL(fileURLWithPath: targetPath, isDirectory: true)
        // Keep partial MTP downloads out of the user's destination. In
        // particular, a cancelled move must never delete an Android source.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("MTP-Shuttle-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for remoteSource in remoteSources {
            if tasks.cancellationRequested { throw MTPServiceError.cancelled }
            try await mtpService.download(
                sources: [remoteSource], destination: staging.path, storageID: storage.storageID
            )
        }
        if tasks.cancellationRequested { throw MTPServiceError.cancelled }
        for (index, item) in sources.enumerated() {
            let staged = staging.appendingPathComponent(item.name)
            let target = destination.appendingPathComponent(targetNames[index])
            guard FileManager.default.fileExists(atPath: staged.path) else {
                throw KalamBridgeError.invalidResponse("Downloaded item missing: \(item.name)")
            }
            if resolution == .overwrite && FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: staged, to: target)
        }
        if tasks.cancellationRequested { throw MTPServiceError.cancelled }
        if mode == .move {
            try await mtpService.delete(files: remoteSources, storageID: storage.storageID)
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
            Task {
                await localBrowser.load(path: leftPane.path)
                statusMessage = localBrowser.errorMessage ?? "This Mac refreshed"
            }
        case .android:
            rightPane.selection.removeAll()
            if mtpService.isBrowsing {
                mtpService.cancelBrowse()
                statusMessage = "加载已暂停，已显示当前已加载项目"
                return
            }
            statusMessage = mtpService.isConnected ? "Refreshing Android device…" : "Connecting to Android device…"
            Task {
                await mtpService.refresh()
                await mtpService.browse(path: rightPane.path)
                statusMessage = mtpService.browseError ?? mtpService.statusText
            }
        }
    }

    private func propertyDescription(for item: DemoEntry) -> String {
        let type = item.isDirectory ? "Folder" : item.subtitle
        let size = item.sizeLabel ?? "—"
        let path = item.localURL?.path ?? item.remotePath ?? item.name
        return "Type: \(type)\nSize: \(size)\nPath: \(path)"
    }
}

private struct FolderDropConfirmationView: View {
    let request: FolderDropRequest
    let onDecision: (ClipboardMode, Bool) -> Void
    let onCancel: () -> Void

    @State private var suppressFuturePrompts = false

    private var folderSummary: String {
        switch request.itemNames.count {
        case 1:
            return "“\(request.itemNames[0])”"
        default:
            return "\(request.itemNames.count) folders"
        }
    }

    private var title: String {
        request.itemNames.count == 1
            ? "Copy Folder"
            : "Copy Folders"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(nsColor: .controlAccentColor))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)

                    Text("Copy \(folderSummary) to \(request.targetPane.title)?")
                        .font(.body)
                }
            }

            Text(request.targetPath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Toggle(
                "Don't ask again for folder drags",
                isOn: $suppressFuturePrompts
            )
            .toggleStyle(.checkbox)

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Cut") {
                    onDecision(.move, suppressFuturePrompts)
                }

                Button("Copy") {
                    onDecision(.copy, suppressFuturePrompts)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 430)
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

    let androidOnlyMode: Bool

    let operation: DemoOperation?
    let operationIndeterminate: Bool
    let onShowTasks: () -> Void
    let onCancelTask: () -> Void
    let statusMessage: String
    let onOpen: (PaneKind, DemoEntry) -> Void
    let onBack: (PaneKind) -> Void
    let onForward: (PaneKind) -> Void
    let onRefresh: (PaneKind) -> Void
    let onNavigate: (PaneKind, String) -> Void
    let onAction: (PaneAction, PaneKind, DemoEntry?) -> Void
    let onNewFolder: (PaneKind) -> Void
    let onPaste: (PaneKind) -> Void
    let onInternalDrop: (String, PaneKind) -> Void
    let onExternalFileDrop: ([URL], PaneKind) -> Void
    let onExternalDragProvider: (PaneKind, String, DemoEntry, Set<UUID>) -> NSItemProvider
    @ObservedObject var mtpService: MTPService
    @ObservedObject var localBrowser: LocalBrowserService

    private var macPane: some View {
        FilePaneView(
            pane: .mac,
            isLoading: localBrowser.isLoading,
            errorMessage: localBrowser.errorMessage,
            canModifyFiles: true,
            path: leftPane.path,
            items: localBrowser.entries,
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
            showCrossPaneActions: !androidOnlyMode,
            onInternalDrop: { encoded in
                onInternalDrop(encoded, .mac)
            },
            onExternalFileDrop: { urls in onExternalFileDrop(urls, .mac) },
            onDragProvider: { item, selectedIDs in
                onExternalDragProvider(.mac, leftPane.path, item, selectedIDs)
            }
        )
    }

    private var androidPane: some View {
        FilePaneView(
            pane: .android,
            subtitle: mtpService.deviceSubtitle,
            refreshTitle: mtpService.isConnected ? "Refresh" : "Connect",
            isLoading: mtpService.isBrowsing || mtpService.state == .connecting,
            errorMessage: mtpService.browseError,
            emptyMessage: mtpService.isConnected ? nil : mtpService.statusText,
            breadcrumbs: MTPDirectory.breadcrumbs(path: rightPane.path, storages: mtpService.storages),
            canModifyFiles: true,
            path: rightPane.path,
            items: rightPane.path == PaneKind.android.rootPath ? mtpService.storageEntries : mtpService.entries,
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
            showCrossPaneActions: !androidOnlyMode,
            onInternalDrop: { encoded in
                onInternalDrop(encoded, .android)
            },
            onExternalFileDrop: { urls in onExternalFileDrop(urls, .android) },
            onDragProvider: { item, selectedIDs in
                onExternalDragProvider(.android, rightPane.path, item, selectedIDs)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(mtpService.isConnected ? Color.green : Color.orange).frame(width: 8, height: 8)
                Text(mtpService.statusText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if case .connecting = mtpService.state { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
            if androidOnlyMode {
                androidPane
            } else {
                HStack(spacing: 0) {
                    macPane

                    Divider()

                    androidPane
                }
            }

            Divider()

            if let operation {
                OperationProgressView(operation: operation, indeterminate: operationIndeterminate,
                                      onShowTasks: onShowTasks, onCancel: onCancelTask)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: clipboard == nil ? "checkmark.circle" : "doc.on.clipboard")
                        .foregroundStyle(Color.accentColor.opacity(0.78))

                    Text(statusMessage)
                        .font(.caption)

                    Spacer()

                    Text(mtpService.deviceSubtitle)
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
    let indeterminate: Bool
    let onShowTasks: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onShowTasks) {
                HStack(spacing: 12) {
                    Group {
                        if indeterminate { ProgressView() }
                        else { ProgressView(value: operation.progress) }
                    }
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 360)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(operation.title).font(.caption.weight(.semibold))
                        Text(operation.detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("打开任务详情")

            Spacer()

            Text(indeterminate ? "计算中" : "\(Int(operation.progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
            Button(action: onCancel) { Image(systemName: "xmark.circle") }
                .buttonStyle(.borderless).help("取消当前操作")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

#Preview {
    ContentView()
}
