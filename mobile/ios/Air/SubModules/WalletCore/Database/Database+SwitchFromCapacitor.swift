
import Foundation
import GRDB
import WalletContext

private let log = Log("switchFromCapacitor")

/// - Note: This method assumes web app storage is migrated to the latest version
@MainActor
public func switchStorageFromCapacitorIfNeeded(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let date = try await db.read { db in
        try Date.fetchOne(db, sql: "SELECT switched_from_capacitor_dt FROM common")
    }
    guard date == nil else {
        log.info("switchFromCapacitorIfNeeded: not needed date=\(date!, .public)")
        return
    }
    let accountIds = try await moveAccounts(global: global, db: db)
    await runNonEssentialSwitchFromCapacitorStep("orderedAccountIds", failureTrace: "airLauncher.storage.switchFromCapacitor.orderedAccountIds.failed") {
        try await moveOrderedAccountIds(global: global, db: db, accountIds: accountIds)
    }
    await runNonEssentialSwitchFromCapacitorStep("currentAccountId", failureTrace: "airLauncher.storage.switchFromCapacitor.currentAccountId.failed") {
        try await moveCurrentAccountId(global: global, db: db)
    }
    moveBaseCurrency(global: global)
    LocalizationSupport.shared.syncLanguageFromGlobalStorage(global: global)
    await runNonEssentialSwitchFromCapacitorStep("settings", failureTrace: "airLauncher.storage.switchFromCapacitor.settings.failed") {
        try await moveSettings(global: global, db: db)
    }
    await runNonEssentialSwitchFromCapacitorStep("savedAddresses", failureTrace: "airLauncher.storage.switchFromCapacitor.savedAddresses.failed") {
        try await moveSavedAddresses(global: global, db: db, accountIds: accountIds)
    }
    await runNonEssentialSwitchFromCapacitorStep("domains", failureTrace: "airLauncher.storage.switchFromCapacitor.domains.failed") {
        try await moveDomains(global: global, db: db, accountIds: accountIds)
    }
    await runNonEssentialSwitchFromCapacitorStep("assetsAndActivityData", failureTrace: "airLauncher.storage.switchFromCapacitor.assetsAndActivityData.failed") {
        try await moveAssetsAndActivityData(global: global, db: db, accountIds: accountIds)
    }
    await runNonEssentialSwitchFromCapacitorStep("accountSettings", failureTrace: "airLauncher.storage.switchFromCapacitor.accountSettings.failed") {
        try await moveAccountSettings(global: global, db: db, accountIds: accountIds)
    }
    try await finalizeSwitch(db: db)
}

@MainActor
private func moveAccounts(global: GlobalStorage, db: any DatabaseWriter) async throws -> [String] {
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
    return accounts.map(\.id)
}

@MainActor
private func moveCurrentAccountId(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let accountId = global["currentAccountId"] as? String
    try await db.write { db in
        try db.execute(sql: "UPDATE common SET current_account_id = ?", arguments: [accountId])
    }
}

@MainActor
private func moveBaseCurrency(global: GlobalStorage) {
    AppStorageHelper.save(selectedCurrency: global.getString(key: AppStorageHelper.selectedCurrencyKey))
}

@MainActor
private func moveOrderedAccountIds(global: GlobalStorage, db: any DatabaseWriter, accountIds: [String]) async throws {
    let accountIdSet = Set(accountIds)
    let orderedAccountIds = (global["settings.orderedAccountIds"] as? [String] ?? [])
        .filter { accountIdSet.contains($0) }
    guard !orderedAccountIds.isEmpty else { return }
    let row = MOrderedAccountIds(orderedAccountIds: orderedAccountIds)
    try await db.write { db in
        try row.upsert(db)
    }
}

@MainActor
private func moveSettings(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let row = MSettings(global: global, currentAccountId: global["currentAccountId"] as? String)
    try await db.write { db in
        try row.upsert(db)
    }
}

@MainActor
private func moveSavedAddresses(global: GlobalStorage, db: any DatabaseWriter, accountIds: [String]) async throws {
    var rows: [MAccountSavedAddresses] = []
    for accountId in accountIds {
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
    guard !rows.isEmpty else { return }
    let rowsToPersist = rows
    try await db.write { db in
        for row in rowsToPersist {
            try row.upsert(db)
        }
    }
}

@MainActor
private func moveDomains(global: GlobalStorage, db: any DatabaseWriter, accountIds: [String]) async throws {
    var rows: [MAccountDomains] = []
    for accountId in accountIds {
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
    guard !rows.isEmpty else { return }
    let rowsToPersist = rows
    try await db.write { db in
        for row in rowsToPersist {
            try row.upsert(db)
        }
    }
}

@MainActor
private func moveAssetsAndActivityData(global: GlobalStorage, db: any DatabaseWriter, accountIds: [String]) async throws {
    var rows: [MAccountAssetsAndActivityData] = []
    for accountId in accountIds {
        guard let dict = global.getDict(key: "settings.byAccountId.\(accountId)") else { continue }
        let data = MAssetsAndActivityData(dictionary: dict)
        let row = MAccountAssetsAndActivityData(accountId: accountId, data: data, didAutoPinStaking: false)
        if row.hasData {
            rows.append(row)
        }
    }
    guard !rows.isEmpty else { return }
    let rowsToPersist = rows
    try await db.write { db in
        for row in rowsToPersist {
            try row.upsert(db)
        }
    }
}

@MainActor
private func moveAccountSettings(global: GlobalStorage, db: any DatabaseWriter, accountIds: [String]) async throws {
    var rows: [MAccountSettings] = []
    for accountId in accountIds {
        guard let dict = global.getDict(key: "settings.byAccountId.\(accountId)") else { continue }
        let row = MAccountSettings(accountId: accountId, settingsDict: dict)
        if row.hasData {
            rows.append(row)
        }
    }
    guard !rows.isEmpty else { return }
    let rowsToPersist = rows
    try await db.write { db in
        for row in rowsToPersist {
            try row.upsert(db)
        }
    }
}

private func finalizeSwitch(db: any DatabaseWriter) async throws {
    try await db.write { db in
        try db.execute(sql: "UPDATE common SET switched_from_capacitor_dt = CURRENT_TIMESTAMP")
    }
}

@MainActor
private func runNonEssentialSwitchFromCapacitorStep(
    _ step: String,
    failureTrace: String,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
    } catch {
        let failureDetails = "step=\(step) error=\(String(reflecting: error))"
        log.fault("switchStorageFromCapacitor non-essential step failed \(failureDetails, .public)")
        StartupTrace.mark(failureTrace, details: failureDetails)
    }
}
