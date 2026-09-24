import XCTest
@testable import SwiftMTP

final class DirectoryTests: XCTestCase {
    func testWalkRequestUsesStorageIDAndVolumeRelativePath() throws {
        let location = try XCTUnwrap(MTPBrowsePath(browserPath: "/65537/DCIM/相机/"))
        XCTAssertEqual(location.storageID, 65537)
        XCTAssertEqual(location.fullPath, "/DCIM/相机")
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(location.walkJSON.utf8)) as? [String: Any])
        XCTAssertEqual(request["fullPath"] as? String, "/DCIM/相机")
        XCTAssertEqual(request["storageId"] as? Int, 65537)
        XCTAssertEqual(request["recursive"] as? Bool, false)
        XCTAssertEqual(MTPBrowsePath(browserPath: "/65537/")?.fullPath, "/")
        XCTAssertNil(MTPBrowsePath(browserPath: "/"))
        XCTAssertNil(MTPBrowsePath(browserPath: "/65537/../"))
    }

    func testGoWalkResponsePreservesIdentityPathsAndLargeSizes() throws {
        let response = try KalamResponse(json: #"{"error":"","errorType":"","data":[{"name":"big.mov","path":"/big.mov","size":5368709120,"isFolder":false,"objectId":42,"parentId":0},{"name":"照片","path":"/照片","size":0,"isFolder":true,"objectId":43,"parentId":0}]}"#)
        let entries = try MTPDirectory.entries(from: response, storageID: 65537)
        XCTAssertEqual(entries.map(\.name), ["照片", "big.mov"])
        XCTAssertEqual(entries[0].remotePath, "/照片")
        XCTAssertEqual(entries[1].sizeBytes, 5_368_709_120)
        XCTAssertEqual(entries[1].objectID, 42)
        XCTAssertEqual(entries[1].id, try MTPDirectory.entries(from: response, storageID: 65537)[1].id)
        XCTAssertNotEqual(entries[1].id, try MTPDirectory.entries(from: response, storageID: 65538)[1].id)
    }

    func testEmptyFolderAndErrorsAreDistinct() throws {
        for data in ["null", "[]"] {
            let response = try KalamResponse(json: "{\"data\":\(data)}")
            XCTAssertTrue(try MTPDirectory.entries(from: response, storageID: 1).isEmpty)
        }
        let failed = try KalamResponse(json: #"{"errorType":"AccessDenied","error":"denied","data":null}"#)
        XCTAssertThrowsError(try MTPDirectory.entries(from: failed, storageID: 1))
        let invalid = try KalamResponse(json: #"{"data":[{"name":"incomplete"}]}"#)
        XCTAssertThrowsError(try MTPDirectory.entries(from: invalid, storageID: 1))
    }

    func testDuplicateStorageLabelsKeepDistinctNavigation() {
        let storages = [UInt32(1), 2].map {
            MTPStorageSummary(id: UUID(), storageID: $0, name: "Internal storage", maxCapacity: nil, freeSpace: nil)
        }
        let trail = MTPDirectory.breadcrumbs(path: "/2/DCIM/", storages: storages)
        XCTAssertEqual(trail.map(\.name), ["Storages", "Internal storage", "DCIM"])
        XCTAssertEqual(trail.map(\.path), ["/", "/2/", "/2/DCIM/"])
    }

    @MainActor
    func testLocalDirectoryUsesRealFilesAndReportsMissingFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("实际文件.txt")
        try Data("real contents".utf8).write(to: file)
        try Data().write(to: root.appendingPathComponent(".hidden"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: false)
        let service = LocalBrowserService()
        await service.load(path: root.path)
        XCTAssertNil(service.errorMessage)
        XCTAssertEqual(service.entries.map(\.name), ["Folder", "实际文件.txt"])
        XCTAssertEqual(service.entries.last?.localURL?.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
        XCTAssertEqual(service.entries.last?.sizeBytes, 13)
        let ids = service.entries.map(\.id)
        await service.load(path: root.path)
        XCTAssertEqual(service.entries.map(\.id), ids)
        await service.load(path: root.appendingPathComponent("missing").path)
        XCTAssertNotNil(service.errorMessage)
        XCTAssertTrue(service.entries.isEmpty)
        XCTAssertFalse(service.isLoading)
    }

    func testFolderTransferManifestIncludesHiddenNestedAndEmptyDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("root hidden".utf8).write(to: root.appendingPathComponent(".root-hidden"))
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        let empty = nested.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try Data("nested hidden".utf8).write(to: nested.appendingPathComponent(".nested-hidden"))

        let manifest = try FolderTransferManifest.localEntries(at: root)
        XCTAssertEqual(
            manifest.map(\.relativePath),
            [".root-hidden", "Nested", "Nested/.nested-hidden", "Nested/Empty"]
        )
        XCTAssertEqual(manifest.first(where: { $0.relativePath == ".root-hidden" })?.sizeBytes, 11)
        XCTAssertEqual(manifest.first(where: { $0.relativePath == "Nested/Empty" })?.isDirectory, true)
    }

    func testEmptyFolderManifestIsVerifiable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = try FolderTransferManifest.localEntries(at: root)
        XCTAssertTrue(local.isEmpty)
        XCTAssertTrue(FolderTransferManifest.matches(local: local, remote: []))
    }

    func testMoveSafetyKeepsSourcesAfterInterruptionCancellationOrFailedVerification() {
        XCTAssertFalse(FolderMoveSafety.canDeleteOriginals(
            uploadsCompleted: false, cancelled: false, integrityVerified: true
        ))
        XCTAssertFalse(FolderMoveSafety.canDeleteOriginals(
            uploadsCompleted: true, cancelled: true, integrityVerified: true
        ))
        XCTAssertFalse(FolderMoveSafety.canDeleteOriginals(
            uploadsCompleted: true, cancelled: false, integrityVerified: false
        ))
        XCTAssertTrue(FolderMoveSafety.canDeleteOriginals(
            uploadsCompleted: true, cancelled: false, integrityVerified: true
        ))
    }

    func testFolderManifestRequiresExactPathsTypesAndFileSizes() {
        let local = [
            FolderTransferManifestEntry(relativePath: ".secret", isDirectory: false, sizeBytes: 7),
            FolderTransferManifestEntry(relativePath: "Nested", isDirectory: true, sizeBytes: nil),
            FolderTransferManifestEntry(relativePath: "Nested/file.bin", isDirectory: false, sizeBytes: 12)
        ]
        XCTAssertTrue(FolderTransferManifest.matches(local: local, remote: local))
        XCTAssertFalse(FolderTransferManifest.matches(local: local, remote: Array(local.dropFirst())))
        XCTAssertFalse(FolderTransferManifest.matches(
            local: local,
            remote: [
                local[0],
                local[1],
                FolderTransferManifestEntry(relativePath: "Nested/file.bin", isDirectory: false, sizeBytes: 11)
            ]
        ))
        XCTAssertFalse(FolderTransferManifest.matches(
            local: local,
            remote: [
                FolderTransferManifestEntry(relativePath: ".secret", isDirectory: true, sizeBytes: nil),
                local[1], local[2]
            ]
        ))
    }
}
