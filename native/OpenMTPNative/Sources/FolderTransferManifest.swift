import Foundation

struct FolderTransferManifestEntry: Equatable {
    let relativePath: String
    let isDirectory: Bool
    let sizeBytes: Int64?
}

enum FolderTransferManifest {
    static func localEntries(at root: URL) throws -> [FolderTransferManifestEntry] {
        let rootURL = root.standardizedFileURL
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        var result: [FolderTransferManifestEntry] = []
        while let child = enumerator.nextObject() as? URL {
            let attributes = try FileManager.default.attributesOfItem(atPath: child.path)
            if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            let values = try child.resourceValues(forKeys: keys)
            let relativePath = child.pathComponents
                .dropFirst(rootURL.pathComponents.count)
                .joined(separator: "/")
            guard !relativePath.isEmpty else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            if values.isDirectory == true {
                result.append(FolderTransferManifestEntry(
                    relativePath: relativePath,
                    isDirectory: true,
                    sizeBytes: nil
                ))
            } else if values.isRegularFile == true, let size = values.fileSize {
                result.append(FolderTransferManifestEntry(
                    relativePath: relativePath,
                    isDirectory: false,
                    sizeBytes: Int64(size)
                ))
            } else {
                throw CocoaError(.fileReadUnknown)
            }
        }
        if let enumerationError { throw enumerationError }
        return result.sorted { $0.relativePath < $1.relativePath }
    }

    static func matches(
        local: [FolderTransferManifestEntry],
        remote: [FolderTransferManifestEntry]
    ) -> Bool {
        guard local.count == remote.count else { return false }
        let expected = local.sorted { $0.relativePath < $1.relativePath }
        let actual = remote.sorted { $0.relativePath < $1.relativePath }
        return zip(expected, actual).allSatisfy { lhs, rhs in
            guard lhs.relativePath == rhs.relativePath,
                  lhs.isDirectory == rhs.isDirectory else { return false }
            if lhs.isDirectory { return true }
            guard let localSize = lhs.sizeBytes,
                  let remoteSize = rhs.sizeBytes else { return false }
            return localSize == remoteSize
        }
    }
}

enum FolderMoveSafety {
    static func canDeleteOriginals(
        uploadsCompleted: Bool,
        cancelled: Bool,
        integrityVerified: Bool
    ) -> Bool {
        uploadsCompleted && !cancelled && integrityVerified
    }
}
