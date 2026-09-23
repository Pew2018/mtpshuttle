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
            return "Not connected"
        case .connecting:
            return "Connecting…"
        case .connected:
            return "Connected"
        case .failed:
            return "Connection failed"
        }
    }
}

@MainActor
final class MTPService: ObservableObject {
    @Published private(set) var state: MTPConnectionState = .disconnected
    @Published private(set) var device: MTPDeviceSummary?
    @Published private(set) var storages: [MTPStorageSummary] = []
    
    @Published private(set) var entries: [DemoEntry] = []
    @Published private(set) var isBrowsing = false
    @Published private(set) var browseError: String?
    private var browseGeneration = UUID()

    func browse(path: String) async {
        let request = UUID()
        browseGeneration = request
        entries = []
        browseError = nil
        isBrowsing = false
        guard isConnected, path != "/" else { return }
        guard let location = MTPBrowsePath(browserPath: path),
              storages.contains(where: { $0.storageID == location.storageID }) else {
            browseError = "This storage is no longer available. Return to Storages and refresh."
            return
        }
        isBrowsing = true
        do {
            let response = try await KalamBridge.shared.walk(location)
            guard request == browseGeneration else { return }
            entries = try MTPDirectory.entries(from: response, storageID: location.storageID)
            DebugLogger.info("MTP directory loaded: \(entries.count) entries")
        } catch {
            guard request == browseGeneration else { return }
            browseError = "Unable to read this folder: \(error.localizedDescription)"
            DebugLogger.error("MTP directory read failed: \(error.localizedDescription)")
        }
        isBrowsing = false
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
            return "MTP · Connected"
        case .connecting:
            return "MTP · Connecting…"
        case .failed(let message):
            return "MTP · \(message)"
        case .disconnected:
            return "MTP · Not connected"
        }
    }
    
    var statusText: String {
        switch state {
        case .connected:
            return "\(deviceTitle) · \(storages.count) storage(s)"
        case .connecting:
            return "Connecting to Android device…"
        case .failed(let message):
            return message
        case .disconnected:
            return "Connect an Android device in MTP mode"
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
        
        state = .connecting
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
            DebugLogger.info("MTP connection ready; storages=\(storages.count)")
        } catch {
            state = .failed(error.localizedDescription)
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
            state = .failed(error.localizedDescription)
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
        
        browseGeneration = UUID()
        entries = []
        browseError = nil
        isBrowsing = false
        state = .disconnected
        device = nil
        storages = []
    }

    func upload(sources: [String], destination: String, storageID: UInt32) async throws {
        let response = try await performNativeCall {
            try await KalamBridge.shared.upload(storageID: storageID, sources: sources, destination: destination)
        }
        guard response.isSuccess else {
            throw MTPServiceError.backend(
                type: response.errorType ?? "Upload failed",
                message: response.errorMessage ?? "Unable to upload files"
            )
        }
    }

    func download(sources: [String], destination: String, storageID: UInt32) async throws {
        let response = try await performNativeCall {
            try await KalamBridge.shared.download(storageID: storageID, sources: sources, destination: destination)
        }
        guard response.isSuccess else {
            throw MTPServiceError.backend(
                type: response.errorType ?? "Download failed",
                message: response.errorMessage ?? "Unable to download files"
            )
        }
    }

    func delete(files: [String], storageID: UInt32) async throws {
        let response = try await performNativeCall {
            try await KalamBridge.shared.delete(storageID: storageID, files: files)
        }
        guard response.isSuccess else {
            throw MTPServiceError.backend(type: response.errorType ?? "Delete failed",
                                          message: response.errorMessage ?? "Unable to delete files")
        }
    }

    func makeDirectory(path: String, storageID: UInt32) async throws {
        let response = try await performNativeCall {
            try await KalamBridge.shared.makeDirectory(storageID: storageID, path: path)
        }
        guard response.isSuccess else {
            throw MTPServiceError.backend(type: response.errorType ?? "Create folder failed",
                                          message: response.errorMessage ?? "Unable to create folder")
        }
    }
}

enum MTPServiceError: LocalizedError {
    case backend(type: String, message: String)
    case noStorages
    
    var errorDescription: String? {
        switch self {
        case .backend(let type, let message):
            return "\(type): \(message)"
        case .noStorages:
            return "Kalam connected to the device but returned no storage volumes."
        }
    }
}
