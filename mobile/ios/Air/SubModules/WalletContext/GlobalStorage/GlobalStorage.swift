import Foundation

public protocol IGlobalStorageProvider {
    var dontSynchronize: Int { get set }
    func getInt(key: String) -> Int?
    func getString(key: String) -> String?
    func getBool(key: String) -> Bool?
    func getDict(key: String) -> [String: Any]?
    func getArray(key: String) -> [Any?]?
    
    func set<T>(key: String, value: T?, persistInstantly: Bool)
    func set(items: [String: Any?], persistInstantly: Bool)
    func setEmptyObject(key: String, persistInstantly: Bool)
    func setEmptyObjects(keys: [String], persistInstantly: Bool)
    func remove(key: String, persistInstantly: Bool)
    func remove(keys: [String], persistInstantly: Bool)
    
    func keysIn(key: String) -> [String]
    func deleteAll() async throws
}

public enum GlobalStorageError: Error, @unchecked Sendable { // todo: remove Any associated values
    case navigationError(any Error)
    case javaScriptError(any Error)
    case localStorageIsNull
    case localStorageIsEmpty
    case localStorageIsNotAString(Any)
    case localStorageIsInvalidJson(Any)
    case notReady
    case serializedValueIsNotAValidDict(Any?)
    case localStorageReadbackFailed(String)
    case serializationError(any Error)
    case localStorageSetItemError(String)
}


private let log = Log("GlobalStorage")

private struct WebViewStorageErrorPayload: Decodable {
    let name: String?
    let message: String?
    let description: String?
}

@MainActor
public final class GlobalStorage {
    private var global = Value(nil)
    
    public init() {}

    public var globalDict: [String: Any]? {
        global.rawValue as? [String: Any]
    }
    
    public subscript(_ keyPath: String) -> Any? {
        global[keyPath]
    }

    public func update(_ f: (inout Value) -> Void) {
        f(&global)
    }

    public func loadFromWebView() async throws(GlobalStorageError) {
        do {
            log.info("load started")
            let json = try await WebViewGlobalStorageProvider().loadFromWebView()
            update { $0[""] = json }
            log.info("load completed")
        } catch {
            log.fault("failed to load global dict from webview \(error, .public)")
            LogStore.shared.syncronize()
            throw error
        }
    }
    
    public func syncronize() async throws(GlobalStorageError) {
        log.info("sync started")
        let webView = WebViewGlobalStorageProvider()
        try await syncronize(using: webView, canRetryAfterClearingCache: true)
        log.info("sync completed")
    }
    
    /// Called when local storage object is too big to save.
    private func clearCache() -> Bool {
        var didClear = false
        update { dict in
            if let byAccountId = dict["byAccountId"] as? [String: Any] {
                for accountId in byAccountId.keys {
                    guard dict["byAccountId.\(accountId).activities"] != nil else { continue }
                    didClear = true
                    dict["byAccountId.\(accountId).activities.idsMain"] = []
                    dict["byAccountId.\(accountId).activities.isMainHistoryEndReached"] = false
                    dict["byAccountId.\(accountId).activities.idsBySlug"] = [:]
                    dict["byAccountId.\(accountId).activities.isHistoryEndReachedBySlug"] = [:]
                    dict["byAccountId.\(accountId).activities.byId"] = [:]
                    dict["byAccountId.\(accountId).activities.newestActivitiesBySlug"] = [:]
                }
            }
        }
        if didClear {
            log.error("Clearing the cache!")
        }
        return didClear
    }
}

extension GlobalStorage {
    private func syncronize(
        using webView: WebViewGlobalStorageProvider,
        canRetryAfterClearingCache: Bool
    ) async throws(GlobalStorageError) {
        guard let dict = globalDict?.nilIfEmpty else {
            throw .serializedValueIsNotAValidDict(global.rawValue)
        }
        do {
            try await webView.saveToWebView(dict)
        } catch .localStorageSetItemError(let error) {
            try await handleSaveFailure(
                error,
                attemptedDict: dict,
                using: webView,
                canRetryAfterClearingCache: canRetryAfterClearingCache
            )
        } catch .localStorageReadbackFailed(let details) {
            await logFailedSaveDiagnostics(
                attemptedDict: dict,
                using: webView,
                failureDescription: "localStorage readback failed \(details)"
            )
            throw .localStorageReadbackFailed(details)
        }
    }

    private func handleSaveFailure(
        _ error: String,
        attemptedDict: [String: Any],
        using webView: WebViewGlobalStorageProvider,
        canRetryAfterClearingCache: Bool
    ) async throws(GlobalStorageError) {
        await logFailedSaveDiagnostics(
            attemptedDict: attemptedDict,
            using: webView,
            failureDescription: "localStorageSetItemError \(error)"
        )

        guard canRetryAfterClearingCache, errorLikelyCausedByStorageQuota(error) else {
            throw .localStorageSetItemError(error)
        }

        let previousGlobal = global
        guard clearCache() else {
            throw .localStorageSetItemError(error)
        }

        log.error("retrying global storage sync after clearing nonessential cache")
        do {
            try await syncronize(using: webView, canRetryAfterClearingCache: false)
        } catch {
            global = previousGlobal
            throw error
        }
    }

    private func logFailedSaveDiagnostics(
        attemptedDict: [String: Any],
        using webView: WebViewGlobalStorageProvider,
        failureDescription: String
    ) async {
        log.error("syncronizer \(failureDescription, .public). will not mutate state automatically")
        if let data = try? JSONSerialization.data(withJSONObject: attemptedDict, options: []) {
            let jsonString = String(data: data, encoding: .utf8)!
            log.info("globalStorage size trying to save \(jsonString.count)")
        }
        if let size = try? await webView.getStoredSize() {
            log.info("globalStorage size before failed save \(size)")
        }
    }

    private func errorLikelyCausedByStorageQuota(_ error: String) -> Bool {
        let details: [String]
        if let data = error.data(using: .utf8),
           let payload = try? JSONDecoder().decode(WebViewStorageErrorPayload.self, from: data) {
            details = [payload.name, payload.message, payload.description]
                .compactMap { $0?.lowercased() }
        } else {
            details = [error.lowercased()]
        }

        return details.contains {
            $0.contains("quotaexceeded")
                || $0.contains("quota exceeded")
                || $0.contains("quota")
        }
    }
    
    private func persistIfNeeded(persistInstantly: Bool) {
        guard persistInstantly else { return }
        Task(priority: .medium) {
            do {
                try await self.syncronize()
            } catch {
                log.error("sync error \(error, .public)")
            }
        }
    }
    
    public func getInt(key: String) -> Int? {
        self[key] as? Int
    }
    
    public func getString(key: String) -> String? {
        self[key] as? String
    }
    
    public func getBool(key: String) -> Bool? {
        self[key] as? Bool
    }
    
    public func getDict(key: String) -> [String : Any]? {
        self[key] as? [String: Any]
    }
    
    public func getArray(key: String) -> [Any?]? {
        self[key] as? [Any?]
    }
    
    public func set<T>(key: String, value: T?, persistInstantly: Bool) {
        update { $0[key] = value }
        persistIfNeeded(persistInstantly: persistInstantly)
    }
    
    public func set(items: [String : Any?], persistInstantly: Bool) {
        update {
            for (key, value) in items {
                $0[key] = value
            }
        }
        persistIfNeeded(persistInstantly: persistInstantly)
    }
    
    public func setEmptyObject(key: String, persistInstantly: Bool) {
        update {
            $0[key] = [:]
        }
        persistIfNeeded(persistInstantly: persistInstantly)
    }
    
    public func setEmptyObjects(keys: [String], persistInstantly: Bool) {
        update {
            for key in keys {
                $0[key] = [:]
            }
        }
        persistIfNeeded(persistInstantly: persistInstantly)
    }
    
    public func remove(key: String, persistInstantly: Bool) {
        update {
            $0[key] = nil
        }
        persistIfNeeded(persistInstantly: persistInstantly)
    }
    
    public func remove(keys: [String], persistInstantly: Bool) {
        update {
            for key in keys {
                $0[key] = nil
            }
        }
        persistIfNeeded(persistInstantly: persistInstantly)
    }
    
    public func keysIn(key: String) -> [String]? {
        (getDict(key: key)?.keys).flatMap(Array.init)
    }
    
    public func deleteAll() async throws {
        try await WebViewGlobalStorageProvider().deleteAll()
    }
}
