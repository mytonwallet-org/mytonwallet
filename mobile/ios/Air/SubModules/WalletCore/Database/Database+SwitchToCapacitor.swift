
import Foundation
import GRDB
import WalletContext

private let log = Log("switchFromCapacitor")

public func switchStorageToCapacitor(global: _GlobalStorage, db: any DatabaseWriter) async throws {
    try await moveAccounts(global: global, db: db)
    try await moveCurrentAccountId(global: global, db: db)
    try await finalizeSwitch(global: global, db: db)
}

private func moveAccounts(global: _GlobalStorage, db: any DatabaseWriter) async throws {
    let accountsById = AccountStore.accountsById
    global.update {
        $0["accounts.byId"] = [:]
    }
    for (accountId, account) in accountsById {
        let json = try account.json()
        global.update {
            $0["accounts.byId.\(accountId)"] = json
        }
    }
}

private func moveCurrentAccountId(global: _GlobalStorage, db: any DatabaseWriter) async throws {
    let accountId = AccountStore.accountId
    global.update {
        $0["currentAccountId"] = accountId
    }
}

private func finalizeSwitch(global: _GlobalStorage, db: any DatabaseWriter) async throws {
    try await global.syncronize()
    try await db.write { db in
        try db.execute(sql: "UPDATE common SET switched_from_capacitor_dt = NULL")
    }
}
