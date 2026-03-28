
import Foundation
import GRDB
import WalletContext

private let log = Log("switchFromCapacitor")

@MainActor
public func switchStorageToCapacitor(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let accountIds = try await moveAccounts(global: global, db: db)
    let currentAccountId = resolveCurrentAccountId(accountIds: accountIds)
    ensureBootCriticalGlobalState(
        global: global,
        accountIds: accountIds,
        currentAccountId: currentAccountId
    )
    moveOrderedAccountIds(global: global)
    moveBaseCurrency(global: global)
    LocalizationSupport.shared.syncLanguageToGlobalStorage(global: global)
    try await moveSettings(global: global, db: db, currentAccountId: currentAccountId)
    try await moveSavedAddresses(global: global, db: db)
    try await moveDomains(global: global, db: db)
    try await moveAssetsAndActivityData(global: global, db: db)
    try await moveAccountSettings(global: global, db: db)
    setHasOpenedAir(global: global)
    try await finalizeSwitch(global: global, db: db)
}

@MainActor
private func moveAccounts(global: GlobalStorage, db: any DatabaseWriter) async throws -> [String] {
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
    return Array(accountsById.keys)
}

@MainActor
private func ensureBootCriticalGlobalState(
    global: GlobalStorage,
    accountIds: [String],
    currentAccountId: String?
) {
    global.update {
        $0["stateVersion"] = STATE_VERSION
        if $0["byAccountId"] == nil {
            $0["byAccountId"] = [:]
        }
        if $0["settings.byAccountId"] == nil {
            $0["settings.byAccountId"] = [:]
        }
        for accountId in accountIds {
            if $0["byAccountId.\(accountId)"] == nil {
                $0["byAccountId.\(accountId)"] = [:]
            }
            if $0["settings.byAccountId.\(accountId)"] == nil {
                $0["settings.byAccountId.\(accountId)"] = [:]
            }
        }
        $0["currentAccountId"] = currentAccountId
    }
}

@MainActor
private func resolveCurrentAccountId(accountIds: [String]) -> String? {
    let accountIdSet = Set(accountIds)
    if let currentAccountId = AccountStore.accountId {
        if accountIdSet.contains(currentAccountId) {
            return currentAccountId
        }
        log.fault("current account is missing from exported accounts currentAccountId=\(currentAccountId, .public)")
    }
    if let fallbackAccountId = AccountStore.orderedAccountIds.first(where: { accountIdSet.contains($0) }) {
        log.fault("falling back to ordered account for capacitor export currentAccountId=\(fallbackAccountId, .public)")
        return fallbackAccountId
    }
    return accountIds.sorted().first
}

@MainActor
private func moveBaseCurrency(global: GlobalStorage) {
    global.update {
        $0[AppStorageHelper.selectedCurrencyKey] = AppStorageHelper.selectedCurrency()
    }
}

@MainActor
private func moveOrderedAccountIds(global: GlobalStorage) {
    global.update {
        $0["settings.orderedAccountIds"] = Array(AccountStore.orderedAccountIds)
    }
}

@MainActor
private func moveSettings(
    global: GlobalStorage,
    db: any DatabaseWriter,
    currentAccountId: String?
) async throws {
    let row = try await db.read { db in
        try MSettings.fetchOne(db, key: SINGLETON_TABLE_ROW_ID)
    } ?? .init()
    let sharedCurrentTokenPeriod = row.currentTokenPeriod
    let accountIds = AccountStore.accountsById.keys
    let isTestnet = currentAccountId.map { getNetwork(accountId: $0) == .testnet } ?? false
    let accountsSupportAppLock = AuthSupport.accountsSupportAppLock

    global.update {
        $0["settings.theme"] = row.theme
        $0["settings.animationLevel"] = row.globalAnimationLevel
        $0["settings.isSeasonalThemingDisabled"] = row.isSeasonalThemingDisabled
        $0["settings.canPlaySounds"] = row.canPlaySounds
        $0["settings.areTinyTransfersHidden"] = row.areTinyTransfersHidden
        $0["settings.areTokensWithNoCostHidden"] = row.areTokensWithNoCostHidden
        $0["settings.authConfig"] = row.authConfigObject
        $0["settings.isTestnet"] = isTestnet
        $0["settings.isAppLockEnabled"] = accountsSupportAppLock
        $0["settings.autolockValue"] = row.autolockValue
        $0["settings.isSensitiveDataHidden"] = row.isSensitiveDataHidden
        $0["settings.selectedExplorerIds"] = row.selectedExplorerIds
        $0["settings.isTokenChartExpanded"] = row.isTokenChartExpanded
        $0["pushNotifications"] = row.pushNotificationsObject
    }

    // Air keeps one token period for all accounts; export it per-account for web compatibility.
    for accountId in accountIds {
        global.update {
            $0["byAccountId.\(accountId).currentTokenPeriod"] = sharedCurrentTokenPeriod
        }
    }
}

@MainActor
private func moveSavedAddresses(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let accountIds = AccountStore.accountsById.keys
    let rows = try await db.read { db in
        try MAccountSavedAddresses.fetchAll(db)
    }
    let rowsByAccountId = rows.dictionaryByKey(\.accountId)

    for accountId in accountIds {
        let addresses = rowsByAccountId[accountId]?.addresses ?? []
        global.update {
            $0["byAccountId.\(accountId).savedAddresses"] = try? JSONSerialization.encode(addresses)
        }
    }
}

@MainActor
private func moveDomains(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let accountIds = AccountStore.accountsById.keys
    let rows = try await db.read { db in
        try MAccountDomains.fetchAll(db)
    }
    let rowsByAccountId = rows.dictionaryByKey(\.accountId)

    for accountId in accountIds {
        let row = rowsByAccountId[accountId]
        let prefix = "byAccountId.\(accountId).nfts"
        global.update {
            $0["\(prefix).dnsExpiration"] = try? JSONSerialization.encode(row?.expirationByAddress ?? [:] as [String: Int])
            $0["\(prefix).linkedAddressByAddress"] = try? JSONSerialization.encode(row?.linkedAddressByAddress ?? [:] as [String: String])
            $0["\(prefix).byAddress"] = try? JSONSerialization.encode(row?.nftsByAddress ?? [:] as [String: ApiNft])
            $0["\(prefix).orderedAddresses"] = row?.orderedAddresses ?? []
        }
    }
}

@MainActor
private func moveAssetsAndActivityData(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let accountsById = AccountStore.accountsById
    let rows = try await db.read { db in
        try MAccountAssetsAndActivityData.fetchAll(db)
    }
    let rowsByAccountId = rows.dictionaryByKey(\.accountId)

    for accountId in accountsById.keys {
        let row = rowsByAccountId[accountId]
        let prefix = "settings.byAccountId.\(accountId)"
        global.update {
            $0["\(prefix).alwaysHiddenSlugs"] = row?.alwaysHiddenSlugs ?? []
            $0["\(prefix).importedSlugs"] = row?.importedSlugs ?? []
            $0["\(prefix).pinnedSlugs"] = row?.pinnedSlugs
        }
    }
}

@MainActor
private func moveAccountSettings(global: GlobalStorage, db: any DatabaseWriter) async throws {
    let accountsById = AccountStore.accountsById
    let rows = try await db.read { db in
        try MAccountSettings.fetchAll(db)
    }
    let rowsByAccountId = rows.dictionaryByKey(\.accountId)

    for accountId in accountsById.keys {
        let row = rowsByAccountId[accountId]
        let prefix = "settings.byAccountId.\(accountId)"
        global.update {
            if let cardBackgroundNft = row?.cardBackgroundNft {
                $0["\(prefix).cardBackgroundNft"] = try? JSONSerialization.encode(cardBackgroundNft)
            } else {
                $0["\(prefix).cardBackgroundNft"] = nil
            }
            if let accentColorNft = row?.accentColorNft {
                $0["\(prefix).accentColorNft"] = try? JSONSerialization.encode(accentColorNft)
            } else {
                $0["\(prefix).accentColorNft"] = nil
            }
            $0["\(prefix).accentColorIndex"] = row?.accentColorIndex
            $0["\(prefix).isAllowSuspiciousActions"] = row?.isAllowSuspiciousActions
        }
    }
}

@MainActor
private func setHasOpenedAir(global: GlobalStorage) {
    global.update {
        $0["settings.hasOpenedAir"] = true
    }
}

@MainActor
private func finalizeSwitch(global: GlobalStorage, db: any DatabaseWriter) async throws {
    try await global.syncronize()
    try await db.write { db in
        try db.execute(sql: "UPDATE common SET switched_from_capacitor_dt = NULL")
    }
}
