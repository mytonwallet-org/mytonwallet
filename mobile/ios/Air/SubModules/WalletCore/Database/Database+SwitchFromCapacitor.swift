
import Foundation
import GRDB
import WalletContext

private let log = Log("switchFromCapacitor")

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
    
    for accountId in accountIds {
        guard let dict = global["accounts.byId.\(accountId)"] as? [String: Any] else {
            log.fault("failed to decode account! global=\(global as Any, .public)")
            assertionFailure()
            continue
        }
        
        let title = dict["title"] as? String
        let type = dict["type"] as? String ?? "mnemonic"
        let addressByChain = dict["addressByChain"] as? [String: String]
        let ledger = try? JSONSerialization.decode(MAccount.Ledger.self, from: dict["ledger"] as Any)
        
        guard let addressByChain, !addressByChain.isEmpty else {
            log.fault("failed to decode account! global=\(dict as Any, .public)")
            assertionFailure("failed to decode account!")
            continue
        }
        
        accounts.append(
            MAccount(
                id: accountId,
                title: title,
                type: AccountType(rawValue: type) ?? .mnemonic,
                addressByChain: addressByChain,
                ledger: ledger
            )
        )
    }
    try await db.write { db in
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
