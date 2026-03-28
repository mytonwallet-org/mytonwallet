import Foundation
import GRDB
import WalletContext

private let log = Log("migrateLegacyStorage")
public let legacyStorageMigrationId = "legacy_storage_from_global_v2"

@MainActor
public func migrateLegacyStorageIfNeeded(global: GlobalStorage, db: any DatabaseWriter) async {
    do {
        let alreadyExecuted = try await db.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT 1 FROM one_time_migrations WHERE id = ? LIMIT 1",
                arguments: [legacyStorageMigrationId]
            ) != nil
        }
        guard !alreadyExecuted else { return }

        StartupTrace.mark("airLauncher.legacyStorageMigration.begin")

        var failedStepDetails: [String] = []

        if let failureDetails = await runLegacyStorageMigrationStep(
            "accountSettings",
            failureTrace: "airLauncher.accountSettingsMigration.failed",
            operation: {
                try await migrateLegacyAccountSettings(global: global, db: db)
                StartupTrace.mark("airLauncher.accountSettingsMigration.end")
            }
        ) {
            failedStepDetails.append(failureDetails)
        }

        if let failureDetails = await runLegacyStorageMigrationStep(
            "settings",
            failureTrace: "airLauncher.settingsMigration.failed",
            operation: {
                try await migrateLegacySettings(global: global, db: db)
                StartupTrace.mark("airLauncher.settingsMigration.end")
            }
        ) {
            failedStepDetails.append(failureDetails)
        }

        if let failureDetails = await runLegacyStorageMigrationStep(
            "orderedAccountIds",
            failureTrace: "airLauncher.orderedAccountIdsMigration.failed",
            operation: {
                try await migrateLegacyOrderedAccountIds(global: global, db: db)
                StartupTrace.mark("airLauncher.orderedAccountIdsMigration.end")
            }
        ) {
            failedStepDetails.append(failureDetails)
        }

        if let failureDetails = await runLegacyStorageMigrationStep(
            "savedAddresses",
            failureTrace: "airLauncher.savedAddressesMigration.failed",
            operation: {
                try await migrateLegacySavedAddresses(global: global, db: db)
                StartupTrace.mark("airLauncher.savedAddressesMigration.end")
            }
        ) {
            failedStepDetails.append(failureDetails)
        }

        if let failureDetails = await runLegacyStorageMigrationStep(
            "domains",
            failureTrace: "airLauncher.domainsMigration.failed",
            operation: {
                try await migrateLegacyDomains(global: global, db: db)
                StartupTrace.mark("airLauncher.domainsMigration.end")
            }
        ) {
            failedStepDetails.append(failureDetails)
        }

        guard failedStepDetails.isEmpty else {
            let failureSummary = failedStepDetails.joined(separator: " | ")
            log.fault("legacy storage migration incomplete failures=\(failureSummary, .public)")
            StartupTrace.mark("airLauncher.legacyStorageMigration.failed", details: failureSummary)
            return
        }

        try await db.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO one_time_migrations (id, executedAt)
                VALUES (?, CURRENT_TIMESTAMP)
                """,
                arguments: [legacyStorageMigrationId]
            )
        }
        StartupTrace.mark("airLauncher.legacyStorageMigration.end")
    } catch {
        log.fault("legacy storage migration failed error=\(String(reflecting: error), .public)")
        StartupTrace.mark("airLauncher.legacyStorageMigration.failed", details: String(reflecting: error))
    }
}

@MainActor
private func runLegacyStorageMigrationStep(
    _ step: String,
    failureTrace: String,
    operation: () async throws -> Void
) async -> String? {
    do {
        try await operation()
        return nil
    } catch {
        let failureDetails = "step=\(step) error=\(String(reflecting: error))"
        log.fault("legacy storage migration step failed \(failureDetails, .public)")
        StartupTrace.mark(failureTrace, details: failureDetails)
        return failureDetails
    }
}

@MainActor
private func migrateLegacySettings(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let legacyRow = MSettings(global: global, currentAccountId: global["currentAccountId"] as? String)
    try await db.write { db in
        let defaultRow = MSettings()
        var row = try MSettings.fetchOne(db, key: SINGLETON_TABLE_ROW_ID) ?? defaultRow
        mergeLegacySettings(into: &row, legacyRow: legacyRow, defaultRow: defaultRow)
        try row.upsert(db)
    }
    log.info("migrated legacy settings currentTokenPeriod=\(legacyRow.currentTokenPeriod, .public)")
}

private func mergeLegacySettings(into row: inout MSettings, legacyRow: MSettings, defaultRow: MSettings) {
    if row.theme == defaultRow.theme {
        row.theme = legacyRow.theme
    }
    if row.areAnimationsDisabled == defaultRow.areAnimationsDisabled {
        row.areAnimationsDisabled = legacyRow.areAnimationsDisabled
    }
    if row.isSeasonalThemingDisabled == defaultRow.isSeasonalThemingDisabled {
        row.isSeasonalThemingDisabled = legacyRow.isSeasonalThemingDisabled
    }
    if row.canPlaySounds == defaultRow.canPlaySounds {
        row.canPlaySounds = legacyRow.canPlaySounds
    }
    if row.areTinyTransfersHidden == defaultRow.areTinyTransfersHidden {
        row.areTinyTransfersHidden = legacyRow.areTinyTransfersHidden
    }
    if row.areTokensWithNoCostHidden == defaultRow.areTokensWithNoCostHidden {
        row.areTokensWithNoCostHidden = legacyRow.areTokensWithNoCostHidden
    }
    if row.authConfig == defaultRow.authConfig {
        row.authConfig = legacyRow.authConfig
    }
    if row.autolockValue == defaultRow.autolockValue {
        row.autolockValue = legacyRow.autolockValue
    }
    if row.isSensitiveDataHidden == defaultRow.isSensitiveDataHidden {
        row.isSensitiveDataHidden = legacyRow.isSensitiveDataHidden
    }
    if row.selectedExplorerIds == defaultRow.selectedExplorerIds {
        row.selectedExplorerIds = legacyRow.selectedExplorerIds
    }
    if row.isTokenChartExpanded == defaultRow.isTokenChartExpanded {
        row.isTokenChartExpanded = legacyRow.isTokenChartExpanded
    }
    if row.pushNotifications == defaultRow.pushNotifications {
        row.pushNotifications = legacyRow.pushNotifications
    }
    if row.currentTokenPeriod == defaultRow.currentTokenPeriod {
        row.currentTokenPeriod = legacyRow.currentTokenPeriod
    }
}

@MainActor
private func migrateLegacyOrderedAccountIds(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let rowExists = try await db.read { db in
        try MOrderedAccountIds.fetchOne(db, key: SINGLETON_TABLE_ROW_ID) != nil
    }
    let accountIds = Set(try await db.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM accounts")
    })
    let stored = (global["settings.orderedAccountIds"] as? [String] ?? [])
        .filter { accountIds.contains($0) }

    try await db.write { db in
        if !rowExists, !stored.isEmpty {
            try MOrderedAccountIds(orderedAccountIds: stored).upsert(db)
        }
    }
    log.info("migrated legacy ordered account ids count=\(stored.count, .public)")
}

@MainActor
private func migrateLegacySavedAddresses(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let existingAccountIds = Set(try await db.read { db in
        try String.fetchAll(db, sql: "SELECT accountId FROM account_saved_addresses")
    })
    let accountIds = try await db.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM accounts")
    }

    var rows: [MAccountSavedAddresses] = []
    for accountId in accountIds where !existingAccountIds.contains(accountId) {
        guard
            let value = global["byAccountId.\(accountId).savedAddresses"],
            let addresses = try? JSONSerialization.decode([SavedAddress].self, from: value)
        else {
            continue
        }
        let row = MAccountSavedAddresses(accountId: accountId, addresses: addresses)
        if row.hasData {
            rows.append(row)
        }
    }

    let rowsToPersist = rows
    try await db.write { db in
        for row in rowsToPersist {
            try row.upsert(db)
        }
    }
    log.info("migrated legacy saved addresses count=\(rows.count, .public)")
}

@MainActor
private func migrateLegacyDomains(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let existingAccountIds = Set(try await db.read { db in
        try String.fetchAll(db, sql: "SELECT accountId FROM account_domains")
    })
    let accountIds = try await db.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM accounts")
    }

    var rows: [MAccountDomains] = []
    for accountId in accountIds where !existingAccountIds.contains(accountId) {
        let prefix = "byAccountId.\(accountId).nfts"
        let row = MAccountDomains(
            accountId: accountId,
            expirationByAddress: global[prefix + ".dnsExpiration"]
                .flatMap { try? JSONSerialization.decode([String: Int].self, from: $0) } ?? [:],
            linkedAddressByAddress: global[prefix + ".linkedAddressByAddress"]
                .flatMap { try? JSONSerialization.decode([String: String].self, from: $0) } ?? [:],
            nftsByAddress: global[prefix + ".byAddress"]
                .flatMap { try? JSONSerialization.decode([String: ApiNft].self, from: $0) } ?? [:],
            orderedAddresses: global[prefix + ".orderedAddresses"]
                .flatMap { try? JSONSerialization.decode([String].self, from: $0) } ?? []
        )
        if row.hasData {
            rows.append(row)
        }
    }

    let rowsToPersist = rows
    try await db.write { db in
        for row in rowsToPersist {
            try row.upsert(db)
        }
    }
    log.info("migrated legacy domains count=\(rows.count, .public)")
}

@MainActor
private func migrateLegacyAccountSettings(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let accountIds = try await db.read { db in
        try String.fetchAll(db, sql: "SELECT id FROM accounts")
    }

    var rowsToUpsert: [MAccountSettings] = []
    if !accountIds.isEmpty {
        let existingAccountIds = try await db.read { db in
            try String.fetchAll(db, sql: "SELECT accountId FROM account_settings")
        }
        let missingAccountIds = Set(accountIds).subtracting(existingAccountIds)

        for accountId in missingAccountIds {
            guard let dict = global.getDict(key: "settings.byAccountId.\(accountId)") else { continue }
            let row = MAccountSettings(accountId: accountId, settingsDict: dict)
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
    }

    log.info("migrated legacy account settings rows count=\(rowsToPersist.count, .public)")
}
