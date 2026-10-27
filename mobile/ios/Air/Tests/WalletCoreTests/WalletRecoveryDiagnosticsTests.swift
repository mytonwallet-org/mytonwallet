import Foundation
import Testing
@testable import WalletCore

@Suite("Wallet recovery diagnostics")
struct WalletRecoveryDiagnosticsTests {
    @Test
    func `only affected mnemonic accounts appear after migration`() {
        let accounts = [
            account("healthy"),
            account("missing"),
            account("flagged", recoveryRequired: true),
            account("stale-flag", recoveryRequired: true),
            account("ledger", type: .hardware, recoveryRequired: true),
            account("watch", type: .view, recoveryRequired: true),
        ]

        let affected = WalletRecoveryDiagnostics.affectedAccounts(
            accounts: accounts,
            isLegacyMigrationAllowed: false,
            enclaveSecretAccountIds: ["healthy", "stale-flag"]
        )

        #expect(affected.map(\.id) == ["flagged", "missing"])
    }

    @Test
    func `pending migration and failed inspection do not flag healthy wallets`() {
        for migrationAllowed in [true, false] {
            let affected = WalletRecoveryDiagnostics.affectedAccounts(
                accounts: [account("healthy"), account("flagged", recoveryRequired: true)],
                isLegacyMigrationAllowed: migrationAllowed,
                enclaveSecretAccountIds: nil
            )
            #expect(affected.map(\.id) == ["flagged"])
        }

        #expect(WalletRecoveryDiagnostics.affectedAccounts(
            accounts: [account("pending")],
            isLegacyMigrationAllowed: true,
            enclaveSecretAccountIds: []
        ).isEmpty)
    }

    @Test
    func `healthy profile has no diagnostic section or export payload`() async {
        let report = await WalletRecoveryDiagnostics.collect(
            accounts: [account("healthy")],
            isLegacyMigrationAllowed: false,
            enclaveSecretAccountIds: ["healthy"]
        )
        #expect(report == nil)
    }

    @Test
    func `fallback sources use exact ids and preserve unavailable status`() throws {
        let sources = WalletRecoveryDiagnostics.inspectLegacySources { source in
            switch source {
            case .accounts:
                return ["7-mainnet": "different-account-ciphertext"]
            case .mnemonicsEncrypted:
                return ["7-ton-mainnet": ""]
            case .backupAccounts:
                return ["7-ton-mainnet": "retained-ciphertext"]
            case .backupMnemonicsEncrypted:
                throw CocoaError(.fileReadNoPermission)
            }
        }
        let report = WalletRecoveryDiagnostics.makeReport(
            accounts: [account("7-ton-mainnet", recoveryRequired: true)],
            isLegacyMigrationAllowed: false,
            enclaveSecretAccountIds: nil,
            legacySourceAccountIds: sources
        )
        let row = try #require(report.accounts.first)

        #expect(row.enclaveSecret == .unavailable)
        #expect(row.legacySources.map(\.key) == [
            "accounts", "mnemonicsEncrypted", "backup_accounts", "backup_mnemonicsEncrypted",
        ])
        #expect(row.legacySources.map(\.ciphertext) == [.missing, .missing, .present, .unavailable])

        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        for output in [json, report.exportText] {
            #expect(output.contains("7-ton-mainnet"))
            #expect(!output.contains("retained-ciphertext"))
            #expect(!output.contains("different-account-ciphertext"))
            #expect(!output.contains("private-account-title"))
        }
    }

    private func account(
        _ id: String,
        type: AccountType = .mnemonic,
        recoveryRequired: Bool = false
    ) -> MAccount {
        MAccount(
            id: id,
            title: "private-account-title",
            type: type,
            byChain: [.ton: .init(address: "address")],
            secretState: recoveryRequired ? .recoveryRequired : nil
        )
    }
}
