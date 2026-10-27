import Foundation
import NativeEnclave
import WalletContext

public struct WalletRecoveryDiagnostics: Encodable, Sendable {
    public let generatedAt: Date
    public let isLegacyMigrationAllowed: Bool
    public let accounts: [Account]

    public struct Account: Encodable, Identifiable, Sendable {
        public let id: String
        public let enclaveSecret: Presence
        public let legacySources: [LegacySource]
    }

    public struct LegacySource: Encodable, Sendable {
        public let key: String
        public let ciphertext: Presence
    }

    public enum Presence: String, Encodable, Sendable {
        case present
        case missing
        case unavailable
    }

    public var exportText: String {
        var lines = [
            "Wallet recovery diagnostics",
            "Checked: \(generatedAt.ISO8601Format())",
            "Legacy migration allowed: \(isLegacyMigrationAllowed)",
        ]
        for account in accounts {
            lines.append("")
            lines.append("Account: \(account.id)")
            lines.append("Enclave secret: \(account.enclaveSecret.rawValue)")
            for source in account.legacySources {
                lines.append("\(source.key): \(source.ciphertext.rawValue)")
            }
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    public static func collect() async -> WalletRecoveryDiagnostics? {
        let accounts = Array(AccountStore.accountsById.values)
        let isLegacyMigrationAllowed = EnclaveManager.isLegacyMigrationAllowed()
        var enclaveSecretAccountIds: Set<String>?
        if !isLegacyMigrationAllowed {
            enclaveSecretAccountIds = try? await EnclaveManager.shared.existingSecretIds(
                in: Set(accounts.filter { $0.type.isStoredEncrypted }.map(\.id))
            )
        }
        return await collect(
            accounts: accounts,
            isLegacyMigrationAllowed: isLegacyMigrationAllowed,
            enclaveSecretAccountIds: enclaveSecretAccountIds
        )
    }

    static func collect(
        accounts: [MAccount],
        isLegacyMigrationAllowed: Bool,
        enclaveSecretAccountIds: Set<String>?
    ) async -> WalletRecoveryDiagnostics? {
        let affected = affectedAccounts(
            accounts: accounts,
            isLegacyMigrationAllowed: isLegacyMigrationAllowed,
            enclaveSecretAccountIds: enclaveSecretAccountIds
        )
        guard !affected.isEmpty else { return nil }

        let sources = await Task.detached(priority: .userInitiated) {
            inspectLegacySources { source in
                switch source {
                case .accounts, .backupAccounts:
                    return LegacyAccountManifest.ciphertexts(
                        in: try KeychainHelper.loadAccounts(key: source.rawValue) ?? [:]
                    )
                case .mnemonicsEncrypted, .backupMnemonicsEncrypted:
                    return try KeychainHelper.loadLegacyMnemonicCiphertexts(key: source.rawValue) ?? [:]
                }
            }
        }.value

        return makeReport(
            accounts: affected,
            isLegacyMigrationAllowed: isLegacyMigrationAllowed,
            enclaveSecretAccountIds: enclaveSecretAccountIds,
            legacySourceAccountIds: sources
        )
    }

    static func affectedAccounts(
        accounts: [MAccount],
        isLegacyMigrationAllowed: Bool,
        enclaveSecretAccountIds: Set<String>?
    ) -> [MAccount] {
        accounts.filter { account in
            guard account.type.isStoredEncrypted else { return false }
            if let enclaveSecretAccountIds {
                // Presence takes precedence over an outdated recovery flag.
                if enclaveSecretAccountIds.contains(account.id) { return false }
                if !isLegacyMigrationAllowed { return true }
            }
            // An unavailable inspection must not turn a healthy account into a failure.
            return account.secretState?.isRecoveryRequired == true
        }.sorted { $0.id < $1.id }
    }

    static func inspectLegacySources(
        load: (LegacyCiphertextSourceName) throws -> [String: String]
    ) -> [String: Set<String>] {
        var accountIds: [String: Set<String>] = [:]
        for source in LegacyCiphertextSourceName.allCases {
            if let ciphertexts = try? load(source) {
                accountIds[source.rawValue] = Set(ciphertexts.filter { !$0.value.isEmpty }.keys)
            }
        }
        return accountIds
    }

    static func makeReport(
        accounts: [MAccount],
        isLegacyMigrationAllowed: Bool,
        enclaveSecretAccountIds: Set<String>?,
        legacySourceAccountIds: [String: Set<String>]
    ) -> WalletRecoveryDiagnostics {
        WalletRecoveryDiagnostics(
            generatedAt: Date(),
            isLegacyMigrationAllowed: isLegacyMigrationAllowed,
            accounts: accounts.map { account in
                Account(
                    id: account.id,
                    enclaveSecret: presence(of: account.id, in: enclaveSecretAccountIds),
                    legacySources: LegacyCiphertextSourceName.allCases.map { source in
                        LegacySource(
                            key: source.rawValue,
                            ciphertext: presence(of: account.id, in: legacySourceAccountIds[source.rawValue])
                        )
                    }
                )
            }
        )
    }

    private static func presence(of accountId: String, in accountIds: Set<String>?) -> Presence {
        guard let accountIds else { return .unavailable }
        return accountIds.contains(accountId) ? .present : .missing
    }
}
