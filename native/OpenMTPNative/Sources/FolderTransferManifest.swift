import CryptoKit
import Foundation

struct FolderTransferManifestEntry: Equatable {
    let relativePath: String
    let isDirectory: Bool
    let sizeBytes: Int64?
    let contentHash: String?

    init(
        relativePath: String,
        isDirectory: Bool,
        sizeBytes: Int64?,
        contentHash: String? = nil
    ) {
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.sizeBytes = sizeBytes
        self.contentHash = contentHash
    }
}

enum FolderTransferManifest {
    static func localEntries(at root: URL) throws -> [FolderTransferManifestEntry] {
        try localEntries(at: root, includingContentHashes: false)
    }

    private static func localEntries(
        at root: URL,
        includingContentHashes: Bool
    ) throws -> [FolderTransferManifestEntry] {
        let rootURL = root.standardizedFileURL.resolvingSymlinksInPath()
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
            let childPath = child.standardizedFileURL.resolvingSymlinksInPath().path
            let rootPrefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
            guard childPath.hasPrefix(rootPrefix) else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let relativePath = String(childPath.dropFirst(rootPrefix.count))
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
                var contentHash: String?
                if includingContentHashes {
                    contentHash = try sha256(at: child)
                }
                result.append(FolderTransferManifestEntry(
                    relativePath: relativePath,
                    isDirectory: false,
                    sizeBytes: Int64(size),
                    contentHash: contentHash
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
                  let remoteSize = rhs.sizeBytes,
                  localSize == remoteSize else { return false }
            if let localHash = lhs.contentHash, let remoteHash = rhs.contentHash {
                return localHash == remoteHash
            }
            return true
        }
    }

    static func matchesContent(source: URL, destination: URL) throws -> Bool {
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let destinationAttributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        guard sourceAttributes[.type] as? FileAttributeType != .typeSymbolicLink,
              destinationAttributes[.type] as? FileAttributeType != .typeSymbolicLink else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let sourceValues = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        let destinationValues = try destination.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        guard sourceValues.isDirectory == destinationValues.isDirectory else { return false }

        if sourceValues.isDirectory == true {
            return matches(
                local: try localEntries(at: source, includingContentHashes: true),
                remote: try localEntries(at: destination, includingContentHashes: true)
            )
        }

        guard sourceValues.isRegularFile == true,
              destinationValues.isRegularFile == true,
              let sourceSize = sourceValues.fileSize,
              let destinationSize = destinationValues.fileSize,
              sourceSize == destinationSize else {
            return false
        }
        return try sha256(at: source) == sha256(at: destination)
    }

    private static func sha256(at url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }

        var hasher = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", Int($0)) }.joined()
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
