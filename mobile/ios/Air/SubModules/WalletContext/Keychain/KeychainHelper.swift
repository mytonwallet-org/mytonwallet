//
//  KeychainHelper.swift
//  WalletContext
//
//  Created by Sina on 3/16/24.
//

import Foundation

private let log = Log("KeychainHelper")


public struct KeychainHelper {

    public static func deleteAccountsFromPreviousInstall() {
        let accountsCount = KeychainHelper.getAccounts()?.count ?? 0
        log.info("Detected \(accountsCount) accounts from previous install")
        if accountsCount > 0 {
            log.info("Deleting now")
            deleteAllWallets()
        }
    }
    
    // MARK: - StorageDB Replacement to prevent WKWebView dexie issues
    public static func getStorage(key: String) -> String? {
        KeychainStorageProvider.get(key: key).1
    }
    public static func saveStorage(key: String, value: String?) {
        if let value {
            _ = KeychainStorageProvider.set(key: key, value: value)
        } else {
            removeStorage(key: key)
        }
    }
    public static func removeStorage(key: String) {
        _ = KeychainStorageProvider.remove(key: key)
    }
    public static func clearStorage() {
        KeychainStorageProvider.keys().forEach { key in
            _ = KeychainStorageProvider.remove(key: key)
        }
    }
    // only a shortcut to make accounts available to swift without fetching accounts one by one :)
    public static func getAccounts() -> [String: [String: Any]]? {
        try? loadAccounts()
    }

    public static func loadAccounts() throws -> [String: [String: Any]]? {
        guard let accounts = try KeychainStorageProvider.load(key: "accounts") else {
            return nil
        }
        guard let accountsData = accounts.data(using: .utf8),
              let jsonDictionary = try JSONSerialization.jsonObject(
                with: accountsData,
                options: []
              ) as? [String: [String: Any]] else {
            throw KeychainStorageProviderError.invalidValue
        }
        return jsonDictionary
    }

    public static func saveAccounts(_ accounts: [String: [String: Any]]) throws {
        let data = try JSONSerialization.data(withJSONObject: accounts)
        guard let json = String(data: data, encoding: .utf8) else {
            throw KeychainStorageProviderError.invalidUTF8
        }
        try KeychainStorageProvider.store(key: "accounts", value: json)
    }

    // MARK: - Biometric passcode
    public static func save(biometricPasscode: String?) {
        guard let biometricPasscode else {
            _ = CapacitorCredentialsStorage.deleteCredentials()
            return
        }
        _ = CapacitorCredentialsStorage.setCredentials(password: biometricPasscode)
    }
    public static func biometricPasscode() -> String {
        return CapacitorCredentialsStorage.getCredentials()?.password ?? ""
    }

    public static func loadBiometricPasscode() throws -> String? {
        try CapacitorCredentialsStorage.loadCredentials()?.password
    }

    public static func deleteBiometricPasscode() throws {
        try CapacitorCredentialsStorage.deleteCredentialsOrThrow()
    }
    
    // MARK: - Keys
    public static func keys() -> [String] {
        KeychainStorageProvider.keys()
    }

    // MARK: - Delete Wallet
    public static func deleteAllWallets() {
        log.info("deleteAllWallets")
        _ = CapacitorCredentialsStorage.deleteCredentials()
        KeychainHelper.save(biometricPasscode: nil)
        [kSecClassGenericPassword,
         kSecClassInternetPassword,
         kSecClassCertificate,
         kSecClassKey,
         kSecClassIdentity].forEach { dataClass in
          let status = SecItemDelete([
            kSecClass: dataClass,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny
          ] as CFDictionary)
          if status != errSecSuccess && status != errSecItemNotFound {
              log.error("Error while removing class \(dataClass, .public) status=\(status, .public)")
          }
        }
    }
}
