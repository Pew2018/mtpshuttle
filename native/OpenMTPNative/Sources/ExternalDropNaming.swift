import Foundation

enum ExternalDropNaming {
    static func conflicts(sourceNames: [String], destinationNames: Set<String>) -> [String] {
        var counts: [String: Int] = [:]
        for name in sourceNames { counts[name, default: 0] += 1 }
        let repeated = Set(counts.compactMap { $0.value > 1 ? $0.key : nil })
        let existing = Set(sourceNames.filter { destinationNames.contains($0) })
        let conflictSet = repeated.union(existing)
        var seen = Set<String>()
        return sourceNames.filter { conflictSet.contains($0) && seen.insert($0).inserted }
    }

    static func plan(sourceNames: [String], destinationNames: Set<String>, resolution: TransferConflictResolution?) -> [String]? {
        let collisions = conflicts(sourceNames: sourceNames, destinationNames: destinationNames)
        guard collisions.isEmpty || resolution != nil else { return nil }
        var reserved = destinationNames
        var seenSourceNames = Set<String>()
        var result: [String] = []
        for name in sourceNames {
            let repeated = seenSourceNames.contains(name)
            let collides = reserved.contains(name)
            let rename = (resolution == .rename && collides) || repeated
            let target = rename ? uniqueName(for: name, reserved: reserved) : name
            seenSourceNames.insert(name)
            reserved.insert(target)
            result.append(target)
        }
        return result
    }

    private static func uniqueName(for name: String, reserved: Set<String>) -> String {
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? name : url.deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let candidate = ext.isEmpty ? stem + " (" + String(index) + ")" : stem + " (" + String(index) + ")." + ext
            if !reserved.contains(candidate) { return candidate }
            index += 1
        }
    }
}
