import Foundation
import GRDB
import WalletContext

private let log = Log("migrateLegacyAssetsAndActivityData")
public let legacyAssetsAndActivityMigrationId = "legacy_assets_and_activity_data_from_global_v1"

/// One-time migration of legacy GlobalStorage assets/activity settings into DB.
/// Execution is guarded by `one_time_migrations` marker.
@MainActor
public func migrateLegacyAssetsAndActivityDataIfNeeded(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let alreadyExecuted = try await db.read { db in
        try Int.fetchOne(
            db,
            sql: "SELECT 1 FROM one_time_migrations WHERE id = ? LIMIT 1",
            arguments: [legacyAssetsAndActivityMigrationId]
        ) != nil
    }
    guard !alreadyExecuted else { return }

    let accountIds = try await db.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM accounts")
    }

    var rowsToUpsert: [MAccountAssetsAndActivityData] = []
    if !accountIds.isEmpty {
        let existingAccountIds = try await db.read { db in
            try String.fetchAll(db, sql: "SELECT accountId FROM account_assets_and_activity_data")
        }
        let missingAccountIds = Set(accountIds).subtracting(existingAccountIds)

        for accountId in missingAccountIds {
            guard let dict = global.getDict(key: "settings.byAccountId.\(accountId)") else { continue }
            let data = MAssetsAndActivityData(dictionary: dict)
            let row = MAccountAssetsAndActivityData(accountId: accountId, data: data, didAutoPinStaking: false)
            if row.hasData {
                rowsToUpsert.append(row)
            }
        }
    }

    let rowsToPersist = rowsToUpsert

    try await db.write { db in
        for row in rowsToPersist {
            try row.upsert(db)
        }
        try db.execute(
            sql: """
            INSERT OR IGNORE INTO one_time_migrations (id, executedAt)
            VALUES (?, CURRENT_TIMESTAMP)
            """,
            arguments: [legacyAssetsAndActivityMigrationId]
        )
    }

    log.info(
        "migrated legacy assets/activity rows count=\(rowsToPersist.count, .public), marker=\(legacyAssetsAndActivityMigrationId, .public)"
    )
}
