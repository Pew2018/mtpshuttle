import Foundation
import SwiftUI

enum FavoriteFileOpenBehavior: String, CaseIterable, Identifiable, Equatable {
    case revealAndSelect
    case showProperties

    static let defaultValue: Self = .revealAndSelect

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .revealAndSelect: return "Reveal Containing Folder and Select File"
        case .showProperties: return "Show File Properties"
        }
    }
}

enum FavoriteItemKind: String, Codable, Hashable {
    case directory
    case file
}

struct FavoriteLocation: Identifiable, Codable, Hashable {
    var id: UUID
    var pane: PaneKind
    var kind: FavoriteItemKind
    var name: String
    var path: String
    var deviceSerial: String?
    var deviceSessionID: String?
    var storageID: UInt32?
    var storageName: String?

    static func from(
        pane: PaneKind,
        item: DemoEntry,
        currentPath: String,
        deviceSerial: String?,
        deviceSessionID: String?,
        storageName: String?
    ) -> FavoriteLocation {
        let path: String
        if pane == .mac {
            path = item.localURL?.standardizedFileURL.path
                ?? DemoFileSystem.childPath(currentPath, item.name)
        } else if currentPath == PaneKind.android.rootPath, let storageID = item.storageID {
            path = "/\(storageID)/"
        } else if let storageID = item.storageID, let remotePath = item.remotePath {
            let suffix = remotePath.hasPrefix("/") ? remotePath : "/" + remotePath
            let trimmed = suffix == "/" ? "" : suffix
            path = "/\(storageID)\(trimmed)" + (item.isDirectory ? "/" : "")
        } else {
            path = currentPath
        }

        let normalizedSerial = deviceSerial?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stableSerial = normalizedSerial?.isEmpty == false ? normalizedSerial : nil
        return FavoriteLocation(
            id: UUID(),
            pane: pane,
            kind: item.isDirectory ? .directory : .file,
            name: item.name,
            path: path,
            deviceSerial: pane == .android ? stableSerial : nil,
            deviceSessionID: pane == .android ? deviceSessionID : nil,
            storageID: pane == .android ? item.storageID : nil,
            storageName: pane == .android ? storageName : nil
        )
    }

    var parentPath: String {
        switch pane {
        case .mac:
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path
            return parent.hasSuffix("/") ? parent : parent + "/"
        case .android:
            let components = path.split(separator: "/").map(String.init)
            guard components.count > 1 else { return "/" }
            return "/" + components.dropLast().joined(separator: "/") + "/"
        }
    }

    func sameLocation(as other: FavoriteLocation) -> Bool {
        guard pane == other.pane, path == other.path else { return false }
        if pane == .mac { return true }
        guard storageID == other.storageID, deviceSerial == other.deviceSerial else { return false }
        if deviceSerial != nil { return true }
        return deviceSessionID == other.deviceSessionID
    }

    static func decode(_ payload: String) -> [FavoriteLocation] {
        guard let data = payload.data(using: .utf8),
              let locations = try? JSONDecoder().decode([FavoriteLocation].self, from: data) else { return [] }
        return locations
    }

    static func encode(_ locations: [FavoriteLocation]) -> String {
        guard let data = try? JSONEncoder().encode(locations) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func toggled(_ location: FavoriteLocation, in locations: [FavoriteLocation]) -> [FavoriteLocation] {
        if locations.contains(where: { $0.sameLocation(as: location) }) {
            return locations.filter { !$0.sameLocation(as: location) }
        }
        return locations + [location]
    }

    func canResolveAndroid(
        deviceSerial currentSerial: String?,
        sessionID currentSessionID: String,
        storages: [MTPStorageSummary],
        isConnected: Bool
    ) -> Bool {
        guard pane == .android, isConnected,
              let storageID, let storageName,
              storages.contains(where: { $0.storageID == storageID && $0.name == storageName }) else { return false }
        let normalizedCurrentSerial = currentSerial?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stableCurrentSerial = normalizedCurrentSerial?.isEmpty == false ? normalizedCurrentSerial : nil
        if let deviceSerial {
            return stableCurrentSerial == deviceSerial
        }
        guard stableCurrentSerial == nil, let deviceSessionID else { return false }
        return deviceSessionID == currentSessionID
    }

    mutating func rebind(deviceSerial: String?, sessionID: String, storageID: UInt32) {
        if let oldStorageID = self.storageID {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            if components.count > 1, components[1] == String(oldStorageID) {
                var updated = components
                updated[1] = Substring(String(storageID))
                path = updated.map(String.init).joined(separator: "/")
            }
        }
        self.deviceSerial = deviceSerial
        self.deviceSessionID = sessionID
        self.storageID = storageID
    }
}

enum FavoriteStrings {
    static func localized(_ key: String) -> String {
        MTPShuttleText.localized(key)
    }
}

struct FilePropertiesSheet: View {
    let item: DemoEntry
    let message: String
    let canShowContainingFolder: Bool
    let onShowContainingFolder: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MTPDialogHeader(
                symbol: "doc.text",
                title: FavoriteStrings.localized("File Properties"),
                subtitle: item.name
            )

            Text(message)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            MTPDialogActionRow {
                if canShowContainingFolder {
                    Button(FavoriteStrings.localized("Show in Containing Folder"), action: onShowContainingFolder)
                        .buttonStyle(.borderedProminent)
                }
                Button(FavoriteStrings.localized("Close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 400, maxWidth: 580)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct FavoriteShelfView: View {
    let favorites: [FavoriteLocation]
    let expandedHeight: CGFloat
    let isAndroidConnected: Bool
    let isAvailable: (FavoriteLocation) -> Bool
    @State private var unavailableFavorite: FavoriteLocation?
    @State private var favoritePendingRebind: FavoriteLocation?
    let onOpen: (FavoriteLocation) -> Void
    let onRemove: (FavoriteLocation) -> Void
    let onRebind: (FavoriteLocation) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(FavoriteStrings.localized("Favorites"), systemImage: "star.fill")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider()
            HStack(spacing: 0) {
                favoriteColumn(title: FavoriteStrings.localized("This Mac"), pane: .mac)
                Divider()
                favoriteColumn(title: FavoriteStrings.localized("Android Device"), pane: .android)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: expandedHeight)
        .background(.bar)
        .alert(item: $unavailableFavorite) { favorite in
            Alert(
                title: Text(FavoriteStrings.localized("Unavailable")),
                message: Text(FavoriteStrings.localized("Favorite is currently unavailable")),
                primaryButton: .destructive(
                    Text(FavoriteStrings.localized("Remove from Favorites")),
                    action: { onRemove(favorite) }
                ),
                secondaryButton: .cancel(Text(FavoriteStrings.localized("Close")))
            )
        }
        .confirmationDialog(
            Text(FavoriteStrings.localized("Link this favorite to the current Android device?")),
            isPresented: Binding(
                get: { favoritePendingRebind != nil },
                set: { if !$0 { favoritePendingRebind = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(FavoriteStrings.localized("Link Favorite")) {
                guard let favorite = favoritePendingRebind else { return }
                favoritePendingRebind = nil
                onRebind(favorite)
            }
            Button(FavoriteStrings.localized("Cancel"), role: .cancel) {
                favoritePendingRebind = nil
            }
        } message: {
            Text(FavoriteStrings.localized("This updates the device and storage location saved for this favorite to match the connected Android device. It does not modify files on the device."))
        }
    }

    private func favoriteColumn(title: String, pane: PaneKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.top, 6)
            let items = favorites.filter { $0.pane == pane }
            if items.isEmpty {
                Text(FavoriteStrings.localized("No favorites yet"))
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10).padding(.top, 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(items) { favorite in
                            favoriteRow(favorite)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.bottom, 5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func favoriteRow(_ favorite: FavoriteLocation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: favorite.kind == .directory ? "folder" : "doc")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(favorite.name).font(.subheadline).lineLimit(1)
                Text(favorite.path).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if isAvailable(favorite) {
                onOpen(favorite)
            } else {
                unavailableFavorite = favorite
            }
        }
        .contextMenu {
            Button(FavoriteStrings.localized("Open")) {
                if isAvailable(favorite) {
                    onOpen(favorite)
                } else {
                    unavailableFavorite = favorite
                }
            }
            if favorite.pane == .android && isAndroidConnected && !isAvailable(favorite) {
                Divider()
                Button(FavoriteStrings.localized("Link to Current Android Device…")) {
                    favoritePendingRebind = favorite
                }
            }
            Button(FavoriteStrings.localized("Remove from Favorites"), systemImage: "star.slash", role: .destructive) {
                onRemove(favorite)
            }
        }
        .help(favorite.path)
    }
}
