import CommonCrypto
import CryptoKit
import Foundation
import NativeEnclave
import WalletContext

private let log = Log("LegacyMigration")

struct LegacyAccountWithMnemonic {
    let accountId: String
    let mnemonicEncrypted: String
}

enum LegacyCiphertextSourceName: String, CaseIterable {
    case accounts
    case mnemonicsEncrypted
    case backupAccounts = "backup_accounts"
    case backupMnemonicsEncrypted = "backup_mnemonicsEncrypted"
}

struct LegacyCiphertextSource {
    let name: LegacyCiphertextSourceName
    let ciphertextByAccountId: [String: String]
}

struct LegacyAccountManifest {
    let requiredAccountIds: Set<String>
    let ciphertextByAccountId: [String: String]
    let sourceByAccountId: [String: LegacyCiphertextSourceName]

    var missingRequiredAccountIds: Set<String> {
        requiredAccountIds.subtracting(ciphertextByAccountId.keys)
    }

    var requiredAccounts: [LegacyAccountWithMnemonic] {
        accounts(for: requiredAccountIds)
    }

    var optionalAccounts: [LegacyAccountWithMnemonic] {
        accounts(for: Set(ciphertextByAccountId.keys).subtracting(requiredAccountIds))
    }

    static func build(
        rawAccounts: [String: [String: Any]],
        requiredAccountIds: Set<String>
    ) -> LegacyAccountManifest {
        build(
            sources: [
                LegacyCiphertextSource(
                    name: .accounts,
                    ciphertextByAccountId: ciphertexts(in: rawAccounts)
                ),
            ],
            requiredAccountIds: requiredAccountIds
        )
    }

    static func build(
        sources: [LegacyCiphertextSource],
        requiredAccountIds: Set<String>
    ) -> LegacyAccountManifest {
        var ciphertextByAccountId: [String: String] = [:]
        var sourceByAccountId: [String: LegacyCiphertextSourceName] = [:]

        for source in sources {
            for (accountId, ciphertext) in source.ciphertextByAccountId
                where ciphertextByAccountId[accountId] == nil && !ciphertext.isEmpty {
                ciphertextByAccountId[accountId] = ciphertext
                sourceByAccountId[accountId] = source.name
            }
        }

        return LegacyAccountManifest(
            requiredAccountIds: requiredAccountIds,
            ciphertextByAccountId: ciphertextByAccountId,
            sourceByAccountId: sourceByAccountId
        )
    }

    static func ciphertexts(
        in rawAccounts: [String: [String: Any]]
    ) -> [String: String] {
        rawAccounts.reduce(into: [String: String]()) {
            result,
            item in
            let (accountId, account) = item
            if let ciphertext = account["mnemonicEncrypted"] as? String,
               !ciphertext.isEmpty {
                result[accountId] = ciphertext
            }
        }
    }

    private func accounts(for accountIds: Set<String>) -> [LegacyAccountWithMnemonic] {
        accountIds.sorted().compactMap { accountId in
            ciphertextByAccountId[accountId].map {
                LegacyAccountWithMnemonic(
                    accountId: accountId,
                    mnemonicEncrypted: $0
                )
            }
        }
    }
}

struct LegacyMigrationResult {
    let session: SessionResult
    let migratedAccountIds: Set<String>
    let migratedRequiredAccountIds: Set<String>
    let recoveryRequiredAccountIds: Set<String>
    let missingLegacyDataAccountIds: Set<String>
    let corruptedLegacyDataAccountIds: Set<String>
}

struct LegacySecretResolution {
    let secrets: [(id: String, secret: String)]
    let migratedRequiredAccountIds: Set<String>
    let missingRequiredAccountIds: Set<String>
    let corruptedRequiredAccountIds: Set<String>

    var recoveryRequiredAccountIds: Set<String> {
        missingRequiredAccountIds.union(corruptedRequiredAccountIds)
    }
}

enum LegacyMigrationError: LocalizedError {
    case invalidPasscode
    case damagedData

    var errorDescription: String? {
        switch self {
        case .invalidPasscode:
            return "Invalid passcode"
        case .damagedData:
            return "Legacy wallet data is unreadable"
        }
    }
}

enum LegacyMigration {
    static func decryptLegacyMnemonic(_ encrypted: String, passcode: String) -> [String]? {
        do {
            if encrypted.contains(":") {
                return try decryptPbkdf2Format(encrypted, passcode: passcode)
            } else {
                return try decryptSha256Format(encrypted, passcode: passcode)
            }
        } catch {
            log.error("decryptLegacyMnemonic failed: \(error, .public)")
            return nil
        }
    }

    static func migrateToEnclave(
        manifest: LegacyAccountManifest,
        passcode: String,
        isLong: Bool
    ) async throws -> LegacyMigrationResult {
        log.info(
            "legacy migration manifest required=\(manifest.requiredAccountIds.count) ciphertexts=\(manifest.ciphertextByAccountId.count) missingRequired=\(manifest.missingRequiredAccountIds.count) keychainOnly=\(manifest.optionalAccounts.count)"
        )
        let resolution = try decryptLegacySecrets(manifest: manifest, passcode: passcode)
        let manager = EnclaveManager.shared

        do {
            let session = try await manager.migrateSecrets(
                secrets: resolution.secrets,
                requiredSecretIds: resolution.migratedRequiredAccountIds,
                authType: .passcode,
                passcode: passcode,
                isLong: isLong
            )
            let migratedAccountIds = Set(resolution.secrets.map(\.id))
            logRecoveredFallbackSecrets(
                manifest: manifest,
                migratedAccountIds: migratedAccountIds
            )
            log.info(
                "legacy migration committed migrated=\(migratedAccountIds.count) migratedRequired=\(resolution.migratedRequiredAccountIds.count) recoveryRequired=\(resolution.recoveryRequiredAccountIds.count)"
            )
            return LegacyMigrationResult(
                session: session,
                migratedAccountIds: migratedAccountIds,
                migratedRequiredAccountIds: resolution.migratedRequiredAccountIds,
                recoveryRequiredAccountIds: resolution.recoveryRequiredAccountIds,
                missingLegacyDataAccountIds: resolution.missingRequiredAccountIds,
                corruptedLegacyDataAccountIds: resolution.corruptedRequiredAccountIds
            )
        } catch {
            log.fault("migrateToEnclave failed: \(error, .public)")
            throw error
        }
    }

    static func decryptLegacySecrets(
        manifest: LegacyAccountManifest,
        passcode: String
    ) throws -> LegacySecretResolution {
        let requiredResults = decrypt(
            accounts: manifest.requiredAccounts,
            passcode: passcode
        )
        guard !requiredResults.secrets.isEmpty else {
            // A typo verdict requires at least one failed decryption attempt and no
            // sibling ciphertext opening with the same passcode. Anything else means
            // the stored data is unreadable: presenting that as a wrong passcode would
            // rate-limit the user and steer him toward erasing the legacy ciphertext,
            // which is the only remaining copy of these mnemonics.
            if manifest.requiredAccounts.isEmpty
                || !decrypt(accounts: manifest.optionalAccounts, passcode: passcode).secrets.isEmpty {
                log.fault(
                    "legacy migration data is unreadable required=\(manifest.requiredAccountIds.count) missingRequiredIds=\(manifest.missingRequiredAccountIds.sorted(), .public) unreadableRequiredIds=\(requiredResults.failedAccountIds.sorted(), .public)"
                )
                throw LegacyMigrationError.damagedData
            }
            throw LegacyMigrationError.invalidPasscode
        }

        let migratedRequiredAccountIds = Set(requiredResults.secrets.map(\.id))
        let corruptedRequiredAccountIds = Set(requiredResults.failedAccountIds)
        let missingRequiredAccountIds = manifest.missingRequiredAccountIds
        let recoveryRequiredAccountIds = missingRequiredAccountIds.union(corruptedRequiredAccountIds)
        if !recoveryRequiredAccountIds.isEmpty {
            log.fault(
                "legacy migration will require recovery count=\(recoveryRequiredAccountIds.count) missingIds=\(missingRequiredAccountIds.sorted(), .public) unreadableIds=\(corruptedRequiredAccountIds.sorted(), .public)"
            )
        }

        let optionalResults = decrypt(
            accounts: manifest.optionalAccounts,
            passcode: passcode
        )
        if !optionalResults.failedAccountIds.isEmpty {
            log.fault(
                "preserving unreadable keychain-only legacy ciphertext count=\(optionalResults.failedAccountIds.count) ids=\(optionalResults.failedAccountIds.sorted(), .public)"
            )
        }

        var secrets = requiredResults.secrets
        secrets.append(contentsOf: optionalResults.secrets)
        return LegacySecretResolution(
            secrets: secrets,
            migratedRequiredAccountIds: migratedRequiredAccountIds,
            missingRequiredAccountIds: missingRequiredAccountIds,
            corruptedRequiredAccountIds: corruptedRequiredAccountIds
        )
    }

    private static func logRecoveredFallbackSecrets(
        manifest: LegacyAccountManifest,
        migratedAccountIds: Set<String>
    ) {
        let recoveredAccounts: [(accountId: String, source: LegacyCiphertextSourceName)] =
            migratedAccountIds.sorted().compactMap { accountId in
                guard let source = manifest.sourceByAccountId[accountId], source != .accounts else {
                    return nil
                }
                return (accountId: accountId, source: source)
            }
        guard !recoveredAccounts.isEmpty else {
            return
        }

        let recoveredAccountIds = Set(recoveredAccounts.map { $0.accountId })
        let recoveredRequiredAccountIds = recoveredAccountIds.intersection(manifest.requiredAccountIds)
        let recoveredOptionalAccountIds = recoveredAccountIds.subtracting(manifest.requiredAccountIds)
        let recoveredSources = recoveredAccounts.map { "\($0.accountId):\($0.source.rawValue)" }
        log.fault(
            "legacy mnemonics missing from accounts and recovered from fallback count=\(recoveredAccountIds.count) requiredIds=\(recoveredRequiredAccountIds.sorted(), .public) optionalIds=\(recoveredOptionalAccountIds.sorted(), .public) sources=\(recoveredSources, .public)"
        )
    }

    private static func decrypt(
        accounts: [LegacyAccountWithMnemonic],
        passcode: String
    ) -> (secrets: [(id: String, secret: String)], failedAccountIds: [String]) {
        var secrets: [(id: String, secret: String)] = []
        var failedAccountIds: [String] = []
        secrets.reserveCapacity(accounts.count)

        for account in accounts {
            if let mnemonic = decryptLegacyMnemonic(
                account.mnemonicEncrypted,
                passcode: passcode
            ) {
                secrets.append(
                    (
                        id: account.accountId,
                        secret: mnemonic.joined(separator: " ")
                    )
                )
            } else {
                failedAccountIds.append(account.accountId)
            }
        }
        return (secrets, failedAccountIds)
    }

    private static func decryptPbkdf2Format(_ encrypted: String, passcode: String) throws -> [String] {
        let parts = encrypted.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let salt = Data(hexString: parts[0]),
              let iv = Data(hexString: parts[1]),
              let ciphertext = Data(base64Encoded: parts[2]) else {
            throw SdkError.unexpected(message: "Invalid PBKDF2 format")
        }

        let key = try derivePbkdf2Key(passcode: passcode, salt: salt)
        let plaintext = try decryptAesGcm(ciphertextAndTag: ciphertext, iv: iv, keyData: key)
        return plaintext.split(separator: ",").map(String.init)
    }

    private static func decryptSha256Format(_ encrypted: String, passcode: String) throws -> [String] {
        guard encrypted.count > 24,
              let iv = Data(hexString: String(encrypted.prefix(24))),
              let ciphertext = Data(base64Encoded: String(encrypted.dropFirst(24))) else {
            throw SdkError.unexpected(message: "Invalid SHA-256 format")
        }

        let key = Data(SHA256.hash(data: Data(passcode.utf8)))
        let plaintext = try decryptAesGcm(ciphertextAndTag: ciphertext, iv: iv, keyData: key)
        return plaintext.split(separator: ",").map(String.init)
    }

    private static func derivePbkdf2Key(passcode: String, salt: Data) throws -> Data {
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passcode,
                passcode.lengthOfBytes(using: .utf8),
                saltBytes.bindMemory(to: UInt8.self).baseAddress,
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                100_000,
                &derived,
                derived.count
            )
        }

        guard status == kCCSuccess else {
            throw SdkError.unexpected(message: "PBKDF2 derivation failed", context: status)
        }
        return Data(derived)
    }

    private static func decryptAesGcm(ciphertextAndTag: Data, iv: Data, keyData: Data) throws -> String {
        var combined = Data()
        combined.reserveCapacity(iv.count + ciphertextAndTag.count)
        combined.append(iv)
        combined.append(ciphertextAndTag)

        let key = SymmetricKey(data: keyData)
        let box = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(box, using: key)

        guard let result = String(data: plaintext, encoding: .utf8) else {
            throw SdkError.unexpected(message: "Invalid UTF-8 payload")
        }
        return result
    }
}
