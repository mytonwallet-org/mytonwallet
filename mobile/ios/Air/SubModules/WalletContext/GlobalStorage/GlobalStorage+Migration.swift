import Foundation

public let STATE_VERSION: Int = 59

private let log = Log("GlobalStorage+Migration")
private let mainAccountId = "0-ton-mainnet"

public enum GlobalMigrationError: Error {
    case stateVersionIsNil
}

extension GlobalStorage {
    
    fileprivate var stateVersion: Int? {
        get { self["stateVersion"] as? Int }
        set { update { $0["stateVersion"] = newValue } }
    }
    
    public func migrate() async throws {
        try await migrate(persist: true)
    }

    func migrate(persist: Bool) async throws {
        let initialStateVersion = self.stateVersion
        let initialStateVersionDescription = initialStateVersion.map(String.init) ?? "nil"

        _normalizeLegacySingleAccountStateIfNeeded()

        if (self.stateVersion == nil || self.stateVersion == 0), _hasAccounts() {
            self.stateVersion = 1
        }

        if self.stateVersion == nil {
            throw GlobalMigrationError.stateVersionIsNil
        }

        if let v = self.stateVersion, v > STATE_VERSION {
            log.fault("migration error: stateVersion=\(v) greater than STATE_VERSION=\(STATE_VERSION)")
            return
        }

        let didRepairKnownSchemaGaps = repairKnownSchemaGaps()

        if didRepairKnownSchemaGaps {
            log.info("migration recovery path triggered from stateVersion=\(initialStateVersionDescription, .public)")
        }

        if let v = self.stateVersion, v >= STATE_VERSION {
            if didRepairKnownSchemaGaps {
                log.info("migration finishing after recovery path stateVersion=\(v, .public)")
                if persist {
                    try await syncronize()
                }
                log.info("migration completed")
            }
            return
        }
        
        log.info(
            "migration started from stateVersion=\(initialStateVersionDescription, .public) recoveryPathTriggered=\(didRepairKnownSchemaGaps, .public)"
        )
        log.info("migration started")
        
        if self.stateVersion == 1 {
            _keepOnlyToncoinTokenInfo()
            _clearLegacyTransactions()
            self.stateVersion = 2
        }

        if self.stateVersion == 2 {
            _normalizeMainAccountIdAndAddTestnetAccounts()
            self.stateVersion = 3
        }

        if self.stateVersion == 3 {
            _clearLegacyTransactions()
            self.stateVersion = 4
        }

        if self.stateVersion == 4 {
            update { $0["staking"] = ["state": "none"] }
            self.stateVersion = 5
        }

        if self.stateVersion == 5 {
            _clearLegacyTransactions()
            self.stateVersion = 6
        }

        if self.stateVersion == 6 {
            _clearLegacyTransactions()
            self.stateVersion = 7
        }

        if self.stateVersion == 7 {
            _removeAccountStateField("backupWallet")
            self.stateVersion = 8
        }

        if self.stateVersion == 8 {
            self.stateVersion = 9
        }

        if self.stateVersion == 9 {
            _clearActivities()
            self.stateVersion = 10
        }

        if self.stateVersion == 10 {
            if self["settings.areTokensWithNoBalanceHidden"] == nil {
                update { $0["settings.areTokensWithNoBalanceHidden"] = true }
            }
            self.stateVersion = 11
        }

        if self.stateVersion == 11 {
            _clearActivities()
            self.stateVersion = 12
        }

        if self.stateVersion == 12 {
            _clearActivities()
            self.stateVersion = 13
        }

        if self.stateVersion == 13 {
            let hidesNoPrice = self["settings.areTokensWithNoPriceHidden"] as? Bool == true
            let hidesNoBalance = self["settings.areTokensWithNoBalanceHidden"] as? Bool == true
            update { $0["settings.areTokensWithNoCostHidden"] = hidesNoPrice || hidesNoBalance }
            self.stateVersion = 14
        }

        if let v = self.stateVersion, v >= 14 && v <= 17 {
            _clearActivities()
            self.stateVersion = 18
        }

        if self.stateVersion == 18 || self.stateVersion == 19 {
            _setCurrentTokenPeriodForAllAccounts("1D")
            self.stateVersion = 20
        }

        if let v = self.stateVersion, v >= 20 && v <= 22 {
            _clearActivities()
            self.stateVersion = 23
        }

        if self.stateVersion == 23 {
            self.stateVersion = 24
        }

        if self.stateVersion == 24 {
            _migrateAccountAddressToAddressByChain()
            self.stateVersion = 25
        }

        if self.stateVersion == 25 {
            _migrateSavedAddressesToArray()
            self.stateVersion = 26
        }

        if self.stateVersion == 26 {
            _clearActivities()
            self.stateVersion = 27
        }

        if self.stateVersion == 27 {
            update { $0["settings.dapps"] = nil }
            self.stateVersion = 28
        }

        if self.stateVersion == 28 {
            _migrateTokenVisibilityExceptions()
            self.stateVersion = 29
        }

        if self.stateVersion == 29 {
            update { $0["currentTransfer.tokenSlug"] = "toncoin" }
            self.stateVersion = 30
        }

        if self.stateVersion == 30 {
            _clearActivities()
            self.stateVersion = 31
        }

        if self.stateVersion == 31 {
            if let autolockValue = self["settings.autolockValue"] as? String, autolockValue != "never" {
                update { $0["settings.isAppLockEnabled"] = true }
            }
            self.stateVersion = 32
        }

        if let v = self.stateVersion, v >= 32 && v <= 35 {
            _clearActivities()
            self.stateVersion = 36
        }

        if self.stateVersion == 36 {
            _migrateAccountTypes()
            self.stateVersion = 37
        }

        if self.stateVersion == 37 {
            _migrateTokenQuotes()
            self.stateVersion = 38
        }

        if let v = self.stateVersion, v >= 38 && v <= 44 {
            _clearActivities()
            self.stateVersion = 45
        }

        if self.stateVersion == 45 {
            _migrateAccountsToByChainIfNeeded()
            self.stateVersion = 46
        }

        if self.stateVersion == 46 {
            _migrateLedgerIndexToByChain()
            self.stateVersion = 47
        }

        if self.stateVersion == 47 {
            _migratePushNotificationEnabledAccounts()
            self.stateVersion = 48
        }
        
        if let v = self.stateVersion, v < 50 {
            self.stateVersion = 50
        }

        if self.stateVersion == 50 {
            _clearActivities()
            self.stateVersion = 51
        }

        if self.stateVersion == 51 {
            _migrateStakingPinnedSlugs()
            self.stateVersion = 52
        }

        if self.stateVersion == 52 {
            _migrateNftCollectionTabs()
            self.stateVersion = 53
        }

        if self.stateVersion == 53 {
            if self["settings.langSource"] == nil {
                update { $0["settings.langSource"] = "user" }
            }
            self.stateVersion = 54
        }

        if self.stateVersion == 54 {
            _clearLegacyContentTabIndexes()
            self.stateVersion = 55
        }

        if self.stateVersion == 55 {
            _migrateWalletTokensLimit()
            self.stateVersion = 56
        }

        if self.stateVersion == 56 {
            _migrateOwnedMtwCardAddresses()
            self.stateVersion = 57
        }

        if self.stateVersion == 57 {
            _clearPortfolioNetChange()
            self.stateVersion = 58
        }

        if self.stateVersion == 58 {
            _clearActivities()
            self.stateVersion = 59
        }

        assert(self.stateVersion == STATE_VERSION)
        
        if persist {
            try await syncronize()
        }
        log.info(
            "migration completed from stateVersion=\(initialStateVersionDescription, .public) to stateVersion=\(self.stateVersion ?? -1, .public) recoveryPathTriggered=\(didRepairKnownSchemaGaps, .public)"
        )
        log.info("migration completed")
    }

    private func repairKnownSchemaGaps() -> Bool {
        var didRepair = _migrateAccountsToByChainIfNeeded()
        didRepair = _migrateLedgerIndexToByChain() || didRepair
        return didRepair
    }
    
    private func _hasAccounts() -> Bool {
        !_accountDicts().isEmpty
    }

    private func _dict(_ key: String) -> [String: Any] {
        self[key] as? [String: Any] ?? [:]
    }

    private func _nestedDicts(_ key: String) -> [String: [String: Any]] {
        _dict(key).compactMapValues { $0 as? [String: Any] }
    }

    private func _accountDicts() -> [String: [String: Any]] {
        _nestedDicts("accounts.byId")
    }

    private func _normalizeLegacySingleAccountStateIfNeeded() {
        guard self["byAccountId"] == nil else { return }
        let addressesByAccountId = _dict("addresses.byAccountId")
        guard !addressesByAccountId.isEmpty else { return }
        let address = (addressesByAccountId[mainAccountId] as? String)
            ?? (addressesByAccountId["0"] as? String)
            ?? addressesByAccountId.values.compactMap { $0 as? String }.first
        guard let address else {
            return
        }

        var account: [String: Any] = [
            "address": address,
            "title": "Main Account",
        ]
        if let accountsById = self["accounts.byId"] as? [String: Any],
           let storedAccount = accountsById[mainAccountId] as? [String: Any]
                ?? accountsById["0"] as? [String: Any] {
            account.merge(storedAccount) { _, stored in stored }
        }

        var accountState: [String: Any] = [
            "isBackupRequired": self["isBackupRequired"] as? Bool == true,
        ]
        if let currentTokenSlug = self["currentTokenSlug"] as? String {
            accountState["currentTokenSlug"] = currentTokenSlug
        }
        if let currentTokenPeriod = self["currentTokenPeriod"] as? String {
            accountState["currentTokenPeriod"] = currentTokenPeriod
        }
        if let balances = self["balances.byAccountId.\(mainAccountId)"] ?? self["balances.byAccountId.0"] {
            accountState["balances"] = balances
        }
        if let transactions = self["transactions"] {
            accountState["transactions"] = transactions
        }
        if let nfts = self["nfts"] {
            accountState["nfts"] = nfts
        }
        if let savedAddresses = self["savedAddresses"] {
            accountState["savedAddresses"] = savedAddresses
        }

        update {
            $0["accounts.byId"] = [mainAccountId: account]
            $0["addresses"] = nil
            $0["byAccountId"] = [mainAccountId: accountState]
            $0["balances"] = nil
            $0["transactions"] = nil
            $0["nfts"] = nil
            $0["savedAddresses"] = nil
            $0["backupWallet"] = nil
        }
    }

    private func _keepOnlyToncoinTokenInfo() {
        guard let toncoin = self["tokenInfo.bySlug.toncoin"] else { return }
        update { $0["tokenInfo.bySlug"] = ["toncoin": toncoin] }
    }

    private func _clearLegacyTransactions() {
        _removeAccountStateField("transactions")
    }

    private func _normalizeMainAccountIdAndAddTestnetAccounts() {
        var accounts = _accountDicts()
        guard !accounts.isEmpty else { return }
        var byAccountId = _nestedDicts("byAccountId")
        var currentAccountId = self["currentAccountId"] as? String

        if let oldAccount = accounts.removeValue(forKey: "0") {
            accounts[mainAccountId] = oldAccount
            if let oldState = byAccountId.removeValue(forKey: "0") {
                byAccountId[mainAccountId] = oldState
            }
            if currentAccountId == "0" {
                currentAccountId = mainAccountId
            }
        }

        for (accountId, account) in Array(accounts) {
            let testnetAccountId = _testnetAccountId(for: accountId)
            if accounts[testnetAccountId] == nil {
                accounts[testnetAccountId] = account
            }
            if byAccountId[testnetAccountId] == nil {
                byAccountId[testnetAccountId] = [:]
            }
        }

        update {
            $0["accounts.byId"] = accounts
            $0["byAccountId"] = byAccountId
            $0["currentAccountId"] = currentAccountId
        }
    }

    private func _testnetAccountId(for accountId: String) -> String {
        let parts = accountId.split(separator: "-")
        let id = parts.compactMap { Int($0) }.first ?? 0
        return "\(id)-testnet"
    }

    private func _clearActivities() {
        _removeAccountStateField("activities")
    }

    private func _removeAccountStateField(_ field: String) {
        var byAccountId = _nestedDicts("byAccountId")
        guard !byAccountId.isEmpty else { return }
        for accountId in Array(byAccountId.keys) {
            byAccountId[accountId]?[field] = nil
        }
        update { $0["byAccountId"] = byAccountId }
    }

    private func _setCurrentTokenPeriodForAllAccounts(_ period: String) {
        var byAccountId = _nestedDicts("byAccountId")
        guard !byAccountId.isEmpty else { return }
        for accountId in Array(byAccountId.keys) {
            byAccountId[accountId]?["currentTokenPeriod"] = period
        }
        update { $0["byAccountId"] = byAccountId }
    }

    private func _migrateAccountAddressToAddressByChain() {
        var accounts = _accountDicts()
        guard !accounts.isEmpty else { return }
        for accountId in Array(accounts.keys) {
            guard let address = accounts[accountId]?["address"] as? String else { continue }
            accounts[accountId]?["addressByChain"] = ["ton": address]
            accounts[accountId]?["address"] = nil
        }
        update { $0["accounts.byId"] = accounts }
    }

    private func _migrateSavedAddressesToArray() {
        var byAccountId = _nestedDicts("byAccountId")
        guard !byAccountId.isEmpty else { return }
        for accountId in Array(byAccountId.keys) {
            guard byAccountId[accountId]?["savedAddresses"] as? [Any] == nil,
                  let savedAddresses = byAccountId[accountId]?["savedAddresses"] as? [String: Any]
            else {
                continue
            }
            byAccountId[accountId]?["savedAddresses"] = savedAddresses.compactMap { address, name -> [String: Any]? in
                guard let name = name as? String else { return nil }
                return [
                    "name": name,
                    "address": address,
                    "chain": "ton",
                ]
            }
        }
        update { $0["byAccountId"] = byAccountId }
    }

    private func _migrateTokenVisibilityExceptions() {
        var settingsByAccountId = _nestedDicts("settings.byAccountId")
        guard !settingsByAccountId.isEmpty else { return }
        let hidesNoCost = self["settings.areTokensWithNoCostHidden"] as? Bool == true
        for accountId in Array(settingsByAccountId.keys) {
            guard let exceptionSlugs = settingsByAccountId[accountId]?["exceptionSlugs"] as? [Any] else { continue }
            settingsByAccountId[accountId]?[hidesNoCost ? "alwaysShownSlugs" : "alwaysHiddenSlugs"] = exceptionSlugs
        }
        update { $0["settings.byAccountId"] = settingsByAccountId }
    }

    private func _migrateAccountTypes() {
        var accounts = _accountDicts()
        guard !accounts.isEmpty else { return }
        for accountId in Array(accounts.keys) {
            let isHardware = accounts[accountId]?["isHardware"] as? Bool == true
                || accounts[accountId]?["type"] as? String == "hardware"
            accounts[accountId]?["type"] = isHardware ? "hardware" : "mnemonic"
            accounts[accountId]?["isHardware"] = nil
        }
        update { $0["accounts.byId"] = accounts }
    }

    private func _migrateTokenQuotes() {
        var tokens = _nestedDicts("tokenInfo.bySlug")
        guard !tokens.isEmpty else { return }
        for slug in Array(tokens.keys) {
            var token = tokens[slug] ?? [:]
            if token["price"] == nil {
                token["price"] = 0
            }
            if token["percentChange24h"] == nil {
                token["percentChange24h"] = 0
            }
            if token["priceUsd"] == nil {
                token["priceUsd"] = 0
            }
            if let quote = token["quote"] as? [String: Any] {
                token["price"] = quote["price"] ?? token["price"]
                token["priceUsd"] = quote["priceUsd"] ?? token["priceUsd"]
                token["percentChange24h"] = quote["percentChange24h"] ?? token["percentChange24h"]
                token["quote"] = nil
            }
            tokens[slug] = token
        }
        update { $0["tokenInfo.bySlug"] = tokens }
    }

    @discardableResult
    private func _migrateAccountsToByChainIfNeeded() -> Bool {
        let cached = _accountDicts()
        guard !cached.isEmpty else { return false }

        var accounts = cached
        var migratedAccountIds: [String] = []

        for (accountId, var account) in cached {
            let existingByChain = account["byChain"] as? [String: Any]
            guard existingByChain?.isEmpty != false else { continue }

            let addressByChain: [String: Any]
            if let existing = account["addressByChain"] as? [String: Any] {
                addressByChain = existing
            } else if let address = account["address"] as? String {
                addressByChain = ["ton": address]
            } else {
                continue
            }

            let domainByChain = account["domainByChain"] as? [String: Any]
            let isMultisigByChain = account["isMultisigByChain"] as? [String: Any]

            let byChain = addressByChain.reduce(into: [String: [String: Any]]()) { result, item in
                let (chain, rawAddress) = item
                guard let address = rawAddress as? String else { return }
                var chainData: [String: Any] = ["address": address]
                if let domain = domainByChain?[chain] as? String, !domain.isEmpty {
                    chainData["domain"] = domain
                }
                if isMultisigByChain?[chain] as? Bool == true {
                    chainData["isMultisig"] = true
                }
                result[chain] = chainData
            }
            guard !byChain.isEmpty else { continue }

            account["byChain"] = byChain
            account["address"] = nil
            account["addressByChain"] = nil
            account["domainByChain"] = nil
            account["isMultisigByChain"] = nil
            accounts[accountId] = account
            migratedAccountIds.append(accountId)
        }

        guard !migratedAccountIds.isEmpty else { return false }

        update { $0["accounts.byId"] = accounts }
        log.info("migrated legacy accounts to byChain count=\(migratedAccountIds.count)")
        return true
    }

    @discardableResult
    private func _migrateLedgerIndexToByChain() -> Bool {
        let cached = _accountDicts()
        guard !cached.isEmpty else { return false }
        var accounts = cached
        var migratedCount = 0

        for (accountId, var account) in cached {
            guard account["type"] as? String == "hardware",
                  var byChain = account["byChain"] as? [String: Any],
                  var ton = byChain["ton"] as? [String: Any],
                  ton["ledgerIndex"] == nil,
                  let ledger = account["ledger"] as? [String: Any],
                  let index = _int(ledger["index"])
            else {
                continue
            }

            ton["ledgerIndex"] = index
            byChain["ton"] = ton
            account["byChain"] = byChain
            account["ledger"] = nil
            accounts[accountId] = account
            migratedCount += 1
        }

        guard migratedCount > 0 else { return false }
        update { $0["accounts.byId"] = accounts }
        log.info("migrated legacy ledger indexes count=\(migratedCount)")
        return true
    }

    private func _migratePushNotificationEnabledAccounts() {
        guard var pushNotifications = self["pushNotifications"] as? [String: Any] else { return }
        if let enabledAccounts = pushNotifications["enabledAccounts"] as? [String: Any] {
            pushNotifications["enabledAccounts"] = Array(enabledAccounts.keys)
        }
        update { $0["pushNotifications"] = pushNotifications }
    }

    private func _migrateStakingPinnedSlugs() {
        let byAccountId = _nestedDicts("byAccountId")
        guard !byAccountId.isEmpty else { return }
        var settingsByAccountId = _nestedDicts("settings.byAccountId")

        for (accountId, accountState) in byAccountId {
            guard let staking = accountState["staking"] as? [String: Any],
                  let stateById = staking["stateById"] as? [String: Any]
            else {
                continue
            }

            let stakingSlugs = stateById.values.compactMap { state -> String? in
                guard let state = state as? [String: Any],
                      let tokenSlug = state["tokenSlug"] as? String
                else {
                    return nil
                }
                return "staking-\(tokenSlug)"
            }

            guard !stakingSlugs.isEmpty else { continue }

            var settings = settingsByAccountId[accountId] ?? [:]
            let pinnedSlugs = settings["pinnedSlugs"] as? [String]
                ?? (settings["pinnedSlugs"] as? [Any])?.compactMap { $0 as? String }
                ?? []
            settings["pinnedSlugs"] = _unique(stakingSlugs + pinnedSlugs)
            settingsByAccountId[accountId] = settings
        }

        update { $0["settings.byAccountId"] = settingsByAccountId }
    }

    private func _migrateNftCollectionTabs() {
        var byAccountId = _nestedDicts("byAccountId")
        guard !byAccountId.isEmpty else { return }

        for accountId in Array(byAccountId.keys) {
            guard var nfts = byAccountId[accountId]?["nfts"] as? [String: Any],
                  let collectionTabs = nfts["collectionTabs"] as? [Any]
            else {
                continue
            }

            nfts["collectionTabs"] = collectionTabs.map { tab -> Any in
                guard let address = tab as? String else { return tab }
                return [
                    "address": address,
                    "chain": "ton",
                ]
            }
            byAccountId[accountId]?["nfts"] = nfts
        }

        update { $0["byAccountId"] = byAccountId }
    }

    private func _clearLegacyContentTabIndexes() {
        var byAccountId = _nestedDicts("byAccountId")
        guard !byAccountId.isEmpty else { return }
        for accountId in Array(byAccountId.keys) {
            byAccountId[accountId]?["landscapeActionsActiveTabIndex"] = nil
            byAccountId[accountId]?["activeContentTab"] = nil
        }
        update { $0["byAccountId"] = byAccountId }
    }

    private func _migrateWalletTokensLimit() {
        var settingsByAccountId = _nestedDicts("settings.byAccountId")
        guard !settingsByAccountId.isEmpty else { return }

        for accountId in Array(settingsByAccountId.keys) {
            if settingsByAccountId[accountId]?["overviewCellSize"] == nil,
               let limit = _int(settingsByAccountId[accountId]?["walletTokensLimit"]) {
                settingsByAccountId[accountId]?["overviewCellSize"] = limit <= 7 ? "small" : limit < 30 ? "medium" : "big"
            }
            settingsByAccountId[accountId]?["walletTokensLimit"] = nil
        }

        update { $0["settings.byAccountId"] = settingsByAccountId }
    }

    private func _migrateOwnedMtwCardAddresses() {
        var byAccountId = _nestedDicts("byAccountId")
        guard !byAccountId.isEmpty else { return }

        for accountId in Array(byAccountId.keys) {
            guard var nfts = byAccountId[accountId]?["nfts"] as? [String: Any],
                  nfts["ownedMtwCardAddresses"] != nil
            else {
                continue
            }

            nfts["ownedMwCardAddresses"] = nfts["ownedMtwCardAddresses"]
            nfts["ownedMtwCardAddresses"] = nil
            byAccountId[accountId]?["nfts"] = nfts
        }

        update { $0["byAccountId"] = byAccountId }
    }

    private func _clearPortfolioNetChange() {
        guard var portfolio = self["portfolio"] as? [String: Any] else { return }
        portfolio["netChangeByAccountId"] = nil
        update { $0["portfolio"] = portfolio }
    }

    private func _int(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private func _unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
