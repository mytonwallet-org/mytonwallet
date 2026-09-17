import GRDB
import Testing
import WalletContext
@testable import WalletCore

@Suite("Account Store Activation")
struct AccountStoreActivationTests {
    @Test
    func `saved view wallet can activate before database observation arrives`() async throws {
        let db = try makeDatabase()
        let store = _AccountStore(db: db)
        let account = viewAccount(id: "1-mainnet")
        try await db.write { db in
            try account.insert(db)
        }
        #expect(store.accountsById[account.id] == nil)

        let resolved = try await store.accountForActivation(accountId: account.id)

        #expect(resolved == account)
        #expect(store.accountsById[account.id] == account)
        #expect(Array(store.orderedAccountIds) == [account.id])
        #expect(store.orderedAccounts == [account])
        let persistedOrder = try await db.read { db in
            try MOrderedAccountIds.fetchOne(db, key: SINGLETON_TABLE_ROW_ID)?.orderedAccountIds
        }
        #expect(persistedOrder == [account.id])
    }

    @Test
    func `resolving another saved wallet preserves custom order without duplicates`() async throws {
        let db = try makeDatabase()
        let store = _AccountStore(db: db)
        let first = viewAccount(id: "1-mainnet")
        let second = viewAccount(id: "2-mainnet")
        let third = viewAccount(id: "3-mainnet")
        try await db.write { db in
            try first.insert(db)
            try second.insert(db)
            try third.insert(db)
        }

        _ = try await store.accountForActivation(accountId: first.id)
        _ = try await store.accountForActivation(accountId: second.id)
        store.reorderAccounts(newOrderHint: [second.id, first.id])
        _ = try await store.accountForActivation(accountId: third.id)
        _ = try await store.accountForActivation(accountId: second.id)

        #expect(store.accountsById == [first.id: first, second.id: second, third.id: third])
        #expect(store.orderedAccounts == [second, first, third])
        let persistedOrder = try await db.read { db in
            try MOrderedAccountIds.fetchOne(db, key: SINGLETON_TABLE_ROW_ID)?.orderedAccountIds
        }
        #expect(persistedOrder == [second.id, first.id, third.id])
    }

    @Test
    func `temporary view wallet stays outside the saved wallet order`() async throws {
        let db = try makeDatabase()
        let store = _AccountStore(db: db)
        let saved = viewAccount(id: "1-mainnet")
        let temporaryAccount = viewAccount(id: "2-mainnet", isTemporary: true)
        try await db.write { db in
            try saved.insert(db)
            try temporaryAccount.insert(db)
        }
        _ = try await store.accountForActivation(accountId: saved.id)

        let resolved = try await store.accountForActivation(accountId: temporaryAccount.id)

        #expect(resolved == temporaryAccount)
        #expect(store.accountsById[temporaryAccount.id] == temporaryAccount)
        #expect(store.orderedAccounts == [saved])
        let persistedOrder = try await db.read { db in
            try MOrderedAccountIds.fetchOne(db, key: SINGLETON_TABLE_ROW_ID)?.orderedAccountIds
        }
        #expect(persistedOrder == [saved.id])
    }

    @Test
    func `cached wallet activation does not need a database read`() async throws {
        let db = try makeDatabase()
        let store = _AccountStore(db: db)
        let account = viewAccount(id: "1-mainnet")
        try await db.write { db in
            try account.insert(db)
        }
        _ = try await store.accountForActivation(accountId: account.id)
        try db.close()

        let resolved = try await store.accountForActivation(accountId: account.id)

        #expect(resolved == account)
    }

    @Test
    func `unknown wallet still fails activation without changing the store`() async throws {
        let db = try makeDatabase()
        let store = _AccountStore(db: db)

        await #expect(throws: SdkError.self) {
            try await store.activateAccount(accountId: "missing-mainnet")
        }

        #expect(store.accountsById.isEmpty)
        #expect(store.orderedAccountIds.isEmpty)
        #expect(store.accountId == nil)
        let persistedAccountId = try await db.read { db in
            try String.fetchOne(db, sql: "SELECT current_account_id FROM common")
        }
        #expect(persistedAccountId == nil)
    }
}

private func makeDatabase() throws -> DatabaseQueue {
    let db = try DatabaseQueue()
    try makeMigrator().migrate(db)
    return db
}

private func viewAccount(id: String, isTemporary: Bool? = nil) -> MAccount {
    MAccount(
        id: id,
        title: "wolf.t.me",
        type: .view,
        byChain: [.ton: AccountChain(address: "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c")],
        isTemporary: isTemporary
    )
}
