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
    func testFinderOpenTargetSelectsFilesAndOpensDirectories() {
        let fileURL = URL(fileURLWithPath: "/Users/test/Documents/notes.txt")
        let file = DemoEntry(
            id: UUID(), name: "notes.txt", subtitle: "Text", sizeBytes: 1,
            isDirectory: false, localURL: fileURL,
            storageID: nil, remotePath: nil, objectID: nil
        )
        XCTAssertEqual(FinderOpenTarget.target(for: file), .selectFileInContainingFolder(fileURL))

        let folderURL = URL(fileURLWithPath: "/Users/test/Documents/Archive", isDirectory: true)
        let folder = DemoEntry(
            id: UUID(), name: "Archive", subtitle: "Folder", sizeBytes: nil,
            isDirectory: true, localURL: folderURL,
            storageID: nil, remotePath: nil, objectID: nil
        )
        XCTAssertEqual(FinderOpenTarget.target(for: folder), .openDirectory(folderURL))
    }

    func testFinderOpenTargetIgnoresItemsWithoutLocalURLs() {
        let remoteItem = DemoEntry(
            id: UUID(), name: "photo.jpg", subtitle: "Image", sizeBytes: nil,
            isDirectory: false, localURL: nil,
            storageID: 1, remotePath: "/photo.jpg", objectID: 2
        )
        XCTAssertNil(FinderOpenTarget.target(for: remoteItem))
    }

}
