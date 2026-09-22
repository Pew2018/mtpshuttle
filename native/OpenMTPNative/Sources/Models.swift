import Foundation

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

enum SidebarItem: String, CaseIterable, Identifiable {
    case computer
    case android

    var id: String { rawValue }

    var title: String {
        switch self {
        case .computer:
            return "This Mac"
        case .android:
            return "Android Device"
        }
    }

    var icon: String {
        switch self {
        case .computer:
            return "macbook"
        case .android:
            return "cable.connector"
        }
    }
}

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let systemImage: String
    let subtitle: String
    let size: String?
    let isDirectory: Bool
}

extension FileItem {
    static let localSamples: [FileItem] = [
        .init(name: "Documents", systemImage: "folder.fill", subtitle: "Folder", size: nil, isDirectory: true),
        .init(name: "Downloads", systemImage: "folder.fill", subtitle: "Folder", size: nil, isDirectory: true),
        .init(name: "Pictures", systemImage: "folder.fill", subtitle: "Folder", size: nil, isDirectory: true),
        .init(name: "OpenMTP", systemImage: "folder.fill", subtitle: "Folder", size: nil, isDirectory: true),
        .init(name: "README.md", systemImage: "doc.text", subtitle: "Markdown", size: "8 KB", isDirectory: false),
        .init(name: "Example.pdf", systemImage: "doc.richtext", subtitle: "PDF", size: "2.4 MB", isDirectory: false),
    ]

    static let androidSamples: [FileItem] = [
        .init(name: "DCIM", systemImage: "folder.fill", subtitle: "Folder", size: nil, isDirectory: true),
        .init(name: "Download", systemImage: "folder.fill", subtitle: "Folder", size: nil, isDirectory: true),
        .init(name: "Movies", systemImage: "folder.fill", subtitle: "Folder", size: nil, isDirectory: true),
        .init(name: "Music", systemImage: "folder.fill", subtitle: "Folder", size: nil, isDirectory: true),
        .init(name: "Pictures", systemImage: "folder.fill", subtitle: "Folder", size: nil, isDirectory: true),
        .init(name: "Telegram", systemImage: "folder.fill", subtitle: "Folder", size: nil, isDirectory: true),
    ]
}
