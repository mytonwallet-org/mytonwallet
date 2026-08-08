import Foundation
import Security

struct PasscodeCredential: Codable, Equatable {
    let salt: Data
    let wrappedMasterKey: String
}

final class EnclaveStorage {
    static let currentVersion = 0

    private static let keychainService = "org.mytonwallet.native-enclave.storage"

    private let enclaveVersionKey = "state:enclave_version"
    private let passcodeCredentialKey = "auth:passcode_credential"
    private let legacyPasscodeSaltKey = "auth:salt"
    private let biometricMasterKeyKey = "master_key:biometric"
    private let masterKeyPrefix = "master_key:"
    private let secretPrefix = "secret#"

    func storeCurrentVersion() throws {
        try KeychainStore.setString(
            String(Self.currentVersion),
            account: enclaveVersionKey,
            service: Self.keychainService
        )
    }

    func loadVersion() throws -> Int? {
        guard let stored = try KeychainStore.getString(
            account: enclaveVersionKey,
            service: Self.keychainService
        ) else {
            return nil
        }
        guard let version = Int(stored), version >= 0 else {
            throw EnclaveError.unsupportedEnclaveVersion(stored)
        }
        return version
    }

    func storePasscodeCredential(_ credential: PasscodeCredential) throws {
        let data = try JSONEncoder().encode(credential)
        try KeychainStore.setData(
            data,
            account: passcodeCredentialKey,
            service: Self.keychainService
        )
    }

    func loadPasscodeCredential() throws -> PasscodeCredential? {
        guard let data = try KeychainStore.getData(
            account: passcodeCredentialKey,
            service: Self.keychainService
        ) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(PasscodeCredential.self, from: data)
        } catch {
            throw EnclaveError.malformedEncryptedPayload
        }
    }

    func removePasscodeCredential() {
        KeychainStore.remove(account: passcodeCredentialKey, service: Self.keychainService)
    }

    func storeBiometricMasterKey(_ encrypted: String) throws {
        try KeychainStore.setString(
            encrypted,
            account: biometricMasterKeyKey,
            service: Self.keychainService,
            accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
    }

    func loadBiometricMasterKey() -> String? {
        try? KeychainStore.getString(
            account: biometricMasterKeyKey,
            service: Self.keychainService
        )
    }

    func removeBiometricMasterKey() {
        KeychainStore.remove(account: biometricMasterKeyKey, service: Self.keychainService)
    }

    func storeSecret(id: String, encrypted: String) throws {
        try KeychainStore.setString(encrypted, account: secretPrefix + id, service: Self.keychainService)
    }

    func loadSecret(id: String) throws -> String {
        guard let encrypted = try KeychainStore.getString(account: secretPrefix + id, service: Self.keychainService) else {
            throw EnclaveError.secretNotFound(id)
        }
        return encrypted
    }

    func copySecret(fromId: String, toId: String) throws {
        let encrypted = try loadSecret(id: fromId)
        try storeSecret(id: toId, encrypted: encrypted)
    }

    func removeSecret(id: String) {
        KeychainStore.remove(account: secretPrefix + id, service: Self.keychainService)
    }

    func containsSecret(id: String) throws -> Bool {
        try KeychainStore.getString(
            account: secretPrefix + id,
            service: Self.keychainService
        ) != nil
    }

    func hasAnySecret() throws -> Bool {
        try KeychainStore.allAccounts(service: Self.keychainService)
            .contains { $0.hasPrefix(secretPrefix) }
    }

    func storeSecretsBatch(_ pairs: [(id: String, encrypted: String)]) throws {
        for pair in pairs {
            try storeSecret(id: pair.id, encrypted: pair.encrypted)
        }
    }

    func clear() {
        guard let accounts = try? KeychainStore.allAccounts(service: Self.keychainService) else {
            return
        }

        for account in accounts where isStorageKey(account) {
            KeychainStore.remove(account: account, service: Self.keychainService)
        }
    }

    func clearChecked() throws {
        let accounts = try KeychainStore.allAccounts(service: Self.keychainService)
        for account in accounts where isStorageKey(account) {
            try KeychainStore.removeChecked(account: account, service: Self.keychainService)
        }
        let remaining = try KeychainStore.allAccounts(service: Self.keychainService)
        guard !remaining.contains(where: isStorageKey) else {
            throw EnclaveError.malformedEncryptedPayload
        }
    }

    private func isStorageKey(_ key: String) -> Bool {
        key == enclaveVersionKey
            || key == passcodeCredentialKey
            || key == legacyPasscodeSaltKey
            || key.hasPrefix(masterKeyPrefix)
            || key.hasPrefix(secretPrefix)
    }
}

private enum KeychainStore {
    static func setData(
        _ data: Data,
        account: String,
        service: String,
        accessibility: CFString = kSecAttrAccessibleWhenUnlocked
    ) throws {
        try upsertData(
            data,
            account: account,
            service: service,
            accessibility: accessibility
        )
    }

    static func setString(
        _ value: String,
        account: String,
        service: String,
        accessibility: CFString = kSecAttrAccessibleWhenUnlocked
    ) throws {
        guard let data = value.data(using: .utf8) else {
            throw EnclaveError.malformedEncryptedPayload
        }
        try upsertData(
            data,
            account: account,
            service: service,
            accessibility: accessibility
        )
    }

    static func getData(account: String, service: String) throws -> Data? {
        try readData(account: account, service: service)
    }

    static func getString(account: String, service: String) throws -> String? {
        guard let data = try readData(account: account, service: service) else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw EnclaveError.malformedEncryptedPayload
        }
        return value
    }

    static func allAccounts(service: String) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw EnclaveError.keychainError(status)
        }

        guard let items = result as? [[String: Any]] else {
            return []
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    static func remove(account: String, service: String) {
        try? removeChecked(account: account, service: service)
    }

    static func removeChecked(account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EnclaveError.keychainError(status)
        }
    }

    private static func upsertData(
        _ data: Data,
        account: String,
        service: String,
        accessibility: CFString
    ) throws {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility,
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
                kSecAttrAccessible as String: accessibility,
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

    private static func readData(account: String, service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

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
}
