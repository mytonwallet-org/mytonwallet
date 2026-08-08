import Foundation
import NativeEnclave
import WalletContext

private let legacyLog = Log("AuthSupportLegacy")

enum AuthSupportLegacy {
    static var hasLegacyBiometrics: Bool {
        guard AppStorageHelper.isLegacyBiometricActivated() else {
            return false
        }
        do {
            return try legacyBiometricPasscode() != nil
        } catch {
            legacyLog.error("failed to read legacy biometric passcode: \(error, .public)")
            return true
        }
    }

    static func configuredMethodsIfNoNativeAuth() -> Set<AuthMethod> {
        var methods = Set<AuthMethod>()
        if !requiredLegacyAccountIds().isEmpty {
            methods.insert(.passcode)
            if hasLegacyBiometrics {
                methods.insert(.biometrics)
            }
        }
        return methods
    }

    static func needsMigration() -> Bool {
        EnclaveManager.isLegacyMigrationAllowed() && !requiredLegacyAccountIds().isEmpty
    }

    static func authorizeWithPasscode(
        _ passcode: String,
        sessionKind: AuthSessionKind,
        usageCount: Int
    ) async throws -> EnclaveToken? {
        guard let migration = try await migrateFromLegacy(passcode: passcode, isLong: true) else {
            return nil
        }

        await persistMigrationOutcomeBestEffort(migration)
        cleanupAfterMigrationBestEffort(accountIds: migration.migratedAccountIds)

        if hasLegacyBiometrics {
            do {
                _ = try await addBiometrics(currentToken: migration.session.token)
                clearBiometricArtifacts()
            } catch {
                legacyLog.error("legacy biometric migration failed: \(error, .public)")
            }
        }

        return try await authorizeEnclave(
            authType: .passcode,
            sessionKind: sessionKind,
            usageCount: usageCount,
            passcode: passcode
        )
    }

    static func authorizeWithBiometrics(
        sessionKind: AuthSessionKind,
        usageCount: Int
    ) async throws -> EnclaveToken? {
        let legacyPasscode = try legacyBiometricPasscode()
        guard let legacyPasscode else {
            return nil
        }

        let currentToken: EnclaveToken
        if needsMigration() {
            guard let migration = try await migrateFromLegacy(passcode: legacyPasscode, isLong: true) else {
                return nil
            }
            await persistMigrationOutcomeBestEffort(migration)
            cleanupAfterMigrationBestEffort(accountIds: migration.migratedAccountIds)
            currentToken = migration.session.token
        } else {
            guard let enclaveToken = try await authorizeEnclave(
                authType: .passcode,
                sessionKind: .reusable,
                usageCount: 1,
                passcode: legacyPasscode
            ) else {
                return nil
            }
            currentToken = enclaveToken
        }

        let biometricToken: EnclaveToken
        do {
            biometricToken = try await addBiometrics(
                currentToken: currentToken,
                sessionKind: sessionKind,
                usageCount: usageCount
            ).token
        } catch EnclaveError.biometricAuthenticationCanceled {
            // nil is reserved for authorization failures; a canceled prompt must stay distinguishable
            throw EnclaveError.biometricAuthenticationCanceled
        } catch {
            legacyLog.error("legacy biometric migration failed: \(error, .public)")
            return nil
        }

        clearBiometricArtifacts()
        return biometricToken
    }

    static func clearBiometricArtifacts() {
        do {
            try KeychainHelper.deleteBiometricPasscode()
            AppStorageHelper.removeLegacyBiometricActivation()
        } catch {
            legacyLog.error("failed to clear legacy biometric artifacts: \(error, .public)")
        }
    }

    static func retryCleanupAfterCommittedMigration() async {
        guard !EnclaveManager.configuredAuthTypes().isEmpty else {
            legacyLog.error("skipping committed migration reconciliation: enclave has no configured auth")
            return
        }
        let storedEncryptedAccountIds = requiredLegacyAccountIds()
        do {
            let migratedAccountIds = try await EnclaveManager.shared.existingSecretIds(
                in: storedEncryptedAccountIds
            )
            let recoveryRequiredAccountIds = storedEncryptedAccountIds.subtracting(migratedAccountIds)
            let changedAccountIds = try await AccountStore.reconcileSecretStates(
                availableAccountIds: migratedAccountIds,
                recoveryRequiredAccountIds: recoveryRequiredAccountIds
            )
            if !changedAccountIds.isEmpty {
                legacyLog.info(
                    "reconciled committed enclave secret states changedIds=\(changedAccountIds.sorted(), .public)"
                )
            }
            if !recoveryRequiredAccountIds.isEmpty {
                legacyLog.fault(
                    "committed enclave has accounts requiring secret recovery count=\(recoveryRequiredAccountIds.count) ids=\(recoveryRequiredAccountIds.sorted(), .public)"
                )
                logPreservedLegacySecrets(accountIds: recoveryRequiredAccountIds)
            }
            cleanupAfterMigrationBestEffort(accountIds: migratedAccountIds)
        } catch {
            legacyLog.error("failed to inspect migrated legacy accounts: \(error, .public)")
        }
        if AppStorageHelper.isLegacyBiometricActivated(),
           EnclaveManager.configuredAuthTypes().contains(.biometric) {
            clearBiometricArtifacts()
        }
    }

    private static func authorizeEnclave(
        authType: AuthType,
        sessionKind: AuthSessionKind,
        usageCount: Int,
        passcode: String?
    ) async throws -> EnclaveToken? {
        let session = try await EnclaveManager.shared.authorize(
            authType: authType,
            isLong: sessionKind.isLong,
            usageCount: usageCount,
            passcode: passcode
        )
        return session?.token
    }

    private static func addBiometrics(
        currentToken: EnclaveToken,
        sessionKind: AuthSessionKind = .oneShot,
        usageCount: Int = 1
    ) async throws -> SessionResult {
        try await EnclaveManager.shared.migrateAuth(
            currentToken: currentToken,
            newAuthType: .biometric,
            passcode: nil,
            shouldReplace: false,
            isLong: sessionKind.isLong,
            usageCount: usageCount
        )
    }

    private static func migrateFromLegacy(
        passcode: String,
        isLong: Bool
    ) async throws -> LegacyMigrationResult? {
        let rawAccounts = try KeychainHelper.loadAccounts() ?? [:]
        let manifest = LegacyAccountManifest.build(
            rawAccounts: rawAccounts,
            requiredAccountIds: requiredLegacyAccountIds()
        )
        guard !manifest.requiredAccountIds.isEmpty else {
            return nil
        }

        do {
            return try await LegacyMigration.migrateToEnclave(
                manifest: manifest,
                passcode: passcode,
                isLong: isLong
            )
        } catch LegacyMigrationError.invalidPasscode {
            return nil
        } catch LegacyMigrationError.damagedData {
            // Thrown, not mapped to nil: a nil result reads as a failed login, feeds
            // the attempt counter whose cooldown unlocks the destructive sign-out, and
            // the legacy ciphertext that sign-out erases is the only remaining copy of
            // these mnemonics.
            throw DisplayError(
                title: lang("$enclave_migration_damaged_title"),
                text: lang("$enclave_migration_damaged_message", arg1: "@\(SUPPORT_USERNAME)")
            )
        } catch {
            throw error
        }
    }

    private static func legacyBiometricPasscode() throws -> String? {
        guard AppStorageHelper.isLegacyBiometricActivated() else {
            return nil
        }

        let passcode = try KeychainHelper.loadBiometricPasscode()?.nilIfEmpty
        if passcode == nil {
            clearBiometricArtifacts()
        }
        return passcode
    }

    private static func persistMigrationOutcomeBestEffort(_ migration: LegacyMigrationResult) async {
        do {
            let changedAccountIds = try await AccountStore.reconcileSecretStates(
                availableAccountIds: migration.migratedRequiredAccountIds,
                recoveryRequiredAccountIds: migration.recoveryRequiredAccountIds
            )
            legacyLog.info(
                "persisted legacy migration secret states available=\(migration.migratedRequiredAccountIds.count) recoveryRequired=\(migration.recoveryRequiredAccountIds.count) changedIds=\(changedAccountIds.sorted(), .public)"
            )
        } catch {
            legacyLog.fault(
                "failed to persist legacy migration secret states recoveryRequiredIds=\(migration.recoveryRequiredAccountIds.sorted(), .public) error=\(error, .public)"
            )
        }

        if !migration.recoveryRequiredAccountIds.isEmpty {
            legacyLog.fault(
                "legacy migration completed with recovery-required accounts missingIds=\(migration.missingLegacyDataAccountIds.sorted(), .public) unreadableIds=\(migration.corruptedLegacyDataAccountIds.sorted(), .public)"
            )
            logPreservedLegacySecrets(accountIds: migration.recoveryRequiredAccountIds)
        }
    }

    private static func logPreservedLegacySecrets(accountIds: Set<String>) {
        do {
            let accounts = try KeychainHelper.loadAccounts() ?? [:]
            let preservedAccountIds = accountIds.filter {
                accounts[$0]?["mnemonicEncrypted"] != nil
            }
            legacyLog.fault(
                "preserving legacy ciphertext for recovery-required accounts count=\(preservedAccountIds.count) ids=\(preservedAccountIds.sorted(), .public)"
            )
        } catch {
            legacyLog.error(
                "failed to inspect preserved recovery-required legacy ciphertext ids=\(accountIds.sorted(), .public) error=\(error, .public)"
            )
        }
    }

    private static func cleanupAfterMigrationBestEffort(accountIds: Set<String>) {
        guard !accountIds.isEmpty else {
            return
        }
        do {
            try cleanupAfterMigration(accountIds: accountIds)
        } catch {
            legacyLog.error("legacy account cleanup failed: \(error, .public)")
        }
    }

    private static func cleanupAfterMigration(accountIds: Set<String>) throws {
        guard let accounts = try KeychainHelper.loadAccounts(), !accounts.isEmpty else {
            return
        }
        var updatedAccounts = accounts
        var cleanedAccountIds: [String] = []
        for accountId in accountIds.sorted() {
            guard let account = accounts[accountId] else {
                continue
            }
            guard account["mnemonicEncrypted"] != nil else {
                continue
            }
            var updated = account
            updated["mnemonicEncrypted"] = nil
            updatedAccounts[accountId] = updated
            cleanedAccountIds.append(accountId)
        }

        guard !cleanedAccountIds.isEmpty else {
            return
        }
        try KeychainHelper.saveAccounts(updatedAccounts)
        legacyLog.info(
            "removed migrated legacy ciphertext count=\(cleanedAccountIds.count) ids=\(cleanedAccountIds, .public)"
        )
    }

    private static func requiredLegacyAccountIds() -> Set<String> {
        var accountIds = Set<String>()
        for account in AccountStore.accountsById.values where account.type.isStoredEncrypted {
            accountIds.insert(account.id)
        }
        return accountIds
    }
}
