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
        let data = try! JSONSerialization.data(withJSONObject: [
            "storageId": storageID, "fullPath": fullPath,
            "recursive": false, "skipDisallowedFiles": false, "skipHiddenFiles": false
        ])
        return String(decoding: data, as: UTF8.self)
    }
}

enum MTPDirectory {
    static func entries(from response: KalamResponse, storageID: UInt32) throws -> [DemoEntry] {
        guard response.isSuccess else {
            throw MTPServiceError.backend(type: response.errorType ?? "MTP",
                                          message: response.errorMessage ?? "Unable to read folder")
        }

        guard let records = records(from: response.data) else {
            throw KalamBridgeError.invalidResponse("Missing directory data")
        }

        let parsed = records.compactMap { value -> DemoEntry? in
            guard let object = value.objectValue else { return nil }
            guard let name = string(object, keys: ["name", "Name", "filename", "fileName"]),
                  !name.isEmpty,
                  let remotePath = string(object, keys: ["path", "fullPath", "fullpath"]),
                  object.value(forKeyIgnoringCase: "isFolder") != nil || object.value(forKeyIgnoringCase: "isDir") != nil || object.value(forKeyIgnoringCase: "isDirectory") != nil else { return nil }

            let isFolder = bool(object, keys: ["isFolder", "isDir", "isDirectory", "folder", "directory"])
            let size = integer(object, keys: ["size", "Size", "fileSize"])
            let objectID = UInt32(clamping: integer(object, keys: ["objectId", "objectID", "id"]) ?? 0)

            return DemoEntry(
                id: identity(storageID: storageID, objectID: objectID, path: remotePath),
                name: name,
                subtitle: isFolder ? "Folder" : "File",
                sizeBytes: isFolder ? nil : size.flatMap { Int(exactly: $0) },
                isDirectory: isFolder,
                storageID: storageID,
                remotePath: remotePath,
                objectID: objectID
            )
        }

        guard parsed.count == records.count else {
            throw KalamBridgeError.invalidResponse("Directory entry is missing a required name")
        }
        return parsed.sorted(by: DemoEntry.browserOrder)
    }

    private static func records(from value: KalamJSONValue?) -> [KalamJSONValue]? {
        guard let value else { return nil }
        if case .null = value { return [] }
        if let array = value.arrayValue { return array }
        if let object = value.objectValue {
            for key in ["data", "files", "items", "entries", "children"] {
                if let nested = object.value(forKeyIgnoringCase: key)?.arrayValue {
                    return nested
                }
            }
        }
        return nil
    }

    private static func string(_ object: [String: KalamJSONValue], keys: [String]) -> String? {
        object.firstString(forKeys: keys)
    }

    private static func integer(_ object: [String: KalamJSONValue], keys: [String]) -> Int64? {
        for key in keys {
            if let value = object.value(forKeyIgnoringCase: key)?.intValue {
                return Int64(value)
            }
        }
        return nil
    }

    private static func bool(_ object: [String: KalamJSONValue], keys: [String]) -> Bool {
        for key in keys {
            guard let value = object.value(forKeyIgnoringCase: key) else { continue }
            switch value {
            case .bool(let result):
                return result
            case .number(let result):
                return result != 0
            case .string(let result):
                return ["true", "1", "yes", "folder", "directory"].contains(result.lowercased())
            default:
                continue
            }
        }
        return false
    }

    private static func pathBase(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? ""
    }

    static func identity(storageID: UInt32, objectID: UInt32, path: String? = nil) -> UUID {
        if objectID != 0 {
            return UUID(uuidString: String(format: "%08x-0000-0000-0000-%012llx", storageID, UInt64(objectID)))!
        }
        let seed = "\(storageID):\(path ?? "")"
        let hash = UInt64(seed.utf8.reduce(0) { ($0 &* 131) &+ UInt64($1) })
        return UUID(uuidString: String(format: "%08x-0000-0000-0000-%012llx", storageID, hash & 0x0000ffffffffffff))!
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
