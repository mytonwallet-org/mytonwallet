
import Foundation
import GRDB

func makeMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
    #endif
    migrator.registerMigration("v1") { db in
        try db.create(table: "accounts") { t in
            t.primaryKey("id", .text)
            t.column("type", .text).notNull()
            t.column("title", .text)
            t.column("addressByChain", .jsonText)
            t.column("ledger", .jsonText)
        }
        try db.create(table: "common") { t in
            t.primaryKey("id", .integer)
            t.column("switched_from_capacitor_dt", .datetime)
            t.column("current_account_id", .text)
                .references("accounts", column: "id", onDelete: .setNull)
        }
        try db.execute(sql: "INSERT INTO common (id) VALUES (0)")
    }
    migrator.registerMigration("v2") { db in
        try db.create(table: "asset_tabs") { t in
            t.primaryKey("account_id", .text)
                .references("accounts", column: "id", onDelete: .cascade)
            t.column("tabs", .jsonText)
            t.column("auto_telegram_gifts_hidden", .boolean)
        }
    }
    migrator.registerMigration("v3") { db in
        try db.create(table: "staking_info") { t in
            t.primaryKey("id", .integer)
            t.column("common_data", .jsonText)
        }
        try db.execute(sql: "INSERT INTO staking_info (id) VALUES (0)")
        try db.create(table: "account_staking") { t in
            t.primaryKey("accountId", .text)
                .references("accounts", column: "id", onDelete: .cascade)
            t.column("stateById", .jsonText)
            t.column("totalProfit", .jsonText)
            t.column("shouldUseNominators", .jsonText)
        }
    }
    migrator.registerMigration("v4") { db in
        try db.drop(table: "staking_info")
        try db.create(table: "account_activities") { t in
            t.primaryKey("accountId", .text)
                .references("accounts", column: "id", onDelete: .cascade)
            t.column("byId", .jsonText)
            t.column("idsMain", .jsonText)
            t.column("idsBySlug", .jsonText)
            t.column("newestActivitiesBySlug", .jsonText)
            t.column("isInitialLoadedByChain", .jsonText)
            t.column("localActivities", .jsonText)
            t.column("isHistoryEndReachedBySlug", .jsonText)
            t.column("isMainHistoryEndReached", .boolean)
        }
    }
    migrator.registerMigration("v5") { db in
        try db.execute(sql: "DELETE FROM account_activities")
        try db.alter(table: "account_activities") { t in
            t.drop(column: "localActivities")
            t.add(column: "localActivityIds", .jsonText)
            t.add(column: "pendingActivityIds", .jsonText)
        }
    }
    migrator.registerMigration("v6") { db in
        
        struct Old_MAccount: Codable, FetchableRecord, PersistableRecord {
            let id: String
            var type: String
            var title: String?
            var addressByChain: [String: String]
            var ledger: _Ledger?
            static var databaseTableName: String = "accounts"
        }
        struct New_MAccount: Codable, FetchableRecord, PersistableRecord {
            public let id: String
            public var title: String?
            public var type: String
            public var byChain: [String: _AccountChain]
            public var ledger: _Ledger?
            static var databaseTableName: String = "accounts"
        }
        struct _Ledger: Codable {
            var index: Int
            var driver: String
            var deviceId: String?
            var deviceName: String?
        }
        struct _AccountChain: Codable {
            var address: String
            var domain: String?
            var isMultisig: Bool?
        }
        
        let oldAccounts = try Old_MAccount.fetchAll(db)
        let newAccounts = oldAccounts.map { oldAccount in
            New_MAccount(
                id: oldAccount.id,
                title: oldAccount.title,
                type: oldAccount.type,
                byChain: Dictionary(uniqueKeysWithValues: oldAccount.addressByChain.map { chain, address in
                    (chain, _AccountChain(address: address))
                }),
                ledger: oldAccount.ledger
            )
        }
        try db.alter(table: "accounts") { t in
            t.drop(column: "addressByChain")
            t.add(column: "byChain", .jsonText).defaults(to: "{}").notNull()
        }
        for newAccount in newAccounts {
            try newAccount.update(db)
        }
    }
    migrator.registerMigration("v7") { db in
        // old
        struct Old_Account: Codable, FetchableRecord, PersistableRecord {
            let id: String
            var title: String?
            var type: String
            var byChain: [String: _AccountChain]
            var ledger: Old_Ledger?
            static var databaseTableName: String = "accounts"
        }
        struct Old_Ledger: Codable {
            var index: Int
            var driver: String?
            var deviceId: String?
            var deviceName: String?
        }
        // new
        struct New_Account: Codable, FetchableRecord, PersistableRecord {
            let id: String
            var title: String?
            var type: String
            var byChain: [String: _AccountChain]
            static var databaseTableName: String = "accounts"
        }
        // common
        struct _AccountChain: Codable {
            var address: String
            var domain: String?
            var isMultisig: Bool?
            var ledgerIndex: Int? // will always be nil before migration
        }
        let oldAccounts = try Old_Account.fetchAll(db)
        let newAccounts = oldAccounts.map { oldAccount in
            New_Account(
                id: oldAccount.id,
                title: oldAccount.title,
                type: oldAccount.type,
                byChain: Dictionary(uniqueKeysWithValues: oldAccount.byChain.map { chain, oldAccountChain in
                    var newAccountChain = oldAccountChain
                    if oldAccount.type == "hardware" && chain == "ton" && oldAccountChain.ledgerIndex == nil {
                        newAccountChain.ledgerIndex = oldAccount.ledger?.index
                    }
                    return (chain, newAccountChain)
                }),
            )
        }
        try db.alter(table: "accounts") { t in
            t.drop(column: "ledger")
        }
        for newAccount in newAccounts {
            try newAccount.update(db)
        }
    }
    migrator.registerMigration("v8") { db in
        try db.alter(table: "accounts") { t in
            t.add(column: "isTemporary", .boolean)
        }
    }
    return migrator
}
