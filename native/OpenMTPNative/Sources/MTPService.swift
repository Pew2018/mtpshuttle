import Combine
import Foundation

enum MTPConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
    
    var label: String {
        switch self {
        case .disconnected:
            return MTPShuttleText.localized("Not connected")
        case .connecting:
            return MTPShuttleText.localized("Connecting…")
        case .connected:
            return MTPShuttleText.localized("Connected")
        case .failed:
            return MTPShuttleText.localized("Connection failed")
        }
    }
}

@MainActor
final class MTPService: ObservableObject {
    @Published private(set) var state: MTPConnectionState = .disconnected
    @Published private(set) var device: MTPDeviceSummary?
    @Published private(set) var storages: [MTPStorageSummary] = []
    @Published private(set) var connectionSessionID = UUID().uuidString
    
    @Published private(set) var entries: [DemoEntry] = []
    @Published private(set) var isBrowsing = false
    @Published private(set) var browseError: String?
    @Published private(set) var isBrowsePartial = false
    @Published private(set) var connectionError: String?
    private var browseGeneration = UUID()

    func browse(path: String) async {
        if isBrowsing { KalamBridge.shared.cancelCurrentOperation() }
        let request = UUID()
        browseGeneration = request
        browseError = nil
        isBrowsePartial = false
        isBrowsing = false
        entries = []
        guard isConnected, path != "/" else { return }
        guard let location = MTPBrowsePath(browserPath: path),
              storages.contains(where: { $0.storageID == location.storageID }) else {
            browseError = MTPShuttleText.localized("This storage is no longer available. Return to Storages and refresh.")
            return
        }
        isBrowsing = true
        do {
            let response = try await KalamBridge.shared.walk(location) { [weak self] item in
                Task { @MainActor in
                    guard let self, self.browseGeneration == request else { return }
                    if let parsed = try? MTPDirectory.entries(from: item, storageID: location.storageID) {
                        // WalkWithProgress can deliver an item callback just
                        // before or just after the final response. Merge by
                        // stable identity so queued callbacks cannot duplicate
                        // rows after the complete directory replaces the list.
                        var merged = Dictionary(uniqueKeysWithValues: self.entries.map { ($0.id, $0) })
                        for entry in parsed { merged[entry.id] = entry }
                        self.entries = merged.values.sorted(by: DemoEntry.browserOrder)
                    }
                }
            }
            guard request == browseGeneration else { return }
            let completed = try MTPDirectory.entries(from: response, storageID: location.storageID)
            var merged = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            for entry in completed { merged[entry.id] = entry }
            entries = merged.values.sorted(by: DemoEntry.browserOrder)
            DebugLogger.info("MTP directory loaded: \(entries.count) unique entries")
        } catch {
            guard request == browseGeneration else { return }
            if handleConnectionFailure(error) {
                return
            }
            browseError = "Unable to read this folder: \(error.localizedDescription)"
            DebugLogger.error("MTP directory read failed: \(error.localizedDescription)")
        }
        isBrowsing = false
    }

    func cancelBrowse() {
        guard isBrowsing else { return }
        browseGeneration = UUID()
        KalamBridge.shared.cancelCurrentOperation()
        isBrowsing = false
        isBrowsePartial = true
        browseError = entries.isEmpty ? MTPShuttleText.localized("加载已暂停，当前目录暂无已加载项目") : MTPShuttleText.localized("加载已暂停，仅显示已加载的部分项目")
        DebugLogger.info("MTP directory browsing paused by user")
    }

    var isConnected: Bool {
        if case .connected = state {
            return true
        }
        return false
    }
    
    var deviceTitle: String {
        device?.displayName ?? "Android Device"
    }
    
    var deviceSubtitle: String {
        switch state {
        case .connected:
            if let device {
                return "MTP · \(device.detail)"
            }
            return "MTP · " + MTPShuttleText.localized("Connected")
        case .connecting:
            return "MTP · " + MTPShuttleText.localized("Connecting…")
        case .failed(let message):
            return "MTP · \(message)"
        case .disconnected:
            return "MTP · " + MTPShuttleText.localized("Not connected")
        }
    }
    
    var statusText: String {
        switch state {
        case .connected:
            return "\(deviceTitle) · \(storages.count) storage(s)"
        case .connecting:
            return MTPShuttleText.localized("Connecting to Android device…")
        case .failed(let message):
            return message
        case .disconnected:
            return MTPShuttleText.localized("Connect an Android device in MTP mode")
        }
    }
    
    var connectionPrompt: String {
        switch state {
        case .connected:
            return ""
        case .connecting:
            return "Connecting to Android device…"
        case .failed(let message):
            return "Unable to connect to the Android device.\n\(message)\n\nConnect it with USB, select MTP / File Transfer, and allow access on the device."
        case .disconnected:
            let reason = connectionError ?? "The Android device is not connected."
            return "\(reason)\n\nTo connect:\n1. Connect the Android device with a USB cable.\n2. On Android, choose MTP / File Transfer in the USB notification.\n3. Allow access if Android asks for permission."
        }
    }

    var storageEntries: [DemoEntry] {
        storages.map { $0.demoEntry() }
    }
    
    private func performNativeCall<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            try await operation()
        }.value
    }
    
    func connect() async {
        guard state != .connecting else { return }

        connectionSessionID = UUID().uuidString
        state = .connecting
        connectionError = nil
        device = nil
        storages = []
        DebugLogger.info("Starting MTP connection")
        
        do {
            let initialize = try await performNativeCall {
                try await KalamBridge.shared.initialize()
            }
            guard initialize.isSuccess else {
                throw MTPServiceError.backend(
                    type: initialize.errorType ?? "Unknown",
                    message: initialize.errorMessage ?? "Kalam initialization failed"
                )
            }
            
            let summary = MTPDeviceSummary.from(initialize)
            device = summary
            DebugLogger.info(
                "MTP device detected: \(summary.displayName), \(summary.detail)"
            )
            
            let storageResponse = try await performNativeCall {
                try await KalamBridge.shared.fetchStorages()
            }
            guard storageResponse.isSuccess else {
                throw MTPServiceError.backend(
                    type: storageResponse.errorType ?? "Unknown",
                    message: storageResponse.errorMessage ?? "Unable to fetch MTP storages"
                )
            }
            
            storages = MTPStorageSummary.fromArray(storageResponse.data)
            if storages.isEmpty {
                throw MTPServiceError.noStorages
            }
            
            state = .connected
            connectionError = nil
            DebugLogger.info("MTP connection ready; storages=\(storages.count)")
        } catch {
            if !handleConnectionFailure(error) {
                state = .failed(error.localizedDescription)
                connectionError = error.localizedDescription
            }
            DebugLogger.error("MTP connection failed: \(error.localizedDescription)")
        }
    }
    
    func refresh() async {
        guard state != .connecting else { return }
        
        if !isConnected {
            await connect()
            return
        }
        
        DebugLogger.info("Refreshing MTP storages")
        
        do {
            let response = try await performNativeCall {
                try await KalamBridge.shared.fetchStorages()
            }
            guard response.isSuccess else {
                throw MTPServiceError.backend(
                    type: response.errorType ?? "Unknown",
                    message: response.errorMessage ?? "Unable to refresh MTP storages"
                )
            }
            
            let updated = MTPStorageSummary.fromArray(response.data)
            storages = updated
            DebugLogger.info("MTP storages refreshed; count=\(updated.count)")
        } catch {
            if !handleConnectionFailure(error) {
                state = .failed(error.localizedDescription)
                connectionError = error.localizedDescription
            }
            DebugLogger.error("MTP storage refresh failed: \(error.localizedDescription)")
        }
    }
    
    func disconnect() async {
        guard isConnected else { return }
        
        do {
            _ = try await performNativeCall {
                try await KalamBridge.shared.dispose()
            }
            DebugLogger.info("MTP disposed")
        } catch {
            DebugLogger.error("MTP dispose failed: \(error.localizedDescription)")
        }
        
        clearDisconnectedState(message: nil)
    }

    func upload(sources: [String], destination: String, storageID: UInt32) async throws {
        do {
            if TaskActivityStore.shared.cancellationRequested { throw MTPServiceError.cancelled }
            let response = try await performNativeCall {
                try await KalamBridge.shared.upload(storageID: storageID, sources: sources, destination: destination)
            }
            if TaskActivityStore.shared.cancellationRequested { throw MTPServiceError.cancelled }
            guard response.isSuccess else {
                throw MTPServiceError.backend(
                    type: response.errorType ?? "Upload failed",
                    message: response.errorMessage ?? "Unable to upload files"
                )
            }
            TaskActivityStore.shared.finishSegment()
        } catch {
            _ = handleConnectionFailure(error)
            throw error
        }
    }

    func download(sources: [String], destination: String, storageID: UInt32) async throws {
        do {
            if TaskActivityStore.shared.cancellationRequested { throw MTPServiceError.cancelled }
            let response = try await performNativeCall {
                try await KalamBridge.shared.download(storageID: storageID, sources: sources, destination: destination)
            }
            if TaskActivityStore.shared.cancellationRequested { throw MTPServiceError.cancelled }
            guard response.isSuccess else {
                throw MTPServiceError.backend(
                    type: response.errorType ?? "Download failed",
                    message: response.errorMessage ?? "Unable to download files"
                )
            }
            TaskActivityStore.shared.finishSegment()
        } catch {
            _ = handleConnectionFailure(error)
            throw error
        }
    }

    func delete(files: [String], storageID: UInt32) async throws {
        do {
            let response = try await performNativeCall {
                try await KalamBridge.shared.delete(storageID: storageID, files: files)
            }
            guard response.isSuccess else {
                throw MTPServiceError.backend(type: response.errorType ?? "Delete failed",
                                              message: response.errorMessage ?? "Unable to delete files")
            }
        } catch {
            _ = handleConnectionFailure(error)
            throw error
        }
    }

    func makeDirectory(path: String, storageID: UInt32) async throws {
        do {
            let response = try await performNativeCall {
                try await KalamBridge.shared.makeDirectory(storageID: storageID, path: path)
            }
            guard response.isSuccess else {
                throw MTPServiceError.backend(type: response.errorType ?? "Create folder failed",
                                              message: response.errorMessage ?? "Unable to create folder")
            }
        } catch {
            _ = handleConnectionFailure(error)
            throw error
        }
    }
    @discardableResult
    private func handleConnectionFailure(_ error: Error) -> Bool {
        guard isConnectionLoss(error) else { return false }
        clearDisconnectedState(message: "Android device disconnected or is no longer available.")
        DebugLogger.error("MTP connection lost: \(error.localizedDescription)")
        return true
    }

    private func isConnectionLoss(_ error: Error) -> Bool {
        if case MTPServiceError.cancelled = error {
            return false
        }
        let text = error.localizedDescription.lowercased()
        let indicators = [
            "device disconnected", "device is disconnected", "no device",
            "device not found", "not connected", "connection lost",
            "usb", "libusb", "transport", "session", "mtp device"
        ]
        return indicators.contains { text.contains($0) }
    }

    private func clearDisconnectedState(message: String?) {
        browseGeneration = UUID()
        KalamBridge.shared.cancelCurrentOperation()
        entries = []
        browseError = nil
        isBrowsing = false
        state = .disconnected
        connectionError = message
        device = nil
        storages = []
    }
}

enum MTPServiceError: LocalizedError {
    case backend(type: String, message: String)
    case noStorages
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .backend(let type, let message):
            return "\(type): \(message)"
        case .noStorages:
            return MTPShuttleText.localized("Kalam connected to the device but returned no storage volumes.")
        case .cancelled:
            return MTPShuttleText.localized("Operation cancelled")
        }
    }
}
