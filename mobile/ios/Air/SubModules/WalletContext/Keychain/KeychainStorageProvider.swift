
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
        let hasValueDedicated = keychainWrapper.hasValue(forKey: key)
        let hasValueStandard = keychainWrapper.hasValue(forKey: key)
        
        // copy standard value to dedicated and remove standard key
        if (hasValueStandard && !hasValueDedicated) {
            let syncValueSuccessful: Bool = keychainWrapper.set(
                keychainWrapper.string(forKey: key) ?? "",
                forKey: key,
                withAccessibility: .afterFirstUnlock
            )
            let removeValueSuccessful: Bool = keychainWrapper.removeObject(forKey: key)
            if (!syncValueSuccessful || !removeValueSuccessful) {
                return (false, nil)
            }
        }
        
        if hasValueDedicated || hasValueStandard {
            return (true, keychainWrapper.string(forKey: key) ?? "")
        }
        else {
            return (false, nil)
        }
    }
    
    public func keys() -> [String] {
        let keys = keychainWrapper.allKeys();
        return Array(keys)
    }
    
    public func remove(key: String) -> Bool {
        log.info("remove key=\(key, .public)")
        let hasValueDedicated = keychainWrapper.hasValue(forKey: key)
        let hasValueStandard = keychainWrapper.hasValue(forKey: key)
        
        if hasValueDedicated || hasValueStandard {
            keychainWrapper.removeObject(forKey: key);
            let removeDedicatedSuccessful: Bool = keychainWrapper.removeObject(forKey: key)
            return removeDedicatedSuccessful
        }
        return false
    }
}

