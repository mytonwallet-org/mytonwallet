import CryptoKit
import Foundation
import Testing
@testable import WalletCore

@Suite("Legacy Enclave Migration")
struct LegacyMigrationTests {
    @Test
    func `requires ciphertext for every database account`() {
        let manifest = LegacyAccountManifest.build(
            rawAccounts: [
                "present": ["mnemonicEncrypted": "ciphertext"],
                "keychain-only": ["mnemonicEncrypted": "other"],
            ],
            requiredAccountIds: ["present", "missing"]
        )

        #expect(manifest.missingRequiredAccountIds == ["missing"])
        #expect(manifest.requiredAccounts.map(\.accountId) == ["present"])
        #expect(manifest.optionalAccounts.map(\.accountId) == ["keychain-only"])
    }

    @Test
    func `merges exact account ids from legacy sources in priority order`() {
        let manifest = LegacyAccountManifest.build(
            sources: [
                LegacyCiphertextSource(
                    name: .accounts,
                    ciphertextByAccountId: ["active": "active-ciphertext"]
                ),
                LegacyCiphertextSource(
                    name: .mnemonicsEncrypted,
                    ciphertextByAccountId: [
                        "active": "stale-active-ciphertext",
                        "legacy-map": "legacy-map-ciphertext",
                    ]
                ),
                LegacyCiphertextSource(
                    name: .backupAccounts,
                    ciphertextByAccountId: [
                        "legacy-map": "stale-legacy-map-ciphertext",
                        "backup-account": "backup-account-ciphertext",
                    ]
                ),
                LegacyCiphertextSource(
                    name: .backupMnemonicsEncrypted,
                    ciphertextByAccountId: [
                        "backup-account": "stale-backup-account-ciphertext",
                        "backup-map": "backup-map-ciphertext",
                    ]
                ),
            ],
            requiredAccountIds: ["active", "legacy-map", "backup-account", "backup-map"]
        )

        #expect(
            manifest.ciphertextByAccountId == [
                "active": "active-ciphertext",
                "legacy-map": "legacy-map-ciphertext",
                "backup-account": "backup-account-ciphertext",
                "backup-map": "backup-map-ciphertext",
            ]
        )
        #expect(manifest.sourceByAccountId["active"] == .accounts)
        #expect(manifest.sourceByAccountId["legacy-map"] == .mnemonicsEncrypted)
        #expect(manifest.sourceByAccountId["backup-account"] == .backupAccounts)
        #expect(manifest.sourceByAccountId["backup-map"] == .backupMnemonicsEncrypted)
    }

    @Test
    func `does not treat old and current account id formats as aliases`() {
        let manifest = LegacyAccountManifest.build(
            sources: [
                LegacyCiphertextSource(
                    name: .mnemonicsEncrypted,
                    ciphertextByAccountId: ["0-mainnet": "ciphertext"]
                ),
            ],
            requiredAccountIds: ["0-ton-mainnet"]
        )

        #expect(manifest.missingRequiredAccountIds == ["0-ton-mainnet"])
        #expect(manifest.requiredAccounts.isEmpty)
        #expect(manifest.optionalAccounts.map(\.accountId) == ["0-mainnet"])
    }

    @Test
    func `recovers a required old style account from the top level legacy map`() throws {
        let manifest = LegacyAccountManifest.build(
            sources: [
                LegacyCiphertextSource(
                    name: .accounts,
                    ciphertextByAccountId: [:]
                ),
                LegacyCiphertextSource(
                    name: .mnemonicsEncrypted,
                    ciphertextByAccountId: [
                        "0-ton-mainnet": try encrypt(
                            "alpha,beta,gamma",
                            passcode: "1234",
                            nonceByte: 11
                        ),
                    ]
                ),
            ],
            requiredAccountIds: ["0-ton-mainnet"]
        )

        let resolution = try LegacyMigration.decryptLegacySecrets(
            manifest: manifest,
            passcode: "1234"
        )

        #expect(manifest.sourceByAccountId["0-ton-mainnet"] == .mnemonicsEncrypted)
        #expect(resolution.migratedRequiredAccountIds == ["0-ton-mainnet"])
        #expect(resolution.recoveryRequiredAccountIds.isEmpty)
    }

    @Test
    func `missing database ciphertext requires recovery after passcode is confirmed`() throws {
        let manifest = LegacyAccountManifest.build(
            rawAccounts: [
                "present": [
                    "mnemonicEncrypted": try encrypt(
                        "alpha,beta,gamma",
                        passcode: "1234",
                        nonceByte: 0
                    ),
                ],
            ],
            requiredAccountIds: ["present", "missing"]
        )

        let resolution = try LegacyMigration.decryptLegacySecrets(
            manifest: manifest,
            passcode: "1234"
        )

        #expect(resolution.migratedRequiredAccountIds == ["present"])
        #expect(resolution.missingRequiredAccountIds == ["missing"])
        #expect(resolution.corruptedRequiredAccountIds.isEmpty)
        #expect(resolution.recoveryRequiredAccountIds == ["missing"])
    }

    @Test
    func `includes readable keychain-only accounts`() throws {
        let manifest = LegacyAccountManifest.build(
            rawAccounts: [
                "database": [
                    "mnemonicEncrypted": try encrypt(
                        "alpha,beta,gamma",
                        passcode: "1234",
                        nonceByte: 1
                    ),
                ],
                "keychain-only": [
                    "mnemonicEncrypted": try encrypt(
                        "delta,epsilon,zeta",
                        passcode: "1234",
                        nonceByte: 2
                    ),
                ],
            ],
            requiredAccountIds: ["database"]
        )

        let resolution = try LegacyMigration.decryptLegacySecrets(
            manifest: manifest,
            passcode: "1234"
        )

        #expect(
            Dictionary(uniqueKeysWithValues: resolution.secrets.map { ($0.id, $0.secret) })
                == [
                    "database": "alpha beta gamma",
                    "keychain-only": "delta epsilon zeta",
                ]
        )
    }

    @Test
    func `ignores keychain-only accounts encrypted with another passcode`() throws {
        let manifest = LegacyAccountManifest.build(
            rawAccounts: [
                "database": [
                    "mnemonicEncrypted": try encrypt(
                        "alpha,beta,gamma",
                        passcode: "1234",
                        nonceByte: 3
                    ),
                ],
                "keychain-only": [
                    "mnemonicEncrypted": try encrypt(
                        "delta,epsilon,zeta",
                        passcode: "5678",
                        nonceByte: 4
                    ),
                ],
            ],
            requiredAccountIds: ["database"]
        )

        let resolution = try LegacyMigration.decryptLegacySecrets(
            manifest: manifest,
            passcode: "1234"
        )

        #expect(resolution.secrets.map(\.id) == ["database"])
        #expect(resolution.recoveryRequiredAccountIds.isEmpty)
    }

    @Test
    func `requires recovery for a database account encrypted with another passcode`() throws {
        let manifest = LegacyAccountManifest.build(
            rawAccounts: [
                "different-passcode": [
                    "mnemonicEncrypted": try encrypt(
                        "delta,epsilon,zeta",
                        passcode: "5678",
                        nonceByte: 5
                    ),
                ],
                "valid": [
                    "mnemonicEncrypted": try encrypt(
                        "alpha,beta,gamma",
                        passcode: "1234",
                        nonceByte: 6
                    ),
                ],
            ],
            requiredAccountIds: ["different-passcode", "valid"]
        )

        let resolution = try LegacyMigration.decryptLegacySecrets(
            manifest: manifest,
            passcode: "1234"
        )

        #expect(resolution.migratedRequiredAccountIds == ["valid"])
        #expect(resolution.corruptedRequiredAccountIds == ["different-passcode"])
        #expect(resolution.recoveryRequiredAccountIds == ["different-passcode"])
    }

    @Test
    func `reports invalid passcode when no required record decrypts`() throws {
        let manifest = LegacyAccountManifest.build(
            rawAccounts: [
                "first": [
                    "mnemonicEncrypted": try encrypt(
                        "alpha,beta,gamma",
                        passcode: "1234",
                        nonceByte: 7
                    ),
                ],
                "second": [
                    "mnemonicEncrypted": try encrypt(
                        "delta,epsilon,zeta",
                        passcode: "1234",
                        nonceByte: 8
                    ),
                ],
            ],
            requiredAccountIds: ["first", "second"]
        )

        do {
            _ = try LegacyMigration.decryptLegacySecrets(
                manifest: manifest,
                passcode: "9999"
            )
            Issue.record("Expected invalid passcode")
        } catch LegacyMigrationError.invalidPasscode {
            // Expected.
        }
    }

    @Test
    func `reports damaged data when no required ciphertext exists`() throws {
        let manifest = LegacyAccountManifest.build(
            rawAccounts: [:],
            requiredAccountIds: ["missing"]
        )

        do {
            _ = try LegacyMigration.decryptLegacySecrets(
                manifest: manifest,
                passcode: "1234"
            )
            Issue.record("Expected damaged data")
        } catch LegacyMigrationError.damagedData {
            // Expected.
        }
    }

    @Test
    func `reports invalid passcode when a required account is missing and no sibling opens`() throws {
        let manifest = LegacyAccountManifest.build(
            rawAccounts: [
                "present": [
                    "mnemonicEncrypted": try encrypt(
                        "alpha,beta,gamma",
                        passcode: "1234",
                        nonceByte: 10
                    ),
                ],
            ],
            requiredAccountIds: ["present", "missing"]
        )

        // A ciphertext that refuses to open carries no evidence of why: AES-GCM fails
        // identically for a wrong key and for tampered bytes. An account whose ciphertext
        // is absent was never opened, so it cannot arbitrate that. The typo stays the
        // verdict here, which keeps the attempt counter alive on the legacy path; the
        // missing account is picked up as recovery-required on the first correct entry.
        do {
            _ = try LegacyMigration.decryptLegacySecrets(
                manifest: manifest,
                passcode: "9999"
            )
            Issue.record("Expected invalid passcode")
        } catch LegacyMigrationError.invalidPasscode {
            // Expected.
        }
    }

    @Test
    func `reports damaged data when a keychain-only account proves the passcode`() throws {
        let manifest = LegacyAccountManifest.build(
            rawAccounts: [
                "database": ["mnemonicEncrypted": "not-a-ciphertext"],
                "keychain-only": [
                    "mnemonicEncrypted": try encrypt(
                        "alpha,beta,gamma",
                        passcode: "1234",
                        nonceByte: 9
                    ),
                ],
            ],
            requiredAccountIds: ["database"]
        )

        do {
            _ = try LegacyMigration.decryptLegacySecrets(
                manifest: manifest,
                passcode: "1234"
            )
            Issue.record("Expected damaged data")
        } catch LegacyMigrationError.damagedData {
            // Expected.
        }
    }

    private func encrypt(
        _ plaintext: String,
        passcode: String,
        nonceByte: UInt8
    ) throws -> String {
        let nonceData = Data(repeating: nonceByte, count: 12)
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let key = SymmetricKey(data: Data(SHA256.hash(data: Data(passcode.utf8))))
        let sealed = try AES.GCM.seal(
            Data(plaintext.utf8),
            using: key,
            nonce: nonce
        )
        let ciphertextAndTag = sealed.ciphertext + sealed.tag
        return nonceData.hexString + ciphertextAndTag.base64EncodedString()
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
