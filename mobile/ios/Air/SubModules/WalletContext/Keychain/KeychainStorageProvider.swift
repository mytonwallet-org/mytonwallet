
private let log = Log("KeychainStorageProvider")

public protocol IKeychainStorageProvider {
    func set(key: String, value: String) -> Bool
    func get(key: String) -> (Bool, String?)
    func remove(key: String) -> Bool
    func keys() -> [String]
}

public let KeychainStorageProvider: IKeychainStorageProvider = CapacitorKeychainStorageProvider()

public class CapacitorKeychainStorageProvider: IKeychainStorageProvider {
    
    var keychainWrapper: KeychainWrapper = KeychainWrapper.init(serviceName: "cap_sec")
    
    public init() {}
    
    public func set(key: String, value: String) -> Bool {
        let saveSuccessful: Bool = keychainWrapper.set(value, forKey: key, withAccessibility: .afterFirstUnlockThisDeviceOnly)
        if saveSuccessful == false {
            log.error("failed to save to keychain key=\(key, .public)")
        }
        return saveSuccessful
    }
    
    public func get(key: String) -> (Bool, String?) {
        if keychainWrapper.hasValue(forKey: key) {
            return (true, keychainWrapper.string(forKey: key) ?? "")
        }
        return (false, nil)
    }
    
    public func keys() -> [String] {
        let keys = keychainWrapper.allKeys();
        return Array(keys)
    }
    
    public func remove(key: String) -> Bool {
        log.info("remove key=\(key, .public)")
        if keychainWrapper.hasValue(forKey: key) {
            return keychainWrapper.removeObject(forKey: key)
        }
        return false
    }
}

