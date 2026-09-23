import Foundation
import Combine

@MainActor
final class LocalBrowserService: ObservableObject {
    @Published private(set) var entries: [DemoEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var generation = UUID()
    private var identities: [String: UUID] = [:]

    func load(path: String) async {
        let request = UUID()
        generation = request
        isLoading = true
        errorMessage = nil
        entries = []
        do {
            let records = try await Task.detached(priority: .userInitiated) {
                try Self.readDirectory(URL(fileURLWithPath: path, isDirectory: true))
            }.value
            guard generation == request else { return }
            entries = records.map { record in
                let id = identities[record.url.path] ?? UUID()
                identities[record.url.path] = id
                return DemoEntry(id: id, name: record.url.lastPathComponent,
                                 subtitle: record.isDirectory ? "Folder" : record.kind,
                                 sizeBytes: record.isDirectory ? nil : record.size,
                                 isDirectory: record.isDirectory, localURL: record.url)
            }.sorted(by: DemoEntry.browserOrder)
        } catch {
            guard generation == request else { return }
            errorMessage = "Unable to read this folder: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private struct Record: Sendable {
        let url: URL
        let isDirectory: Bool
        let size: Int?
        let kind: String
    }

    nonisolated private static func readDirectory(_ url: URL) throws -> [Record] {
        let manager = FileManager.default
        return try manager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .localizedTypeDescriptionKey],
            options: [.skipsHiddenFiles]
        ).map { child in
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .localizedTypeDescriptionKey])
            var directory: ObjCBool = false
            _ = manager.fileExists(atPath: child.path, isDirectory: &directory)
            return Record(url: child, isDirectory: directory.boolValue,
                          size: values?.fileSize, kind: values?.localizedTypeDescription ?? "File")
        }
    }
}
