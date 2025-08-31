//
//  CapacitorCredentialsStorage.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/15/24.
//

import Foundation

private let log = Log("CapacitorCredentialsStorage")

public class CapacitorCredentialsStorage {
    public struct Credentials {
        public var username: String
        public var password: String
    }
    public enum KeychainError: Error {
        case noPassword
        case unexpectedPasswordData
        case duplicateItem
        case unhandledError(status: OSStatus)
    }

    public static func migrate() {
        do {
            let credentials = try getCredentials().orThrow()
            if credentials.username != NATIVE_BIOMETRICS_USERNAME {
                log.error("credentials.username != MyTonWallet \(credentials.username, .public)")
                var ok: Bool = deleteCredentials()
                guard ok else {
                    log.fault("failed to delete credentials")
                    return
                }
                ok = setCredentials(password: credentials.password)
                guard ok else {
                    log.fault("failed to add credentials")
                    return
                }
                log.info("migration successful")
            }
        } catch {
            log.info("migration error: \(error, .public)")
        }
    }
    
    public static func getCredentials() -> Credentials? {
        do {
            let credentials = try getCredentialsFromKeychain(NATIVE_BIOMETRICS_SERVER)
            return credentials
        } catch {
            log.fault("failed to get credentials: \(error, .public)")
            return nil
        }
    }
    
    static func setCredentials(password: String) -> Bool {
        let credentials = Credentials(username: NATIVE_BIOMETRICS_USERNAME, password: password)
        
        do {
            try storeCredentialsInKeychain(credentials, NATIVE_BIOMETRICS_SERVER)
            return true
        } catch KeychainError.duplicateItem {
            do {
                try updateCredentialsInKeychain(credentials, NATIVE_BIOMETRICS_SERVER)
                return true
            } catch {
                return false
            }
        } catch {
            return false
        }
    }
    
    public static func deleteCredentials() -> Bool {
        do {
            try deleteCredentialsFromKeychain(NATIVE_BIOMETRICS_SERVER)
            return true
        } catch {
            log.fault("failed to delete credentials: \(error)")
            return false
        }
    }
    
    // Store user Credentials in Keychain
    private static func storeCredentialsInKeychain(_ credentials: Credentials, _ server: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrAccount as String: credentials.username,
                                    kSecAttrServer as String: server,
                                    kSecValueData as String: credentials.password.data(using: .utf8)!]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status != errSecDuplicateItem else { throw KeychainError.duplicateItem }
        guard status == errSecSuccess else { throw KeychainError.unhandledError(status: status) }
    }
    
    // Update user Credentials in Keychain
    private static func updateCredentialsInKeychain(_ credentials: Credentials, _ server: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrServer as String: server]
        
        let account = credentials.username
        let password = credentials.password.data(using: String.Encoding.utf8)!
        let attributes: [String: Any] = [kSecAttrAccount as String: account,
                                         kSecValueData as String: password]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard status != errSecItemNotFound else { throw KeychainError.noPassword }
        guard status == errSecSuccess else { throw KeychainError.unhandledError(status: status) }
    }
    
    // Get user Credentials from Keychain
    private static func getCredentialsFromKeychain(_ server: String) throws -> Credentials {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrServer as String: server,
                                    kSecMatchLimit as String: kSecMatchLimitOne,
                                    kSecReturnAttributes as String: true,
                                    kSecReturnData as String: true]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw KeychainError.noPassword }
        guard status == errSecSuccess else { throw KeychainError.unhandledError(status: status) }
        
        guard let existingItem = item as? [String: Any],
              let passwordData = existingItem[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8),
              let username = existingItem[kSecAttrAccount as String] as? String
        else {
            throw KeychainError.unexpectedPasswordData
        }
        
        let credentials = Credentials(username: username, password: password)
        return credentials
    }
    
    // Delete user Credentials from Keychain
    private static func deleteCredentialsFromKeychain(_ server: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrServer as String: server]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unhandledError(status: status) }
    }

}
