import Foundation

enum PaneKind: String, CaseIterable, Codable, Hashable {
    case mac
    case android

    var title: String {
        switch self {
        case .mac:
            return "This Mac"
        case .android:
            return "Android Device"
        }
    }

    var subtitle: String {
        switch self {
        case .mac:
            return "Local files"
        case .android:
            return "MTP demo device"
        }
    }

    var deviceSymbol: String {
        switch self {
        case .mac:
            return "desktopcomputer"
        case .android:
            return "externaldrive.connected.to.line.below"
        }
    }

    var rootPath: String {
        switch self {
        case .mac:
            return "/Users/Patrick/"
        case .android:
            return "/Internal storage/"
        }
    }
}

enum FileViewMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .list:
            return "list.bullet"
        case .grid:
            return "square.grid.2x2"
        }
    }
}

enum DragDropMode: String, CaseIterable, Identifiable {
    case copy
    case move
    case ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy:
            return "Copy"
        case .move:
            return "Move"
        case .ask:
            return "Ask every time"
        }
    }
}

enum PaneAction: Hashable {
    case properties
    case copy
    case cut
    case delete
    case copyToOther
    case moveToOther
}

enum ClipboardMode: Hashable {
    case copy
    case move
}

struct ClipboardPayload: Hashable {
    let sourcePane: PaneKind
    let sourcePath: String
    let itemIDs: [UUID]
    let mode: ClipboardMode
}

struct DemoDragPayload: Codable, Hashable {
    let sourcePane: PaneKind
    let sourcePath: String
    let itemIDs: [UUID]

    var encoded: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return data.base64EncodedString()
    }

    static func decode(_ encoded: String) -> DemoDragPayload? {
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONDecoder().decode(DemoDragPayload.self, from: data)
    }
}

struct PendingDrop: Identifiable, Hashable {
    let id = UUID()
    let payload: DemoDragPayload
    let targetPane: PaneKind
    let targetPath: String
}

struct BreadcrumbComponent: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
}

struct PaneNavigationState {
    var path: String
    var back: [String] = []
    var forward: [String] = []
    var selection: Set<UUID> = []

    init(path: String) {
        self.path = path
    }
}

struct DemoEntry: Identifiable, Hashable {
    let id: UUID
    var name: String
    var subtitle: String
    var sizeBytes: Int?
    var isDirectory: Bool

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String,
        sizeBytes: Int? = nil,
        isDirectory: Bool
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
    }

    var systemImage: String {
        if isDirectory {
            return "folder.fill"
        }

        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "pdf":
            return "doc.richtext"
        case "zip":
            return "doc.zipper"
        case "dmg":
            return "externaldrive"
        case "mp4", "mov", "mkv":
            return "film"
        case "mp3", "m4a", "wav":
            return "music.note"
        case "jpg", "jpeg", "png", "heic", "webp":
            return "photo"
        case "md", "txt", "swift", "json":
            return "doc.text"
        default:
            return "doc"
        }
    }

    var sizeLabel: String? {
        guard let sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}

struct DemoFileSystem {
    private var local: [String: [DemoEntry]]
    private var android: [String: [DemoEntry]]

    init() {
        local = Self.makeLocalData()
        android = Self.makeAndroidData()
    }

    func entries(for pane: PaneKind, at path: String) -> [DemoEntry] {
        switch pane {
        case .mac:
            return local[path] ?? []
        case .android:
            return android[path] ?? []
        }
    }

    static func breadcrumbComponents(for path: String) -> [BreadcrumbComponent] {
        guard path != "/" else {
            return [
                BreadcrumbComponent(id: "/", name: "/", path: "/")
            ]
        }

        let segments = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        var components: [BreadcrumbComponent] = []
        var currentPath = "/"

        for segment in segments {
            currentPath = childPath(currentPath, segment)
            components.append(
                BreadcrumbComponent(
                    id: currentPath,
                    name: segment,
                    path: currentPath
                )
            )
        }

        return components
    }

    mutating func createFolder(
        named requestedName: String = "New Folder",
        at path: String,
        in pane: PaneKind
    ) -> DemoEntry {
        var name = requestedName
        var suffix = 2
        let existing = Set(entries(for: pane, at: path).map(\.name))

        while existing.contains(name) {
            name = "\(requestedName) \(suffix)"
            suffix += 1
        }

        let entry = DemoEntry(name: name, subtitle: "Folder", isDirectory: true)
        append(entry, to: path, in: pane)
        setEntries([], at: Self.childPath(path, name), in: pane)
        return entry
    }

    mutating func delete(itemIDs: [UUID], at path: String, in pane: PaneKind) -> Int {
        let selected = entries(for: pane, at: path).filter { itemIDs.contains($0.id) }
        guard !selected.isEmpty else { return 0 }

        setEntries(
            entries(for: pane, at: path).filter { !itemIDs.contains($0.id) },
            at: path,
            in: pane
        )

        for item in selected where item.isDirectory {
            removeSubtree(at: Self.childPath(path, item.name), in: pane)
        }

        return selected.count
    }

    mutating func transfer(
        itemIDs: [UUID],
        from sourcePane: PaneKind,
        sourcePath: String,
        to targetPane: PaneKind,
        targetPath: String,
        mode: ClipboardMode
    ) -> Int {
        let selected = entries(for: sourcePane, at: sourcePath).filter { itemIDs.contains($0.id) }
        guard !selected.isEmpty else { return 0 }

        if sourcePane == targetPane, sourcePath == targetPath, mode == .move {
            return 0
        }

        var destination = entries(for: targetPane, at: targetPath)
        var transferred = 0

        for item in selected {
            let newName = uniqueName(for: item.name, in: destination)
            let copiedRoot = DemoEntry(
                name: newName,
                subtitle: item.subtitle,
                sizeBytes: item.sizeBytes,
                isDirectory: item.isDirectory
            )

            destination.append(copiedRoot)

            if item.isDirectory {
                let sourceFolder = Self.childPath(sourcePath, item.name)
                let targetFolder = Self.childPath(targetPath, newName)
                setEntries([], at: targetFolder, in: targetPane)
                copyChildren(
                    from: sourcePane,
                    sourcePath: sourceFolder,
                    to: targetPane,
                    targetPath: targetFolder
                )
            }

            transferred += 1
        }

        setEntries(destination, at: targetPath, in: targetPane)

        if mode == .move {
            _ = delete(itemIDs: selected.map(\.id), at: sourcePath, in: sourcePane)
        }

        return transferred
    }

    static func childPath(_ parent: String, _ child: String) -> String {
        let normalized = parent.hasSuffix("/") ? String(parent.dropLast()) : parent
        return normalized.isEmpty ? "/\(child)/" : "\(normalized)/\(child)/"
    }

    static func parentPath(_ path: String) -> String {
        guard path != "/", path.count > 1 else { return path }

        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let slash = trimmed.lastIndex(of: "/") else { return path }

        let parent = String(trimmed[..<slash])
        return parent.isEmpty ? "/" : "\(parent)/"
    }

    private mutating func append(_ entry: DemoEntry, to path: String, in pane: PaneKind) {
        var updated = entries(for: pane, at: path)
        updated.append(entry)
        setEntries(updated, at: path, in: pane)
    }

    private func uniqueName(for original: String, in destination: [DemoEntry]) -> String {
        let existing = Set(destination.map(\.name))
        guard existing.contains(original) else { return original }

        let url = URL(fileURLWithPath: original)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var index = 2

        while true {
            let candidateBase = "\(base) \(index)"
            let candidate = ext.isEmpty ? candidateBase : "\(candidateBase).\(ext)"
            if !existing.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    private mutating func copyChildren(
        from sourcePane: PaneKind,
        sourcePath: String,
        to targetPane: PaneKind,
        targetPath: String
    ) {
        let children = entries(for: sourcePane, at: sourcePath)
        var destination = entries(for: targetPane, at: targetPath)

        for child in children {
            let newName = uniqueName(for: child.name, in: destination)
            let copied = DemoEntry(
                name: newName,
                subtitle: child.subtitle,
                sizeBytes: child.sizeBytes,
                isDirectory: child.isDirectory
            )
            destination.append(copied)

            if child.isDirectory {
                let childSourcePath = Self.childPath(sourcePath, child.name)
                let childTargetPath = Self.childPath(targetPath, newName)
                setEntries([], at: childTargetPath, in: targetPane)
                copyChildren(
                    from: sourcePane,
                    sourcePath: childSourcePath,
                    to: targetPane,
                    targetPath: childTargetPath
                )
            }
        }

        setEntries(destination, at: targetPath, in: targetPane)
    }

    private mutating func removeSubtree(at path: String, in pane: PaneKind) {
        let children = entries(for: pane, at: path)
        for child in children where child.isDirectory {
            removeSubtree(at: Self.childPath(path, child.name), in: pane)
        }

        switch pane {
        case .mac:
            local.removeValue(forKey: path)
        case .android:
            android.removeValue(forKey: path)
        }
    }

    private mutating func setEntries(_ value: [DemoEntry], at path: String, in pane: PaneKind) {
        switch pane {
        case .mac:
            local[path] = value
        case .android:
            android[path] = value
        }
    }

    private static func folder(_ name: String) -> DemoEntry {
        DemoEntry(name: name, subtitle: "Folder", isDirectory: true)
    }

    private static func file(_ name: String, _ subtitle: String, _ sizeBytes: Int) -> DemoEntry {
        DemoEntry(name: name, subtitle: subtitle, sizeBytes: sizeBytes, isDirectory: false)
    }

    private static func makeLocalData() -> [String: [DemoEntry]] {
        let root = "/Users/Patrick/"
        let users = "/Users/"
        let filesystemRoot = "/"
        let documents = childPath(root, "Documents")
        let projects = childPath(documents, "Projects")
        let downloads = childPath(root, "Downloads")
        let pictures = childPath(root, "Pictures")
        let trip = childPath(pictures, "Trip 2026")
        let openMTP = childPath(projects, "OpenMTP")
        let nativeUI = childPath(openMTP, "Native UI")

        return [
            filesystemRoot: [
                folder("Users")
            ],
            users: [
                folder("Patrick")
            ],
            root: [
                folder("Desktop"),
                folder("Documents"),
                folder("Downloads"),
                folder("Pictures"),
                folder("Movies"),
                folder("Music"),
                folder("OpenMTP Demo"),
                file("README.md", "Markdown", 8_192),
                file("SwiftUI-Notes.txt", "Plain Text", 14_336),
                file("Presentation.pdf", "PDF Document", 2_486_272),
                file("Demo Archive.zip", "ZIP Archive", 6_291_456)
            ],
            documents: [
                folder("Projects"),
                folder("Receipts"),
                file("Semester-Plan.pdf", "PDF Document", 1_245_184),
                file("Meeting Notes.md", "Markdown", 32_768),
                file("Budget.xlsx", "Spreadsheet", 84_992),
                file("Travel Checklist.txt", "Plain Text", 6_144)
            ],
            projects: [
                folder("OpenMTP"),
                folder("Media Tools"),
                file("Project Brief.md", "Markdown", 12_288),
                file("Architecture.pdf", "PDF Document", 3_145_728)
            ],
            openMTP: [
                folder("Native UI"),
                folder("Research"),
                file("README.md", "Markdown", 9_728),
                file("Design Notes.pdf", "PDF Document", 1_572_864)
            ],
            nativeUI: [
                file("ContentView.swift", "Swift Source", 18_432),
                file("FilePaneView.swift", "Swift Source", 16_384),
                file("Models.swift", "Swift Source", 14_848),
                file("Mock Data.json", "JSON", 22_528)
            ],
            downloads: [
                folder("Installers"),
                file("OpenMTP-Native-ARM64.zip", "ZIP Archive", 4_718_592),
                file("Sample Video.mp4", "Video", 42_467_328),
                file("Test Image.heic", "HEIC Image", 5_242_880),
                file("SwiftUI Preview.dmg", "Disk Image", 8_388_608),
                file("Transfer Log.txt", "Plain Text", 3_072)
            ],
            pictures: [
                folder("Trip 2026"),
                folder("Screenshots"),
                file("IMG_1201.HEIC", "HEIC Image", 4_718_592),
                file("IMG_1202.HEIC", "HEIC Image", 5_033_164),
                file("OpenMTP.png", "PNG Image", 1_048_576),
                file("UI-Test.jpg", "JPEG Image", 2_621_440)
            ],
            trip: [
                file("Mountain 01.jpg", "JPEG Image", 3_145_728),
                file("Mountain 02.jpg", "JPEG Image", 4_194_304),
                file("Train Station.jpg", "JPEG Image", 5_033_164),
                file("Sunset.heic", "HEIC Image", 3_670_016),
                file("Trail Map.pdf", "PDF Document", 1_572_864)
            ]
        ]
    }

    private static func makeAndroidData() -> [String: [DemoEntry]] {
        let root = "/Internal storage/"
        let filesystemRoot = "/"
        let dcim = childPath(root, "DCIM")
        let camera = childPath(dcim, "Camera")
        let screenshots = childPath(dcim, "Screenshots")
        let download = childPath(root, "Download")
        let movies = childPath(root, "Movies")
        let music = childPath(root, "Music")
        let pictures = childPath(root, "Pictures")
        let telegram = childPath(pictures, "Telegram")
        let bluetooth = childPath(root, "Bluetooth")

        return [
            filesystemRoot: [
                folder("Internal storage")
            ],
            root: [
                folder("DCIM"),
                folder("Download"),
                folder("Movies"),
                folder("Music"),
                folder("Pictures"),
                folder("Documents"),
                folder("Bluetooth"),
                file("Android-Overview.txt", "Plain Text", 4_608),
                file("Phone Backup.zip", "ZIP Archive", 18_874_368),
                file("storage-info.json", "JSON", 9_216)
            ],
            dcim: [
                folder("Camera"),
                folder("Screenshots"),
                file("DCIM-Readme.txt", "Plain Text", 2_048)
            ],
            camera: [
                file("IMG_2026_0901.jpg", "JPEG Image", 5_242_880),
                file("IMG_2026_0902.jpg", "JPEG Image", 4_718_592),
                file("IMG_2026_0903.jpg", "JPEG Image", 6_291_456),
                file("VID_2026_0904.mp4", "Video", 74_448_896),
                file("IMG_2026_0905.heic", "HEIC Image", 4_194_304)
            ],
            screenshots: [
                file("Screenshot_2026-09-20.png", "PNG Image", 2_097_152),
                file("Screenshot_2026-09-21.png", "PNG Image", 1_835_008),
                file("Screenshot_2026-09-22.png", "PNG Image", 2_621_440),
                file("settings-backup.json", "JSON", 12_288)
            ],
            download: [
                file("OpenMTP.apk", "Android Package", 31_457_280),
                file("Pixel-Notes.pdf", "PDF Document", 2_936_832),
                file("sample-data.zip", "ZIP Archive", 12_582_912),
                file("Train-Routes.txt", "Plain Text", 8_192),
                file("demo-video.mp4", "Video", 38_797_312)
            ],
            movies: [
                file("Demo Clip.mp4", "Video", 58_720_256),
                file("Travel 2026.mov", "Video", 84_934_912),
                file("OpenMTP Test.mkv", "Video", 101_711_872)
            ],
            music: [
                file("Ambient.m4a", "Audio", 8_388_608),
                file("Morning.mp3", "Audio", 6_291_456),
                file("Railway Station.wav", "Audio", 12_582_912)
            ],
            pictures: [
                folder("Telegram"),
                file("Wallpapers.zip", "ZIP Archive", 26_214_400),
                file("Profile.heic", "HEIC Image", 3_670_016),
                file("Favorite.jpg", "JPEG Image", 2_516_992)
            ],
            telegram: [
                folder("Images"),
                folder("Documents"),
                file("Telegram Notes.txt", "Plain Text", 4_096)
            ],
            bluetooth: [
                file("Shared from Mac.zip", "ZIP Archive", 9_437_184),
                file("Bluetooth Photo.jpg", "JPEG Image", 2_936_832)
            ]
        ]
    }
}
