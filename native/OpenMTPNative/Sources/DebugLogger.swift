import AppKit
import Foundation

enum DebugLogger {
    private static let lock = NSLock()
    private static let directoryURL = FileManager.default.urls(
        for: .libraryDirectory,
        in: .userDomainMask
    ).first!
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("MTPShuttle", isDirectory: true)
    
    static let logURL = directoryURL.appendingPathComponent("debug.log")
    
    static var isDebugModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "debugMode")
    }
    
    static func info(_ message: String) {
        write(level: "INFO", message: message)
    }
    
    static func verbose(_ message: String) {
        guard isDebugModeEnabled else { return }
        write(level: "DEBUG", message: message)
    }
    
    static func error(_ message: String) {
        write(level: "ERROR", message: message)
    }
    
    static func startSession() {
        write(
            level: "INFO",
            message: "========== MTP Shuttle session =========="
        )
        write(
            level: "INFO",
            message: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString), architecture \(arch)"
        )
    }
    
    static func contents() -> String {
        lock.lock()
        defer { lock.unlock() }
        
        guard let data = try? Data(contentsOf: logURL) else {
            return "No MTP Shuttle debug log has been created yet."
        }
        
        return String(decoding: data, as: UTF8.self)
    }
    
    static func clearLog() throws {
        lock.lock()
        defer { lock.unlock() }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try Data().write(to: logURL, options: .atomic)
    }

    static func openLog() {
        _ = NSWorkspace.shared.open(logURL)
    }
    
    static func copyLogToClipboard() {
        let contents = self.contents()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contents, forType: .string)
    }
    
    private static var arch: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
    
    private static func write(level: String, message: String) {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            
            let line = "[\(Date())] [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                handle.write(data)
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        } catch {
            // Diagnostics must never terminate the app.
        }
    }
}
