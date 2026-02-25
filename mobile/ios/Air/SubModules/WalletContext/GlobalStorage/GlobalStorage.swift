
import Foundation
import WebKit

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

public let GlobalStorage = _GlobalStorage()

public enum GlobalStorageError: Error {
    case navigationError(any Error)
    case javaScriptError(any Error)
    case localStorageIsNull
    case localStorageIsEmpty
    case localStorageIsNotAString(Any)
    case localStorageIsInvalidJson(Any)
    case notReady
    case serializedValueIsNotAValidDict(Any?)
    case serializationError(any Error)
    case localStorageSetItemError(String)
}


private let log = Log("GlobalStorage")
private let capacitorUrl = URL(string: "capacitor://mytonwallet.local")!
private let globalStateKey = "mytonwallet-global-state"


public final class _GlobalStorage {
    
    private let _global: JSValue = .init(nil)
    private var autosync: Autosync? = nil
    
    fileprivate init() {
        autosync = Autosync(onAutosync: { [weak self] in
            Task.detached(priority: .background) { [weak self] in
                do {
                    log.info("autosync")
                    try await self?.syncronize()
                } catch {
                    log.fault("failed to autosync: \(error, .public)")
                }
            }
        })
    }

    public var globalDict: [String: Any]? {
        _global.value as? [String: Any]
    }
    
    public subscript(_ keyPath: String) -> Any? {
        _global[keyPath]
    }

    public func update(_ f: (inout JSValue.Value) -> ()) {
        _global.update(f)
    }

    public func loadFromWebView() async throws(GlobalStorageError) {
        do {
            log.info("load started")
            let json = try await WebViewGlobalStorageProvider().loadFromWebView()
            _global.update { $0[""] = json }
            log.info("load completed")
        } catch {
            log.fault("failed to load global dict from webview \(error, .public)")
            LogStore.shared.syncronize()
            throw error
        }
    }
    
    public func syncronize() async throws(GlobalStorageError) {
        log.info("sync started")
        let webView = await WebViewGlobalStorageProvider()
        guard let dict = self.globalDict?.nilIfEmpty else {
            throw .serializedValueIsNotAValidDict(_global.value)
        }
        do {
            try await webView.saveToWebView(dict)
        } catch .localStorageSetItemError(let error) {
            // setItem might fail when localStorage runs out of memory. downsizing and trying again
            do { // logs
                log.error("syncronizer localStorageSetItemError \(error, .public). will clear cache and retry")
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: []) {
                    let jsonString = String(data: data, encoding: .utf8)!
                    log.info("globalStorage size trying to save \(jsonString.count)")
                }
                if let size = try? await webView.getStoredSize() {
                    log.info("globalStorage size before clearCache \(size)")
                }
            }
            
            clearCache()
            
            guard let clearedDict = self.globalDict else {
                throw .serializedValueIsNotAValidDict(_global.value)
            }
            do { // more logs
                if let data = try? JSONSerialization.data(withJSONObject: clearedDict, options: []) {
                    let jsonString = String(data: data, encoding: .utf8)!
                    log.info("globalStorage size after clearing cache \(jsonString.count)")
                }
            }
            try await webView.saveToWebView(clearedDict)
        }
        log.info("sync completed")
    }
    
    /// Called when local storage object is too big to save.
    private func clearCache() {
        log.error("Clearing the cache!")
        update { dict in
            if let byAccountId = dict["byAccountId"] as? [String: Any] {
                for accountId in byAccountId.keys {
                    dict["byAccountId.\(accountId).activities.idsMain"] = []
                    dict["byAccountId.\(accountId).activities.isMainHistoryEndReached"] = false
                    dict["byAccountId.\(accountId).activities.idsBySlug"] = [:]
                    dict["byAccountId.\(accountId).activities.isHistoryEndReachedBySlug"] = [:]
                    dict["byAccountId.\(accountId).activities.byId"] = [:]
                    dict["byAccountId.\(accountId).activities.newestActivitiesBySlug"] = [:]
                }
            }
        }
    }
}

extension _GlobalStorage {
    
    private func persistIfNeeded(persistInstantly: Bool) {
        guard persistInstantly else { return }
        Task.detached(priority: .medium) {
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

extension _GlobalStorage {
    final class Autosync: NSObject {
        
        private var onAutosync: () -> ()
        private var observers: [Any] = []
        
        init(onAutosync: @escaping () -> ()) {
            self.onAutosync = onAutosync
            var observers: [Any] = []
            let notifications = [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification, UIApplication.didReceiveMemoryWarningNotification]
            for name in notifications {
                let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                    onAutosync()
                }
                observers.append(observer)
            }
            self.observers = observers
        }
    }
}
