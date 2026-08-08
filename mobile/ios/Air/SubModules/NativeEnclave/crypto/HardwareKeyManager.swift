import Foundation
import LocalAuthentication
import Security

enum HardwareKeyManager {
    private static let dataKeyAlias = "mtw_enclave_data"
    private static let biometricKeyAlias = "mtw_enclave_biometric"

    static func encrypt(_ plaintext: String) throws -> String {
        let keyData = try getOrCreateDataKey()
        return try AesGcm.encrypt(Data(plaintext.utf8), keyData: keyData)
    }

    static func decrypt(_ encrypted: String) throws -> String {
        let keyData = try getOrCreateDataKey()
        let data = try AesGcm.decrypt(encrypted, keyData: keyData)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EnclaveError.malformedEncryptedPayload
        }
        return string
    }

    static func ensureBiometricKey() throws {
        let random = try KeyDerivation.generateMasterKey()
        try KeychainStore.addBiometricDataIfMissing(random, account: biometricKeyAlias)
    }

    static func loadBiometricKey(context: LAContext) throws -> Data {
        guard let keyData = try KeychainStore.getData(account: biometricKeyAlias, context: context) else {
            throw EnclaveError.biometricNotConfigured
        }
        return keyData
    }

    static func deleteDataKey() {
        KeychainStore.remove(account: dataKeyAlias)
    }

    static func deleteBiometricKey() {
        KeychainStore.remove(account: biometricKeyAlias)
    }

    private static func getOrCreateDataKey() throws -> Data {
        if let data = try KeychainStore.getData(account: dataKeyAlias) {
            return data
        }

        let key = try KeyDerivation.generateMasterKey()
        try KeychainStore.setData(key, account: dataKeyAlias)
        return key
    }
}

private enum KeychainStore {
    private static let service = "org.mytonwallet.native-enclave"

    static func setData(_ data: Data, account: String) throws {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw EnclaveError.keychainError(updateStatus)
            }
            return
        }

        guard addStatus == errSecSuccess else {
            throw EnclaveError.keychainError(addStatus)
        }
    }

    static func addBiometricDataIfMissing(_ data: Data, account: String) throws {
        var cfError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &cfError
        ) else {
            throw EnclaveError.biometricNotAvailable
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl,
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            return
        }

        guard addStatus == errSecSuccess else {
            throw EnclaveError.keychainError(addStatus)
        }
    }

    static func getData(account: String, context: LAContext? = nil) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        if let context {
            query[kSecUseAuthenticationContext as String] = context
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw EnclaveError.keychainError(status)
        }

        return item as? Data
    }

    static func remove(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
