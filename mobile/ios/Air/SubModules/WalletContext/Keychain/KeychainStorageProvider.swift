
private let log = Log("KeychainStorageProvider")

public protocol IKeychainStorageProvider {
    func set(key: String, value: String) -> Bool
    func get(key: String) -> (Bool, String?)
    func remove(key: String) -> Bool
    func keys() -> [String]
}

public let KeychainStorageProvider: IKeychainStorageProvider = CapacitorKeychainStorageProvider()

public class CapacitorKeychainStorageProvider: IKeychainStorageProvider {
    
    var keychainwrapper: KeychainWrapper = KeychainWrapper.init(serviceName: "cap_sec")
    
    public init() {}
    
    public func set(key: String, value: String) -> Bool {
        let saveSuccessful: Bool = keychainwrapper.set(value, forKey: key, withAccessibility: .afterFirstUnlockThisDeviceOnly)
        if saveSuccessful == false {
            log.error("failed to save to keychain key=\(key, .public)")
        }
        return saveSuccessful
    }
    
    public func get(key: String) -> (Bool, String?) {
        let hasValueDedicated = keychainwrapper.hasValue(forKey: key)
        let hasValueStandard = keychainwrapper.hasValue(forKey: key)
        
        // copy standard value to dedicated and remove standard key
        if (hasValueStandard && !hasValueDedicated) {
            let syncValueSuccessful: Bool = keychainwrapper.set(
                keychainwrapper.string(forKey: key) ?? "",
                forKey: key,
                withAccessibility: .afterFirstUnlock
            )
            let removeValueSuccessful: Bool = keychainwrapper.removeObject(forKey: key)
            if (!syncValueSuccessful || !removeValueSuccessful) {
                return (false, nil)
            }
        }
        
        if hasValueDedicated || hasValueStandard {
            return (true, keychainwrapper.string(forKey: key) ?? "")
        }
        else {
            return (false, nil)
        }
    }
    
    public func keys() -> [String] {
        let keys = keychainwrapper.allKeys();
        return Array(keys)
    }
    
    public func remove(key: String) -> Bool {
        log.info("remove key=\(key, .public)")
        let hasValueDedicated = keychainwrapper.hasValue(forKey: key)
        let hasValueStandard = keychainwrapper.hasValue(forKey: key)
        
        if hasValueDedicated || hasValueStandard {
            keychainwrapper.removeObject(forKey: key);
            let removeDedicatedSuccessful: Bool = keychainwrapper.removeObject(forKey: key)
            return removeDedicatedSuccessful
        }
        return false
    }
}

