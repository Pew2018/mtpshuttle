import XCTest
@testable import SwiftMTP

final class FavoriteLocationTests: XCTestCase {
    func testLocalFavoriteRoundTripsAndTogglesByPath() throws {
        let entry = DemoEntry(
            id: UUID(), name: "notes.txt", subtitle: "Text",
            sizeBytes: 12, isDirectory: false,
            localURL: URL(fileURLWithPath: "/Users/test/Documents/notes.txt"),
            storageID: nil, remotePath: nil, objectID: nil
        )
        let favorite = FavoriteLocation.from(
            pane: .mac, item: entry, currentPath: "/Users/test/Documents/",
            deviceSerial: nil, deviceSessionID: nil, storageName: nil
        )
        XCTAssertEqual(favorite.parentPath, "/Users/test/Documents/")
        let encoded = FavoriteLocation.encode([favorite])
        XCTAssertEqual(FavoriteLocation.decode(encoded), [favorite])
        XCTAssertTrue(FavoriteLocation.toggled(favorite, in: []).contains(favorite))
        XCTAssertTrue(FavoriteLocation.toggled(favorite, in: [favorite]).isEmpty)
    }

    func testAndroidFavoriteUsesVolumeRelativePathAndRequiresVerifiedDeviceAndStorage() {
        let entry = DemoEntry(
            id: UUID(), name: "photo.jpg", subtitle: "Image",
            sizeBytes: 42, isDirectory: false,
            localURL: nil, storageID: 65537, remotePath: "/DCIM/photo.jpg", objectID: 7
        )
        let favorite = FavoriteLocation.from(
            pane: .android, item: entry, currentPath: "/65537/DCIM/",
            deviceSerial: "SERIAL-A", deviceSessionID: "session-a", storageName: "Internal"
        )
        XCTAssertEqual(favorite.path, "/65537/DCIM/photo.jpg")
        XCTAssertEqual(favorite.parentPath, "/65537/DCIM/")
        let storage = MTPStorageSummary(id: UUID(), storageID: 65537, name: "Internal", maxCapacity: nil, freeSpace: nil)
        XCTAssertTrue(favorite.canResolveAndroid(deviceSerial: "SERIAL-A", sessionID: "new-session", storages: [storage], isConnected: true))
        XCTAssertFalse(favorite.canResolveAndroid(deviceSerial: "SERIAL-B", sessionID: "session-a", storages: [storage], isConnected: true))
        XCTAssertFalse(favorite.canResolveAndroid(deviceSerial: "SERIAL-A", sessionID: "new-session", storages: [], isConnected: true))
        XCTAssertFalse(favorite.canResolveAndroid(deviceSerial: "SERIAL-A", sessionID: "new-session", storages: [storage], isConnected: false))
    }

    func testSerialIdentitySurvivesReconnectAndEmptySerialUsesSessionIdentity() {
        let a = FavoriteLocation(id: UUID(), pane: .android, kind: .file, name: "x", path: "/1/x",
                                 deviceSerial: "SERIAL", deviceSessionID: "old", storageID: 1, storageName: "Phone")
        let b = FavoriteLocation(id: UUID(), pane: .android, kind: .file, name: "x", path: "/1/x",
                                 deviceSerial: "SERIAL", deviceSessionID: "new", storageID: 1, storageName: "Phone")
        XCTAssertTrue(a.sameLocation(as: b))
        let storage = MTPStorageSummary(id: UUID(), storageID: 1, name: "Phone", maxCapacity: nil, freeSpace: nil)
        let noSerial = FavoriteLocation(id: UUID(), pane: .android, kind: .file, name: "x", path: "/1/x",
                                        deviceSerial: nil, deviceSessionID: "session", storageID: 1, storageName: "Phone")
        XCTAssertTrue(noSerial.canResolveAndroid(deviceSerial: "", sessionID: "session", storages: [storage], isConnected: true))
        XCTAssertFalse(noSerial.canResolveAndroid(deviceSerial: "", sessionID: "other", storages: [storage], isConnected: true))
    }

    func testAndroidWithoutSerialIsScopedToCurrentConnectionSession() {
        let storage = MTPStorageSummary(id: UUID(), storageID: 1, name: "Phone", maxCapacity: nil, freeSpace: nil)
        var favorite = FavoriteLocation(
            id: UUID(), pane: .android, kind: .directory, name: "DCIM",
            path: "/1/DCIM/", deviceSerial: nil, deviceSessionID: "old-session",
            storageID: 1, storageName: "Phone"
        )
        XCTAssertFalse(favorite.canResolveAndroid(deviceSerial: nil, sessionID: "new-session", storages: [storage], isConnected: true))
        XCTAssertTrue(favorite.canResolveAndroid(deviceSerial: nil, sessionID: "old-session", storages: [storage], isConnected: true))
        favorite.rebind(deviceSerial: nil, sessionID: "new-session", storageID: 2)
        XCTAssertEqual(favorite.path, "/2/DCIM/")
        XCTAssertFalse(favorite.canResolveAndroid(deviceSerial: nil, sessionID: "old-session", storages: [storage], isConnected: true))
    }
}
