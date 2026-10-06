import Foundation
import Security
import XCTest
@testable import NativeEnclave

final class EnclaveRecoveryTests: XCTestCase {
    private let manager = EnclaveManager.shared

    override func setUp() async throws {
        await manager.reset()
    }

    override func tearDown() async throws {
        await manager.reset()
    }

    func testLegacySecretsMigrateIntoEmptyEnclaveAndCannotBeReplacedByAnotherMigration() async throws {
        XCTAssertTrue(EnclaveManager.isLegacyMigrationAllowed())
        XCTAssertTrue(EnclaveManager.configuredAuthTypes().isEmpty)
        let hasSecrets = try await manager.hasStoredSecrets()
        XCTAssertFalse(hasSecrets)

        let secrets = [
            (id: "0-ton-mainnet", secret: "required legacy secret"),
            (id: "keychain-only", secret: "additional legacy secret"),
        ]
        _ = try await manager.migrateSecrets(
            secrets: secrets,
            requiredSecretIds: ["0-ton-mainnet"],
            authType: .passcode,
            passcode: "1234",
            isLong: true
        )
        XCTAssertFalse(EnclaveManager.isLegacyMigrationAllowed())
        XCTAssertEqual(EnclaveManager.configuredAuthTypes(), [.passcode])

        // The recovery opt-in on setupAuth must not relax the migration boundary.
        do {
            _ = try await manager.migrateSecrets(
                secrets: [(id: "replacement", secret: "must not be imported")],
                requiredSecretIds: ["replacement"],
                authType: .passcode,
                passcode: "5678",
                isLong: true
            )
            XCTFail("Migration must not replace a committed enclave")
        } catch EnclaveError.authAlreadyConfigured {
            // Expected even if all incoming account IDs differ.
        }

        await manager.invalidateSessions()
        let session = try await authorize("1234")
        for entry in secrets {
            let secret = try await manager.exportSecret(id: entry.id, token: session.token)
            XCTAssertEqual(secret, entry.secret)
        }
        let importedIds = try await manager.existingSecretIds(in: ["0-ton-mainnet", "keychain-only", "replacement"])
        XCTAssertEqual(importedIds, ["0-ton-mainnet", "keychain-only"])
    }

    func testTransferredPasscodeOpensSecretsWithoutBiometricRecords() async throws {
        let session = try await manager.setupAuth(authType: .passcode, passcode: "1234")
        try await manager.importSecret(id: "transferred", secret: "transfer test secret", token: session.token)
        try EnclaveStorage().storeBiometricMasterKey("device-bound test record")
        EnclaveStorage().removeBiometricMasterKey()
        await manager.invalidateSessions()

        XCTAssertEqual(EnclaveManager.configuredAuthTypes(), [.passcode])
        let restored = try await authorize("1234")
        let secret = try await manager.exportSecret(id: "transferred", token: restored.token)
        XCTAssertEqual(secret, "transfer test secret")
    }

    func testRecoveryPreservesUnsupportedAndMalformedVersions() async throws {
        for version in ["99", "invalid"] {
            await manager.reset()
            try EnclaveStorage().storeSecret(id: "preserve", encrypted: "ciphertext")
            let status = SecItemAdd([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "org.mytonwallet.native-enclave.storage",
                kSecAttrAccount as String: "state:enclave_version",
                kSecValueData as String: Data(version.utf8),
            ] as CFDictionary, nil)
            XCTAssertEqual(status, errSecSuccess)

            do {
                _ = try await manager.setupAuth(authType: .passcode, passcode: "5678", replacingOrphanedAuth: true)
                XCTFail("Unsupported storage must not be replaced")
            } catch EnclaveError.unsupportedEnclaveVersion {
                // Expected for both an unknown version and an invalid marker.
            }
            XCTAssertEqual(try EnclaveStorage().loadSecret(id: "preserve"), "ciphertext")
        }
    }

    func testOrphanReplacementClearsSecretsAndSessionsAndPermitsNewImports() async throws {
        let oldSession = try await manager.setupAuth(authType: .passcode, passcode: "1234")
        try await manager.importSecret(id: "orphan", secret: "old test secret", token: oldSession.token)
        let oldAuthorization = try await authorize("1234")

        do {
            _ = try await manager.setupAuth(authType: .passcode, passcode: "5678")
            XCTFail("Ordinary setup must not overwrite authentication")
        } catch EnclaveError.authAlreadyConfigured {
            // Replacement remains opt-in at the enclave boundary.
        }
        let hadSecrets = try await manager.hasStoredSecrets()
        XCTAssertTrue(hadSecrets)

        let replacement = try await manager.setupAuth(authType: .passcode, passcode: "5678", replacingOrphanedAuth: true)
        let hasSecrets = try await manager.hasStoredSecrets()
        XCTAssertFalse(hasSecrets)
        do {
            try await manager.ensureValidSession(token: oldAuthorization.token, consumeIfNeeded: false)
            XCTFail("Old sessions must be invalidated")
        } catch EnclaveError.invalidSessionToken {
            // Expected after resetting the old master key and sessions.
        }
        let oldPasscodeResult = try await manager.authorize(authType: .passcode, isLong: false, passcode: "1234")
        XCTAssertNil(oldPasscodeResult)
        try await manager.importSecret(id: "new-wallet", secret: "new test secret", token: replacement.token)
        let session = try await authorize("5678")
        let secret = try await manager.exportSecret(id: "new-wallet", token: session.token)
        XCTAssertEqual(secret, "new test secret")
    }

    func testVersionOnlyLeftoversCanBeReplacedWithNoConfiguredMethods() async throws {
        try EnclaveStorage().storeCurrentVersion()
        XCTAssertTrue(EnclaveManager.configuredAuthTypes().isEmpty)
        _ = try await manager.setupAuth(authType: .passcode, passcode: "5678", replacingOrphanedAuth: true)
        XCTAssertEqual(EnclaveManager.configuredAuthTypes(), [.passcode])
    }

    private func authorize(_ passcode: String) async throws -> SessionResult {
        let session = try await manager.authorize(authType: .passcode, isLong: true, passcode: passcode)
        return try XCTUnwrap(session)
    }
}
