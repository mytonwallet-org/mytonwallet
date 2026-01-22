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
    // only a shortcut to make accounts available to swift without fetching accounts one by one :)
    public static func getAccounts() -> [String: [String: Any]]? {
        guard let accountsData = KeychainStorageProvider.get(key: "accounts").1?.data(using: .utf8) else {
            return nil
        }
        guard let jsonDictionary = try? JSONSerialization.jsonObject(with: accountsData, options: []) as? [String: [String: Any]] else {
            return nil
        }
        return jsonDictionary
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
    
    // MARK: - AppLock settings
    private static let appLockKey = "appLock"
    public static func save(appLock: Bool) {
        // TODO::
    }

    // MARK: - Recent addresses
    private static var recentAddressesKey = "recentAddresses"
    public static func save(accountId: String, recentAddresses: String?) {
        _ = KeychainStorageProvider.set(key: "\(recentAddressesKey)_\(accountId)", value: recentAddresses ?? "")
    }
    public static func recentAddresses(accountId: String) -> String? {
        KeychainStorageProvider.get(key: "\(recentAddressesKey)_\(accountId)").1
    }

    // MARK: - Passcode length
    private static var passcodeLengthKey = "passcodeLength"
    public static func save(passcodeLength: Int) {
        _ = KeychainStorageProvider.set(key: passcodeLengthKey, value: "\(passcodeLength)")
    }
    public static func passcodeLength() -> Int {
        Int(KeychainStorageProvider.get(key: passcodeLengthKey).1 ?? "") ?? 4
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
        KeychainHelper.save(appLock: true)
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
