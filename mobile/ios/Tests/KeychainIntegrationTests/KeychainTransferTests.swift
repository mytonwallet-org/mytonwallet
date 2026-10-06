import Foundation
import Security
import XCTest
@testable import WalletContext

final class KeychainTransferTests: XCTestCase {
    func testClassicAccountsAndAllLegacyCiphertextSourcesRemainReadableAfterProtectionMigration() throws {
        let service = "keychain-transfer-tests.\(UUID())"
        defer { removeService(service) }
        let provider = CapacitorKeychainStorageProvider(serviceName: service)
        let records = [
            "accounts": #"{"0-ton-mainnet":{"address":"legacy-address"},"1-mainnet":{"type":"ton","mnemonicEncrypted":"inline-ciphertext"}}"#,
            "mnemonicsEncrypted": #"{"0-ton-mainnet":"separate-ciphertext"}"#,
            "backup_accounts": #"{"0-ton-mainnet":{"mnemonicEncrypted":"backup-ciphertext"}}"#,
            "backup_mnemonicsEncrypted": #"{"0-ton-mainnet":"backup-map-ciphertext"}"#,
        ]
        for (key, value) in records {
            try add(key: key, data: Data(value.utf8), service: service)
        }

        try provider.migrateToTransferableProtection()

        XCTAssertEqual(Set(provider.keys()), Set(records.keys))
        for (key, value) in records {
            // Classic and native readers must both see the original payload.
            XCTAssertEqual(provider.get(key: key).1, value)
            XCTAssertEqual(try provider.load(key: key), value)
        }
    }

    func testMigrationPreservesBytesAndOnlyChangesDeviceOnlyRecordsInItsService() throws {
        let service = "keychain-transfer-tests.\(UUID())"
        let otherService = service + ".other"
        defer { removeService(service); removeService(otherService) }
        let provider = CapacitorKeychainStorageProvider(serviceName: service)
        let payload = Data([0, 255, 128, 42])
        try add(key: "accounts", data: payload, service: service)
        try add(key: "untouched", data: payload, service: otherService)
        try provider.store(key: "already-transferable", value: "keep")

        try provider.migrateToTransferableProtection()
        try provider.migrateToTransferableProtection()

        let migrated = try item(key: "accounts", service: service)
        XCTAssertTrue(migrated[kSecValueData as String] as? Data == payload)
        XCTAssertTrue(migrated[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
        XCTAssertTrue((migrated[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue != true)
        XCTAssertTrue(try provider.load(key: "already-transferable") == "keep")
        let untouched = try item(key: "untouched", service: otherService)
        XCTAssertTrue(untouched[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    func testBothWriteAPIsUpgradeExistingRecordsAndCreateTransferableRecords() throws {
        for useLegacyAPI in [false, true] {
            let service = "keychain-transfer-tests.\(UUID())"
            defer { removeService(service) }
            let provider = CapacitorKeychainStorageProvider(serviceName: service)
            try add(key: "existing", data: Data("old".utf8), service: service)

            for key in ["existing", "new"] {
                if useLegacyAPI {
                    XCTAssertTrue(provider.set(key: key, value: "new-value"))
                } else {
                    try provider.store(key: key, value: "new-value")
                }
                XCTAssertTrue(try provider.load(key: key) == "new-value")
                XCTAssertTrue(provider.get(key: key).1 == "new-value")
                let stored = try item(key: key, service: service)
                XCTAssertTrue(stored[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
            }
            XCTAssertTrue(Set(provider.keys()) == ["existing", "new"])
        }
    }

    func testFreshInstallNeedsNoMigration() throws {
        let provider = CapacitorKeychainStorageProvider(serviceName: "keychain-transfer-tests.\(UUID())")
        try provider.migrateToTransferableProtection()
        XCTAssertTrue(provider.keys().isEmpty)
    }

    private func query(key: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Data(key.utf8),
            kSecAttrGeneric as String: Data(key.utf8),
            kSecAttrSynchronizable as String: false,
        ]
    }

    private func add(key: String, data: Data, service: String) throws {
        var query = query(key: key, service: service)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        XCTAssertEqual(status, errSecSuccess)
    }

    private func item(key: String, service: String) throws -> [String: Any] {
        var query = query(key: key, service: service)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        XCTAssertEqual(status, errSecSuccess)
        return try XCTUnwrap(result as? [String: Any])
    }

    private func removeService(_ service: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }
}
