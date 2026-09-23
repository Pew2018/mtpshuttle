import Foundation

/// The UI path includes a storage ID; Kalam paths are relative to that volume.
struct MTPBrowsePath: Equatable {
    let storageID: UInt32
    let fullPath: String

    init?(browserPath: String) {
        let parts = browserPath.split(separator: "/")
        guard let first = parts.first, let storage = UInt32(first),
              !parts.contains(".."), !parts.contains(".") else { return nil }
        storageID = storage
        fullPath = "/" + parts.dropFirst().joined(separator: "/")
    }

    var walkJSON: String {
        // Match the existing Electron Kalam.walk request exactly.
        let data = try! JSONSerialization.data(withJSONObject: [
            "storageId": storageID, "fullPath": fullPath,
            "recursive": false, "skipDisallowedFiles": false, "skipHiddenFiles": true
        ])
        return String(decoding: data, as: UTF8.self)
    }
}

enum MTPDirectory {
    private struct Record: Decodable {
        let name: String
        let isFolder: Bool
        let size: Int64
        let path: String
        let objectId: UInt32
    }
    private struct Envelope: Decodable { let data: [Record]? }

    static func entries(from response: KalamResponse, storageID: UInt32) throws -> [DemoEntry] {
        guard response.isSuccess else {
            throw MTPServiceError.backend(type: response.errorType ?? "MTP",
                                          message: response.errorMessage ?? "Unable to read folder")
        }
        guard response.data != nil else {
            throw KalamBridgeError.invalidResponse("Missing directory data")
        }
        // Kalam encodes an empty Go slice as null, not []. Invalid records must
        // produce a visible error instead of silently looking like an empty folder.
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(response.rawJSON.utf8))
        return (envelope.data ?? []).map { record in
            DemoEntry(id: identity(storageID: storageID, objectID: record.objectId),
                      name: record.name, subtitle: record.isFolder ? "Folder" : "File",
                      sizeBytes: record.isFolder ? nil : Int(exactly: record.size),
                      isDirectory: record.isFolder, storageID: storageID,
                      remotePath: record.path, objectID: record.objectId)
        }.sorted(by: DemoEntry.browserOrder)
    }

    static func identity(storageID: UInt32, objectID: UInt32) -> UUID {
        UUID(uuidString: String(format: "%08x-0000-0000-0000-%012llx", storageID, UInt64(objectID)))!
    }

    static func breadcrumbs(path: String, storages: [MTPStorageSummary]) -> [BreadcrumbComponent] {
        var result = [BreadcrumbComponent(id: "/", name: "Storages", path: "/")]
        let parts = path.split(separator: "/").map(String.init)
        var current = "/"
        for (index, part) in parts.enumerated() {
            current += part + "/"
            let name = index == 0 ? (storages.first { String($0.storageID) == part }?.name ?? "Storage") : part
            result.append(BreadcrumbComponent(id: current, name: name, path: current))
        }
        return result
    }
}
