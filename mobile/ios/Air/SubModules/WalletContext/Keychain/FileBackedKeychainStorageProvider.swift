import Foundation

private let log = Log("FileBackedKeychainStorageProvider")

// JSON-file replacement for the iOS Keychain, used only under E2E flows.
// Backing file lives in the app's Application Support directory so that
// simctl clone preserves it as part of the sandbox.
public final class FileBackedKeychainStorageProvider: IKeychainStorageProvider, @unchecked Sendable {

    private let fileURL: URL
    private let queue = DispatchQueue(label: "FileBackedKeychainStorageProvider", qos: .userInitiated)
    private var cache: [String: String]

    public init() {
        let fileManager = FileManager.default
        let baseURL: URL
        do {
            baseURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            log.fault("failed to locate Application Support directory: \(error, .public)")
            baseURL = fileManager.temporaryDirectory
        }
        fileURL = baseURL.appendingPathComponent("e2e_keychain.json")
        cache = Self.load(from: fileURL)
        log.info("file-backed keychain enabled at \(fileURL.path, .public) entries=\(cache.count, .public)")
    }

    public func set(key: String, value: String) -> Bool {
        queue.sync {
            cache[key] = value
            return persistIgnoringFailure()
        }
    }

    public func get(key: String) -> (Bool, String?) {
        queue.sync {
            if let value = cache[key] {
                return (true, value)
            }
            return (false, nil)
        }
    }

    public func remove(key: String) -> Bool {
        queue.sync {
            guard cache.removeValue(forKey: key) != nil else {
                return false
            }
            return persistIgnoringFailure()
        }
    }

    public func keys() -> [String] {
        queue.sync { Array(cache.keys) }
    }

    public func load(key: String) throws -> String? {
        queue.sync { cache[key] }
    }

    public func store(key: String, value: String) throws {
        try queue.sync {
            let previous = cache[key]
            cache[key] = value
            do {
                try persist()
            } catch {
                cache[key] = previous
                throw error
            }
        }
    }

    public func removeOrThrow(key: String) throws {
        try queue.sync {
            guard let previous = cache.removeValue(forKey: key) else { return }
            do {
                try persist()
            } catch {
                cache[key] = previous
                throw error
            }
        }
    }

    private func persistIgnoringFailure() -> Bool {
        do {
            try persist()
            return true
        } catch {
            log.error("failed to persist: \(error, .public)")
            return false
        }
    }

    private func persist() throws {
        let data = try JSONSerialization.data(withJSONObject: cache, options: [])
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}
