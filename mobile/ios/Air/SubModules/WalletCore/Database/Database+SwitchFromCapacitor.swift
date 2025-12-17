
import Foundation
import GRDB
import WalletContext

private let log = Log("switchFromCapacitor")

/// - Note: This method assumes web app storage is migrated to the latest version
public func switchStorageFromCapacitorIfNeeded(global: _GlobalStorage, db: any DatabaseWriter) async throws {
    let date = try! await db.read { db in
        try Date.fetchOne(db, sql: "SELECT switched_from_capacitor_dt FROM common")
    }
    guard date == nil else {
        log.info("switchFromCapacitorIfNeeded: not needed date=\(date!, .public)")
        return
    }
    try await moveAccounts(global: global, db: db)
    try await moveCurrentAccountId(global: global, db: db)
    try await finalizeSwitch(db: db)
}

private func moveAccounts(global: _GlobalStorage, db: any DatabaseWriter) async throws {
    let accountIds = global.keysIn(key: "accounts.byId") ?? []
    
    var accounts: [MAccount] = []
    
    struct _AccountWithoutId: Codable {
        var title: String?
        var type: AccountType
        var byChain: [String: AccountChain]
        var isTemporary: Bool?
    }

    for accountId in accountIds {
        
        guard let dict = global["accounts.byId.\(accountId)"] as? [String: Any] else {
            log.fault("failed to decode account! global=\(global as Any, .public)")
            throw GlobalStorageError.localStorageIsInvalidJson(global)
        }
        let _account = try JSONSerialization.decode(_AccountWithoutId.self, from: dict)
        if _account.isTemporary == true {
            continue
        }
        let account = MAccount(
            id: accountId,
            title: _account.title,
            type: _account.type,
            byChain: _account.byChain,
        )
        accounts.append(account)
    }
    try await db.write { [accounts] db in
        try db.execute(sql: "DELETE FROM accounts")
        for account in accounts {
            try account.insert(db)
        }
    }
}

private func moveCurrentAccountId(global: _GlobalStorage, db: any DatabaseWriter) async throws {
    let accountId = global["currentAccountId"] as? String
    try await db.write { db in
        try db.execute(sql: "UPDATE common SET current_account_id = ?", arguments: [accountId])
    }
}

private func finalizeSwitch(db: any DatabaseWriter) async throws {
    try await db.write { db in
        try db.execute(sql: "UPDATE common SET switched_from_capacitor_dt = CURRENT_TIMESTAMP")
    }
}
