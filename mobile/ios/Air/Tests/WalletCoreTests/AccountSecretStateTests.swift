import GRDB
import Testing
@testable import WalletCore

@Suite("Account Secret State")
struct AccountSecretStateTests {
    @Test
    func `v21 migration defaults existing accounts to no secret state`() throws {
        let db = try DatabaseQueue()
        let migrator = makeMigrator()
        try migrator.migrate(db, upTo: "v20")
        try db.write { db in
            try db.execute(
                sql: """
                INSERT INTO accounts (id, type, title, byChain)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    "legacy-mainnet",
                    AccountType.mnemonic.rawValue,
                    "Legacy",
                    #"{"ton":{"address":"EQ-test"}}"#,
                ]
            )
        }

        try migrator.migrate(db)

        let (account, storedState): (MAccount?, String?) = try db.read { db in
            (
                try MAccount.fetchOne(db, key: "legacy-mainnet"),
                try String.fetchOne(
                    db,
                    sql: "SELECT secretState FROM accounts WHERE id = ?",
                    arguments: ["legacy-mainnet"]
                )
            )
        }
        #expect(account?.secretState == nil)
        #expect(storedState == nil)
    }

    @Test
    func `recovery required state persists`() throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let account = MAccount(
            id: "recovery-mainnet",
            title: "Recovery",
            type: .mnemonic,
            byChain: [.ton: AccountChain(address: "EQ-test")],
            secretState: .recoveryRequired
        )

        try db.write { db in
            try account.insert(db)
        }

        let (reloaded, storedState): (MAccount?, String?) = try db.read { db in
            (
                try MAccount.fetchOne(db, key: account.id),
                try String.fetchOne(
                    db,
                    sql: "SELECT secretState FROM accounts WHERE id = ?",
                    arguments: [account.id]
                )
            )
        }
        #expect(reloaded?.secretState?.isRecoveryRequired == true)
        #expect(storedState == #"{"isRecoveryRequired":true}"#)
    }
}
