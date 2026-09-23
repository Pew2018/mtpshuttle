import Foundation
import Darwin

enum KalamBridgeError: LocalizedError {
    case libraryNotFound([String])
    case loadFailed(String)
    case symbolNotFound(String)
    case busy(String)
    case invalidResponse(String)
    
    var errorDescription: String? {
        switch self {
        case .libraryNotFound(let paths):
            return "Kalam library not found. Searched: \(paths.joined(separator: ", "))"
        case .loadFailed(let message):
            return "Unable to load Kalam: \(message)"
        case .symbolNotFound(let symbol):
            return "Kalam symbol not found: \(symbol)"
        case .busy(let operation):
            return "Kalam is already handling another operation: \(operation)"
        case .invalidResponse(let raw):
            return "Kalam returned invalid JSON: \(raw.prefix(512))"
        }
    }
}

struct KalamResponse {
    let rawJSON: String
    let errorType: String?
    let errorMessage: String?
    let data: KalamJSONValue?
    
    var isSuccess: Bool {
        (errorType?.isEmpty ?? true) && (errorMessage?.isEmpty ?? true)
    }
    
    init(json: String) throws {
        rawJSON = json
        guard let rawData = json.data(using: .utf8) else {
            throw KalamBridgeError.invalidResponse(json)
        }
        
        let root = try JSONDecoder().decode([String: KalamJSONValue].self, from: rawData)
        data = root.value(forKeyIgnoringCase: "data")
        
        let rawErrorType = root.value(forKeyIgnoringCase: "errorType")?.stringValue
        let rawError = root.value(forKeyIgnoringCase: "error")?.stringValue
        
        errorType = rawErrorType.flatMap { $0.isEmpty ? nil : $0 }
        errorMessage = rawError.flatMap { $0.isEmpty ? nil : $0 }
    }
    

}

enum KalamJSONValue: Decodable {
    case object([String: KalamJSONValue])
    case array([KalamJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
            return
        }
        
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        
        if let value = try? container.decode([KalamJSONValue].self) {
            self = .array(value)
            return
        }
        
        if let value = try? container.decode([String: KalamJSONValue].self) {
            self = .object(value)
            return
        }
        
        throw KalamBridgeError.invalidResponse("Unsupported JSON value")
    }
    
    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        default:
            return nil
        }
    }
    
    var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }
    
    var objectValue: [String: KalamJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
    
    var arrayValue: [KalamJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
    
    func value(forKeyIgnoringCase key: String) -> KalamJSONValue? {
        guard let object = objectValue else { return nil }
        return object.value(forKeyIgnoringCase: key)
    }
    
    func firstString(forKeys keys: [String]) -> String? {
        guard let object = objectValue else { return nil }
        return object.firstString(forKeys: keys)
    }
}

extension Dictionary where Key == String, Value == KalamJSONValue {
    func value(forKeyIgnoringCase key: String) -> KalamJSONValue? {
        if let exact = self[key] {
            return exact
        }
        
        return first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }
    
    func firstString(forKeys keys: [String]) -> String? {
        for key in keys {
            if let value = value(forKeyIgnoringCase: key)?.stringValue,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

final class KalamBridge {
    static let shared = KalamBridge()
    
    private typealias Callback = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void
    private typealias JSONFunction = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
    private typealias TransferFunction = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    private let callQueue = DispatchQueue(label: "com.pew2018.openmtp.kalam", qos: .userInitiated)

    private typealias OneShotFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void
    
    private static let callback: Callback = { pointer in
        KalamBridge.shared.receive(pointer)
    }
    private static let preprocessCallback: Callback = { pointer in
        KalamBridge.shared.receiveTransferProgress(pointer)
    }
    private static let progressCallback: Callback = { pointer in
        KalamBridge.shared.receiveTransferProgress(pointer)
    }
    private static let doneCallback: Callback = { pointer in
        KalamBridge.shared.receive(pointer)
    }
    
    private let stateLock = NSLock()
    private var handle: UnsafeMutableRawPointer?
    private var pendingContinuation: CheckedContinuation<KalamResponse, Error>?
    private var pendingOperation: String?
    private var loadedPath: String?
    
    private init() {}
    
    deinit {
        if let handle {
            dlclose(handle)
        }
    }
    
    func initialize() async throws -> KalamResponse {
        try await call("Initialize")
    }
    
    func fetchDeviceInfo() async throws -> KalamResponse {
        try await call("FetchDeviceInfo")
    }
    
    func fetchStorages() async throws -> KalamResponse {
        try await call("FetchStorages")
    }
    
    func walk(_ location: MTPBrowsePath) async throws -> KalamResponse {
        try await call("Walk", input: location.walkJSON)
    }

    func upload(storageID: UInt32, sources: [String], destination: String) async throws -> KalamResponse {
        try await transfer(
            symbol: "UploadFiles",
            input: ["storageId": storageID, "sources": sources, "destination": destination, "preprocessFiles": true]
        )
    }

    func download(storageID: UInt32, sources: [String], destination: String) async throws -> KalamResponse {
        try await transfer(
            symbol: "DownloadFiles",
            input: ["storageId": storageID, "sources": sources, "destination": destination, "preprocessFiles": true]
        )
    }

    func dispose() async throws -> KalamResponse {
        try await call("Dispose")
    }
    
    func loadedLibraryPath() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return loadedPath
    }
    
    private func call(_ symbol: String, input: String? = nil) async throws -> KalamResponse {
        try await withCheckedThrowingContinuation { continuation in
            // Native Kalam functions invoke their completion callback before returning.
            // Serialize the whole native call, including argument buffer lifetime.
            callQueue.async { [self] in
                stateLock.lock()
                guard pendingContinuation == nil else {
                    let operation = pendingOperation ?? "unknown"
                    stateLock.unlock()
                    continuation.resume(throwing: KalamBridgeError.busy(operation))
                    return
                }
                pendingContinuation = continuation
                pendingOperation = symbol
                stateLock.unlock()
                do {
                    try ensureLoaded()
                    guard let handle, let address = dlsym(handle, symbol) else {
                        throw KalamBridgeError.symbolNotFound(symbol)
                    }
                    DebugLogger.info("Kalam call started: \(symbol)")
                    let callbackAddress = unsafeBitCast(Self.callback, to: UnsafeMutableRawPointer.self)
                    if let input {
                        let function = unsafeBitCast(address, to: JSONFunction.self)
                        input.withCString { function($0, callbackAddress) }
                    } else {
                        let function = unsafeBitCast(address, to: OneShotFunction.self)
                        function(callbackAddress)
                    }
                } catch {
                    finish(with: error)
                }
            }
        }
    }

    private func transfer(symbol: String, input: [String: Any]) async throws -> KalamResponse {
        let data = try JSONSerialization.data(withJSONObject: input)
        guard let json = String(data: data, encoding: .utf8) else {
            throw KalamBridgeError.invalidResponse("Unable to encode (symbol) input")
        }
        return try await withCheckedThrowingContinuation { continuation in
            callQueue.async { [self] in
                stateLock.lock()
                guard pendingContinuation == nil else {
                    let operation = pendingOperation ?? "unknown"
                    stateLock.unlock()
                    continuation.resume(throwing: KalamBridgeError.busy(operation))
                    return
                }
                pendingContinuation = continuation
                pendingOperation = symbol
                stateLock.unlock()
                do {
                    try ensureLoaded()
                    guard let handle, let address = dlsym(handle, symbol) else {
                        throw KalamBridgeError.symbolNotFound(symbol)
                    }
                    let function = unsafeBitCast(address, to: TransferFunction.self)
                    let preprocess = unsafeBitCast(Self.preprocessCallback, to: UnsafeMutableRawPointer.self)
                    let progress = unsafeBitCast(Self.progressCallback, to: UnsafeMutableRawPointer.self)
                    let done = unsafeBitCast(Self.doneCallback, to: UnsafeMutableRawPointer.self)
                    json.withCString { function($0, preprocess, progress, done) }
                } catch {
                    finish(with: error)
                }
            }
        }
    }

    private func ensureLoaded() throws {
        stateLock.lock()
        if handle != nil {
            stateLock.unlock()
            return
        }
        stateLock.unlock()
        
        let candidates = candidateLibraryURLs()
        let attemptedPaths = candidates.map(\.path)
        
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            
            DebugLogger.info("Attempting to load Kalam: \(url.path)")
            
            if let loaded = dlopen(url.path, RTLD_NOW | RTLD_LOCAL) {
                stateLock.lock()
                handle = loaded
                loadedPath = url.path
                stateLock.unlock()
                
                DebugLogger.info("Loaded Kalam successfully: \(url.path)")
                return
            }
            
            let message = dlerror().map { String(cString: $0) } ?? "unknown dlopen error"
            DebugLogger.error("Kalam dlopen failed at \(url.path): \(message)")
        }
        
        throw KalamBridgeError.libraryNotFound(attemptedPaths)
    }
    
    private func resolve(_ symbol: String) throws -> OneShotFunction {
        guard let handle else {
            throw KalamBridgeError.loadFailed("Library handle is unavailable")
        }
        
        guard let address = dlsym(handle, symbol) else {
            DebugLogger.error("Kalam symbol lookup failed: \(symbol)")
            throw KalamBridgeError.symbolNotFound(symbol)
        }
        
        return unsafeBitCast(address, to: OneShotFunction.self)
    }
    
    private func candidateLibraryURLs() -> [URL] {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let useSeg5 = os.majorVersion >= 26
        
        var urls: [URL] = []
        
        if let resourceURL = Bundle.main.resourceURL {
            if useSeg5 {
                urls.append(resourceURL.appendingPathComponent("Kalam/seg5/kalam-seg5.dylib"))
            }
            urls.append(resourceURL.appendingPathComponent("Kalam/standard/kalam.dylib"))
        }
        
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let repositoryRoot = currentDirectory.appendingPathComponent("../../", isDirectory: true).standardizedFileURL
        if useSeg5 {
            urls.append(repositoryRoot.appendingPathComponent("build/mac/bin/arm64/kalam-seg5.dylib"))
        }
        urls.append(repositoryRoot.appendingPathComponent("build/mac/bin/arm64/kalam.dylib"))
        
        return urls
    }
    
    private func receive(_ pointer: UnsafeMutablePointer<CChar>?) {
        guard let pointer else {
            finish(with: KalamBridgeError.invalidResponse("<null callback>"))
            return
        }
        
        let rawJSON = String(cString: pointer)
        free(pointer)
        
        DebugLogger.verbose("Kalam raw response: \(rawJSON)")
        
        do {
            let response = try KalamResponse(json: rawJSON)
            if let errorType = response.errorType {
                DebugLogger.error("Kalam returned \(errorType): \(response.errorMessage ?? "unknown error")")
            } else {
                DebugLogger.info("Kalam call completed successfully")
            }
            finish(with: response)
        } catch {
            finish(with: error)
        }
    }

    private func receiveTransferProgress(_ pointer: UnsafeMutablePointer<CChar>?) {
        if let pointer {
            free(pointer)
        }
    }
    
    private func finish(with response: KalamResponse) {
        stateLock.lock()
        let continuation = pendingContinuation
        pendingContinuation = nil
        pendingOperation = nil
        stateLock.unlock()
        
        continuation?.resume(returning: response)
    }
    
    private func finish(with error: Error) {
        stateLock.lock()
        let continuation = pendingContinuation
        pendingContinuation = nil
        pendingOperation = nil
        stateLock.unlock()
        
        continuation?.resume(throwing: error)
    }
}
