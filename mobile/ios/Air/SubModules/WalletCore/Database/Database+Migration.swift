
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
    return migrator
}
