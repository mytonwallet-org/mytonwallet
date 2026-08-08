
import Foundation
import Security

private let log = Log("KeychainStorageProvider")

public enum KeychainStorageProviderError: LocalizedError {
    case keychain(OSStatus)
    case invalidUTF8
    case invalidValue

    public var errorDescription: String? {
        switch self {
        case let .keychain(status):
            "Keychain error: \(status)"
        case .invalidUTF8:
            "Keychain value is not valid UTF-8"
        case .invalidValue:
            "Keychain value could not be encoded"
        }
    }
}

public protocol IKeychainStorageProvider: Sendable {
    func set(key: String, value: String) -> Bool
    func get(key: String) -> (Bool, String?)
    func remove(key: String) -> Bool
    func keys() -> [String]
    func load(key: String) throws -> String?
    func store(key: String, value: String) throws
}

public let KeychainStorageProvider: IKeychainStorageProvider = CapacitorKeychainStorageProvider()

public final class CapacitorKeychainStorageProvider: IKeychainStorageProvider, Sendable {
    
    private static let serviceName = "cap_sec"
    let keychainWrapper: KeychainWrapper = KeychainWrapper.init(serviceName: serviceName)
    
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

    public func load(key: String) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query(key: key, returnData: true) as CFDictionary,
            &result
        )
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStorageProviderError.keychain(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainStorageProviderError.invalidUTF8
        }
        return value
    }

    public func store(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainStorageProviderError.invalidValue
        }

        var addQuery = query(key: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(
                query(key: key) as CFDictionary,
                attributes as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainStorageProviderError.keychain(updateStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else {
            throw KeychainStorageProviderError.keychain(addStatus)
        }
    }

    private func query(key: String, returnData: Bool = false) -> [String: Any] {
        let encodedKey = Data(key.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrGeneric as String: encodedKey,
            kSecAttrAccount as String: encodedKey,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if returnData {
            query[kSecReturnData as String] = kCFBooleanTrue
        } else {
            query.removeValue(forKey: kSecMatchLimit as String)
        }
        return query
    }
}
