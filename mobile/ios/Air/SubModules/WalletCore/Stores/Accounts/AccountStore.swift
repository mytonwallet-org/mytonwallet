//
//  AccountStore.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/30/24.
//

import Foundation
import WalletContext
import UIKit
import Kingfisher
import OrderedCollections
import GRDB
import Dependencies
import Perception

private let log = Log("AccountStore")

public var AccountStore: _AccountStore { _AccountStore.shared }

@Perceptible
public final class _AccountStore: @unchecked Sendable, WalletCoreData.EventsObserver {

    public static let shared = _AccountStore()

    private init() {}

    private var _accountsById: UnfairLock<[String: MAccount]> = .init(initialState: [:])
    private let _accountId: UnfairLock<String?> = .init(initialState: nil)
    private let _walletVersionsData: UnfairLock<MWalletVersionsData?> = .init(initialState: nil)
    private let _updatingActivities: UnfairLock<Bool> = .init(initialState: false)
    private let _updatingBalance: UnfairLock<Bool> = .init(initialState: false)
    private let _orderedAccountIds: UnfairLock<OrderedSet<String>> = .init(initialState: [])
    
    public var activeNetwork: ApiNetwork {
        if let account {
            return account.id.contains("mainnet") ? .mainnet  : .testnet
        }
        return .mainnet
    }

    public private(set) var accountsById: [String: MAccount] {
        get {
            access(keyPath: \._accountsById)
            return _accountsById.withLock { $0 }
        }
        set {
            withMutation(keyPath: \._accountsById) {
                _accountsById.withLock { $0 = newValue }
            }
        }
    }

    public var account: MAccount? {
        if let accountId {
            return accountsById[accountId]
        }
        return nil
    }

    public private(set) var accountId: String? {
        get { _accountId.withLock { $0 } }
        set {
            withMutation(keyPath: \._accountId) {
                _accountId.withLock { $0 = newValue }
            }
        }
    }

    public internal(set) var walletVersionsData: MWalletVersionsData? {
        get { _walletVersionsData.withLock { $0 } }
        set { _walletVersionsData.withLock { $0 = newValue } }
    }
    
    // MARK: Observable
    
    public var currentAccountId: String {
        access(keyPath: \._accountId)
        return accountId ?? DUMMY_ACCOUNT.id
    }
    
    /// Excludes temporary view accounts
    public private(set) var orderedAccountIds: OrderedSet<String> {
        get {
            access(keyPath: \._orderedAccountIds)
            return _orderedAccountIds.withLock { $0 }
        }
        set {
            withMutation(keyPath: \._orderedAccountIds) {
                _orderedAccountIds.withLock { $0 = newValue }
            }
        }
    }
    
    public var orderedAccountIdsWithTemporary: OrderedSet<String> {
        orderedAccountIds.union(accountsById.keys)
    }
        
    /// Excludes temporary view accounts
    public var orderedAccounts: [MAccount] {
        access(keyPath: \._accountsById)
        let accountsById = accountsById
        return orderedAccountIds.compactMap { accountsById[$0] }
    }
    
    public func get(accountId: String) -> MAccount {
        access(keyPath: \._accountsById)
        return accountsById[accountId] ?? DUMMY_ACCOUNT
    }
    
    private func getCurrentAccount() -> MAccount {
        get(accountId: currentAccountId)
    }
    
    public func get(accountIdOrCurrent: String?) -> MAccount {
        get(accountId: accountIdOrCurrent ?? currentAccountId)
    }

    // MARK: - Database

    private var _db: (any DatabaseWriter)?
    private var db: any DatabaseWriter {
        get throws {
            try _db.orThrow("database not ready")
        }
    }

    private var currentAccountIdObservation: Task<Void, Never>?
    private var accountsObservation: Task<Void, Never>?

    func use(db: any DatabaseWriter) {
        loadOrderedAccountIds()
        
        self._db = db

        do {
            let currentAccountId = try! db.read { db in
                try String.fetchOne(db, sql: "SELECT current_account_id FROM common")
            }
            updateFromDb(currentAccountId: currentAccountId)

            let observation = ValueObservation.tracking { db in
                try String.fetchOne(db, sql: "SELECT current_account_id FROM common")
            }
            currentAccountIdObservation = Task { [weak self] in
                do {
                    for try await accountId in observation.values(in: db) {
                        try Task.checkCancellation()
                        self?.updateFromDb(currentAccountId: accountId)
                    }
                } catch {
                    log.error("\(error)")
                }
            }
        }

        do {
            let accounts = try! db.read { db in
                try MAccount.fetchAll(db)
            }
            updateFromDb(accounts: accounts)

            let observation = ValueObservation.tracking { db in
                try MAccount.fetchAll(db)
            }
            accountsObservation = Task { [weak self] in
                do {
                    for try await accounts in observation.values(in: db) {
                        try Task.checkCancellation()
                        self?.updateFromDb(accounts: accounts)
                    }
                } catch {
                    log.error("\(error)")
                }
            }
        }
        
        WalletCoreData.add(eventObserver: self)
    }

    private func updateFromDb(currentAccountId: String?) {
        self.accountId = currentAccountId
    }

    private func updateFromDb(accounts: [MAccount]) {
        var accountsById: [String: MAccount] = [:]
        for account in accounts {
            accountsById[account.id] = account
        }
        let accountIds = accountsById.compactMap { $1.isTemporaryView ? nil : $0 }
        self.accountsById = accountsById

        let orderedAccountIds = orderedAccountIds.intersection(accountIds).union(accountIds)
        if orderedAccountIds != self.orderedAccountIds {
            self.orderedAccountIds = orderedAccountIds
            saveOrderedAccountIds()
        }
    }
    
    // MARK: - Current account

    @discardableResult
    public func activateAccount(accountId: String, isNew: Bool = false, updateCurrentAccountId: Bool = true) async throws -> MAccount {
        displayLog("activateAccount \(accountId)")
        let timestamps = await ActivityStore.getNewestActivityTimestamps(accountId: accountId)
        if timestamps?.nilIfEmpty == nil {
            Log.api.info("No newestTransactionsBySlug for \(accountId, .public), loading will be slow")
        }
        try await Api.activateAccount(accountId: accountId, newestActivityTimestamps: timestamps)

        guard let account = AccountStore.accountsById[accountId] else {
            throw BridgeCallError.unknown()
        }

        if updateCurrentAccountId {
            self.accountId = accountId
            try await db.write { db in
                try db.execute(sql: "UPDATE common SET current_account_id = ?", arguments: [accountId])
            }
            
            Task.detached {
                WalletCoreData.notifyAccountChanged(to: account, isNew: isNew)
            }
        }
        
        return account
    }
    
    public func reactivateCurrentAccount() async throws {
        if let accountId = self.accountId {
            let timestamps = await ActivityStore.getNewestActivityTimestamps(accountId: accountId)
            log.info("reactivateCurrentAccount: \(accountId, .public) timestamps#=\(timestamps?.count as Any, .public)")
            try await Api.activateAccount(accountId: accountId, newestActivityTimestamps: timestamps)
        }
    }
    
    public func resolveAccountId(source: AccountSource) -> String {
        switch source {
        case .accountId(let accountId):
            accountId
        case .current:
            self.currentAccountId
        case .constant(let account):
            account.id
        }
    }

    // MARK: - Account management

    public func importMnemonic(network: ApiNetwork, words: [String], passcode: String, version: ApiTonWalletVersion?) async throws -> MAccount {
        let result = try await Api.importMnemonic(networks: [network], mnemonic: words, password: passcode, version: version).first.orThrow()
        let account = MAccount(
            id: result.accountId,
            title: _defaultTitle(),
            type: .mnemonic,
            byChain: result.byChain,
        )
        try await _storeAccount(account: account)
        _ = try await self.activateAccount(accountId: result.accountId, isNew: true)
        await subscribeNotificationsIfAvailable(account: account)
        return account
    }
    
    public func importPrivateKey(network: ApiNetwork, privateKey: String, passcode: String) async throws -> MAccount {
        let result = try await Api.importPrivateKey(chain: .ton, networks: [network], privateKey: privateKey, password: passcode).first.orThrow()
        let account = MAccount(
            id: result.accountId,
            title: _defaultTitle(),
            type: .mnemonic,
            byChain: result.byChain,
        )
        try await _storeAccount(account: account)
        _ = try await self.activateAccount(accountId: result.accountId, isNew: true)
        await subscribeNotificationsIfAvailable(account: account)
        return account
    }

    public func importLedgerAccount(accountInfo: ApiLedgerAccountInfo) async throws -> String {
        let result = try await Api.importLedgerAccount(network: .mainnet, accountInfo: accountInfo)
        let index = accountInfo.byChain[TON_CHAIN]?.index ?? 0
        let title = "Ledger \(index + 1)"
        let account = MAccount(
            id: result.accountId,
            title: title,
            type: .hardware,
            byChain: result.byChain,
        )
        try await _storeAccount(account: account)
        await subscribeNotificationsIfAvailable(account: account)
        return result.accountId
    }

    public func importNewWalletVersion(accountId: String, version: ApiTonWalletVersion) async throws -> MAccount {

        let originalAccount = try accountsById[accountId].orThrow("Can't find the original account")

        let result = try await Api.importNewWalletVersion(accountId: accountId, version: version)

        if result.isNew {
            
            var title = originalAccount.title?.nilIfEmpty ?? _defaultTitle()
            title += " \(version.rawValue)"
            
            let account = try MAccount(
                id: result.accountId,
                title: title,
                type: originalAccount.type,
                byChain: [
                    ApiChain.ton.rawValue: AccountChain(
                        address: result.address.orThrow("Address missing for new wallet version"),
                    ),
                ],
            )
            
            try await _storeAccount(account: account)
            _ = try await self.activateAccount(accountId: result.accountId, isNew: true)
            await subscribeNotificationsIfAvailable(account: account)
            return account
            
        } else {
            let account = try await self.activateAccount(accountId: result.accountId)
            return account
        }
    }

    public func importViewWallet(network: ApiNetwork, addressByChain: [String: String]) async throws -> MAccount {
        if addressByChain.isEmpty { throw DisplayError(text: "No matching chains") }

        let result = try await Api.importViewAccount(network: network, addressByChain: addressByChain, isTemporary: nil)
        let viewCount = AccountStore.accountsById.values.filter { $0.type == .view }.count
        let account = MAccount(
            id: result.accountId,
            title: result.title ?? "\(lang("Wallet")) \(viewCount + 1)",
            type: .view,
            byChain: result.byChain,
        )

        try await _storeAccount(account: account)
        _ = try await self.activateAccount(accountId: result.accountId, isNew: true)
        await subscribeNotificationsIfAvailable(account: account)
        return account
    }

    private func _defaultTitle() -> String {
        let totalCount = AccountStore.accountsById.count
        if totalCount == 0 {
            return APP_NAME
        }
        let mnemonicCount = AccountStore.accountsById.values.filter { $0.type == .mnemonic }.count
        return "\(lang("My Wallet")) \(mnemonicCount + 1)"
    }

    private func _storeAccount(account: MAccount) async throws {
        try await db.write { db in
            try account.upsert(db)
        }
    }

    public func updateAccountTitle(accountId: String, newTitle: String?) async throws {
        if var account = accountsById[accountId] {
            account.title = newTitle?.nilIfEmpty
            accountsById[accountId] = account
            try await _storeAccount(account: account)
            WalletCoreData.notify(event: .accountNameChanged)
            if notificationsEnabledAccountIds.contains(accountId) {
                await _subscribeNotifications(account: account, force: true)
            }
        }
    }
    
    // MARK: - Temporary wallets
    
    public func importTemporaryViewAccountOrActivateFirstMatching(network: ApiNetwork, addressOrDomainByChain: [String: String]) async throws -> MAccount {
        if let account = firstAccountContainingChainAddresses(addressOrDomainByChain) {
            try await activateAccount(accountId: account.id, updateCurrentAccountId: false)
            return account
        } else {
            return try await importTemporaryViewAccount(network: network, addressOrDomainByChain: addressOrDomainByChain)
        }
    }
    
    private func importTemporaryViewAccount(network: ApiNetwork, addressOrDomainByChain: [String: String]) async throws -> MAccount {
        let result = try await Api.importViewAccount(network: network, addressByChain: addressOrDomainByChain, isTemporary: true)
        let account = MAccount(
            id: result.accountId,
            title: result.title ?? lang("Wallet"),
            type: .view,
            byChain: result.byChain,
            isTemporary: true,
        )
        accountsById[account.id] = account
        try await _storeAccount(account: account)
        return account
    }

    public func saveTemporaryViewAccount(accountId: String) async throws {
        if var account = accountsById[accountId] {
            account.isTemporary = nil
            var nameChanged = false
            if account.title == lang("Wallet") {
                let viewCount = AccountStore.accountsById.values.filter { $0.type == .view }.count
                account.title = "\(lang("Wallet")) \(viewCount + 1)"
                nameChanged = true
            }
            try await _storeAccount(account: account)
            accountsById[accountId] = account
            _ = try await self.activateAccount(accountId: accountId, isNew: false)
            await subscribeNotificationsIfAvailable(account: account)
            if nameChanged {
                WalletCoreData.notify(event: .accountNameChanged)
            }
        }
    }
    
    private func firstAccountContainingChainAddresses(_ addressOrDomainByChain: [String: String]) -> MAccount? {
        accountLoop: for account in orderedAccounts {
            for (chain, addressOrDomain) in addressOrDomainByChain {
                if account.byChain[chain]?.address != addressOrDomain && account.byChain[chain]?.domain != addressOrDomain {
                    continue accountLoop
                }
            }
            return account
        }
        return nil
    }
    
    public func removeAccountIfTemporary(accountId: String) async throws {
        let account = get(accountId: accountId)
        if account.isTemporaryView {
            try await AccountStore.removeAccount(accountId: accountId, nextAccountId: self.currentAccountId)
        }
    }
    
    public func removeAllTemporaryAccounts() async throws {
        for account in accountsById.values {
            if account.isTemporaryView {
                try await AccountStore.removeAccount(accountId: account.id, nextAccountId: self.currentAccountId)
            }
        }
    }

    // MARK: - Remove methods

    @MainActor
    public func resetAccounts() async throws {
        log.info("resetAccounts")
        try await Api.resetAccounts()
        self.accountId = nil
        self.accountsById = [:]
        try await db.write { db in
            _ = try MAccount.deleteAll(db)
        }

        try await GlobalStorage.deleteAll()
        GlobalStorage.update {
            $0["stateVersion"] = STATE_VERSION
        }
        try await GlobalStorage.syncronize()

        await ActivityStore.clean()
        BalanceStore.clean()
        NftStore.clean()
        AccountStore.clean()
        // TODO: Remove all capacitor storage data!
        DispatchQueue.main.async {
            Api.shared?.webViewBridge.recreateWebView()
        }
        AppStorageHelper.deleteAllWallets()
        KeychainHelper.deleteAllWallets()
        WalletCoreData.notify(event: .accountsReset)
    }

    @discardableResult
    public func removeAccount(accountId: String, nextAccountId: String) async throws -> MAccount {
        if let account = accountsById[accountId] {
            await _unsubscribeNotifications(account: account)
        }
        let timestamps = await ActivityStore.getNewestActivityTimestamps(accountId: nextAccountId)
        try await Api.removeAccount(accountId: accountId, nextAccountId: nextAccountId, newestActivityTimestamps: timestamps)
        AppStorageHelper.remove(accountId: accountId)
        try await db.write { db in
            _ = try MAccount.deleteOne(db, key: accountId)
        }
        WalletCoreData.notify(event: .accountDeleted(accountId: accountId))
        if let currentAccount = self.account, currentAccount.id == nextAccountId, self.accountId == nextAccountId {
            return currentAccount
        } else {
            return try await activateAccount(accountId: nextAccountId)
        }
    }
    
    // MARK: - Reordering accounts
    
    public func reorderAccounts(changes: CollectionDifference<String>) {
        withMutation(keyPath: \._orderedAccountIds) {
            _orderedAccountIds.withLock {
                $0 = $0.applying(changes)!
            }
        }
        saveOrderedAccountIds()
    }
    
    private func loadOrderedAccountIds() {
        if let stored = GlobalStorage["settings.orderedAccountIds"] as? [String] {
            orderedAccountIds = OrderedSet(stored)
        }
    }
    
    private func saveOrderedAccountIds() {
        GlobalStorage.update { $0["settings.orderedAccountIds"] = Array(orderedAccountIds) }
        Task { try? await GlobalStorage.syncronize() }
    }
    
    // MARK: - Domains
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .updateAccount(let update):
            Task {
                await handleUpdateAccount(update: update)
            }
        default:
            break
        }
    }
    
    func handleUpdateAccount(update: ApiUpdate.UpdateAccount) async {
        guard var account = accountsById[update.accountId] else {
            return
        }

        let chain = update.chain.rawValue
        var didChange = false

        if let address = update.address {
            if account.byChain[chain] == nil {
                account.byChain[chain] = AccountChain(address: address)
                didChange = true
            } else if account.byChain[chain]?.address != address {
                account.byChain[chain]?.address = address
                didChange = true
            }
        }

        switch update.domain {
        case .unchanged:
            break
        case .changed(let domain):
            if account.byChain[chain]?.domain != domain {
                account.byChain[chain]?.domain = domain
                didChange = true
            }
        case .removed:
            if account.byChain[chain]?.domain != nil {
                account.byChain[chain]?.domain = nil
                didChange = true
            }
        }
        if let isMultisig = update.isMultisig {
            if account.byChain[chain]?.isMultisig != isMultisig {
                account.byChain[chain]?.isMultisig = isMultisig
                didChange = true
            }
        }

        if didChange {
            try? await _storeAccount(account: account)
        }
    }


    // MARK: - Notifications

    public var notificationsEnabledAccountIds: Set<String> {
        Set(AppStorageHelper.pushNotifications?.enabledAccounts ?? [])
    }
    
    public func didRegisterForPushNotifications(userToken: String) {
        let existingInfo = AppStorageHelper.pushNotifications
        let previousToken = existingInfo?.userToken

        let info = GlobalPushNotifications(
            isAvailable: true,
            userToken: userToken,
            platform: .ios,
            enabledAccounts: existingInfo?.enabledAccounts ?? []
        )
        AppStorageHelper.pushNotifications = info

        let enabledAccounts = info.enabledAccounts
        guard !enabledAccounts.isEmpty else { return }

        let accounts = info.enabledAccounts.compactMap { accountsById[$0] }
        let addresses = accounts.flatMap { notificationAddresses(for: $0) }
        guard !addresses.isEmpty else { return }

        Task {
            do {
                let subscribeProps = ApiSubscribeNotificationsProps(
                    userToken: userToken,
                    platform: .ios,
                    langCode: LocalizationSupport.shared.langCode,
                    addresses: addresses
                )

                if let previousToken, previousToken != userToken {
                    async let subscribeResult = Api.subscribeNotifications(props: subscribeProps)
                    async let _ = Api.unsubscribeNotifications(props: ApiUnsubscribeNotificationsProps(
                        userToken: previousToken,
                        addresses: addresses
                    ))
                    let result = try await subscribeResult
                    updateEnabledNotificationAccounts(info: info, accounts: accounts, result: result)
                } else {
                    let result = try await Api.subscribeNotifications(props: subscribeProps)
                    updateEnabledNotificationAccounts(info: info, accounts: accounts, result: result)
                }
            } catch {
                log.info("didRegisterForPushNotifications: \(error, .public)")
            }
        }
    }
    
    public func refreshEnabledNotificationSubscriptions() {
        guard let info = AppStorageHelper.pushNotifications,
              let userToken = info.userToken else {
            return
        }
        let accounts = info.enabledAccounts.compactMap { accountsById[$0] }
        let addresses = accounts.flatMap { notificationAddresses(for: $0) }
        guard !addresses.isEmpty else { return }

        Task {
            do {
                let result = try await Api.subscribeNotifications(props: ApiSubscribeNotificationsProps(
                    userToken: userToken,
                    platform: .ios,
                    langCode: LocalizationSupport.shared.langCode,
                    addresses: addresses
                ))
                updateEnabledNotificationAccounts(info: info, accounts: accounts, result: result)
            } catch {
                log.info("refreshEnabledNotificationSubscriptions: \(error, .public)")
            }
        }
    }
    
    private func subscribeNotificationsIfAvailable(account: MAccount) async {
        if let info = AppStorageHelper.pushNotifications, info.enabledAccounts.count < MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT {
            await _subscribeNotifications(account: account)
        }
    }
    
    @MainActor public func selectedNotificationsAccounts(accounts: [MAccount]) async {
        do {
            let toEnableAccountIds = Set(accounts.map(\.id))
            let oldEnabledAccountIds = Set(AppStorageHelper.pushNotifications?.enabledAccounts ?? [])
            if oldEnabledAccountIds == toEnableAccountIds {
                return
            }
            let toUnsubscribeAccounts = oldEnabledAccountIds
                .filter { !toEnableAccountIds.contains($0) }
                .compactMap { accountsById[$0] }
            for account in toUnsubscribeAccounts {
                await _unsubscribeNotifications(account: account)
            }
            for account in accounts {
                await _subscribeNotifications(account: account)
            }
            try await GlobalStorage.syncronize()
        } catch {
            log.info("selectedNotificationsAccounts: \(error)")
        }
    }

    private func _subscribeNotifications(account: MAccount, force: Bool = false) async {
        do {
            if var info = AppStorageHelper.pushNotifications,
                let userToken = info.userToken
            {
                if info.enabledAccounts.contains(account.id), !force {
                    return
                }
                let addresses = notificationAddresses(for: account)
                guard !addresses.isEmpty else {
                    log.info("_subscribeNotifications: no supported addresses")
                    return
                }
                let result = try await Api.subscribeNotifications(props: ApiSubscribeNotificationsProps(
                    userToken: userToken,
                    platform: .ios,
                    langCode: LocalizationSupport.shared.langCode,
                    addresses: addresses
                ))
                let enabledAddresses = Set(result.addressKeys.keys)
                if addresses.contains(where: { enabledAddresses.contains($0.address) }) {
                    if !info.enabledAccounts.contains(account.id) {
                        info.enabledAccounts.append(account.id)
                    }
                } else {
                    info.enabledAccounts.removeAll { $0 == account.id }
                }
                AppStorageHelper.pushNotifications = info
            } else {
                log.info("_subscribeNotifications: no info or token")
            }
        } catch {
            log.info("_subscribeNotifications: \(error)")
        }
    }

    private func _unsubscribeNotifications(account: MAccount) async {
        do {
            if var info = AppStorageHelper.pushNotifications,
                let userToken = info.userToken
            {
                let addresses = notificationAddresses(for: account)
                if !addresses.isEmpty {
                    _ = try await Api.unsubscribeNotifications(props: ApiUnsubscribeNotificationsProps(
                        userToken: userToken,
                        addresses: addresses
                    ))
                }
                info.enabledAccounts.removeAll { $0 == account.id }
                AppStorageHelper.pushNotifications = info
            } else {
                log.info("_unsubscribeNotifications: no info or userToken")
            }
        } catch {
            log.info("\(error)")
        }
    }
    
    private func notificationAddresses(for account: MAccount) -> [ApiNotificationAddress] {
        account.orderedChains.compactMap { chain, info in
            if chain.doesSupportPushNotifications {
                return ApiNotificationAddress(
                    title: account.displayName,
                    address: info.address,
                    chain: chain
                )
            }
            return nil
        }
    }

    private func updateEnabledNotificationAccounts(
        info: GlobalPushNotifications,
        accounts: [MAccount],
        result: ApiSubscribeNotificationsResult
    ) {
        let enabledAddresses = Set(result.addressKeys.keys)
        let enabledAccountIds = accounts
            .filter { account in
                notificationAddresses(for: account)
                    .contains { enabledAddresses.contains($0.address) }
            }
            .map(\.id)
        var updatedInfo = info
        updatedInfo.enabledAccounts = enabledAccountIds
        AppStorageHelper.pushNotifications = updatedInfo
    }

    // MARK: - AssetsAndActivityData

    private let _assetsAndActivityData = UnfairLock<ValueFetchingState<[String: MAssetsAndActivityData]>>(initialState: .notSet)
    
    public var currentAccountAssetsAndActivityData: MAssetsAndActivityData? {
        guard let accountID = AccountStore.accountId else { return nil }
        return assetsAndActivityData(forAccountID: accountID)
    }
    
    /// [AccountID: MAssetsAndActivityData]
    public func assetsAndActivityData(forAccountID accountID: String) -> MAssetsAndActivityData? {
        _assetsAndActivityData.withLock { dataState in
            switch dataState {
            case .notSet: nil
            case .data(let assetsSettingsDict): assetsSettingsDict[accountID]
            }
        }
    }
    
    /// Without this state it is impossible to understand whether the data has not yet been loaded or MAssetsAndActivityData is nil because nothing has been write.
    /// Was added as a workaround to prevent data being erased in BalanceStore. In BalanceStore when `recalculateAccountData()` called,
    /// MAssetsAndActivityData is not loaded yet. It is needed some time after `recalculateAccountData()` called for MAssetsAndActivityData to be parsed and set.
    /// This is an artifact of current data layer implementation, which is needed to be addressed.
    ///
    /// Account data loading and recalculateAccountData() happens in non-deterministic order.  notifyAccountChanged event, which initiate MAssetsAndActivityData
    /// loading from persistent storage, happens after ~650ms after recalculateAccountData(). Then after ~200ms MAssetsAndActivityData is finally parsed and set.
    public var isAssetsAndActivityDataLoaded: Bool {
        _assetsAndActivityData.withLock { dataState in
            switch dataState {
            case .notSet: false
            case .data: true
            }
        }
    }
    
    /// For setting data from bridge
    public func setAssetsAndActivityData(_ settings: MAssetsAndActivityData, forAccountID accountID: String) {
        let hasChanged = _assetsAndActivityData.withLock { dataState in
            switch dataState {
            case .notSet:
                dataState = .data([accountID: settings])
                return true

            case .data(var settingsDict):
                let isChanged = Self.update_AccountsAssetsAndActivityDict(&settingsDict,
                                                                          withSettings: settings,
                                                                          forAccountID: accountID)
                if isChanged { dataState = .data(settingsDict) }
                return isChanged
            }
        }

        guard hasChanged else { return }

        AppStorageHelper.save(accountId: accountID, assetsAndActivityData: settings.toDictionary)
        WalletCoreData.notify(event: .assetsAndActivityDataUpdated)
    }

    /// For changing settings from UI
    public func updateAssetsAndActivityData(forAccountID accountID: String,
                                            update: (inout MAssetsAndActivityData) -> Void) {
        let updatedSettings: MAssetsAndActivityData? = _assetsAndActivityData.withLock { dataState in
            switch dataState {
            case .notSet:
                // this branch signals about incorrect usage / races.
                let message = "Trying to update data that is not set yet. "
                  + " Check `isAssetsAndActivityDataLoaded` state first to prevent data erasing on concurrent access"
                Log.shared.fault(LogMessage(stringLiteral: message))
                assertionFailure(message)
                return nil
                
            case .data(var settingsDict):
                // there can still be a race in this branch too. The existence of settingsDict only guarantees that settings
                // for one account have already been set. Settings for other accounts may still being loaded.
                // This solves situation with recalculateAccountData() in BalanceStore, but still brittle.
                var accountAssetsSettings = settingsDict[accountID] ?? .empty
                update(&accountAssetsSettings)
                
                let isChanged = Self.update_AccountsAssetsAndActivityDict(&settingsDict,
                                                                          withSettings: accountAssetsSettings,
                                                                          forAccountID: accountID)
                if isChanged {
                    dataState = .data(settingsDict)
                    return accountAssetsSettings
                } else {
                    return nil
                }
            }
        }

        guard let updatedSettings else { return }

        // Improvement: potential race with AppStorageHelper.save and reading data
        AppStorageHelper.save(accountId: accountID, assetsAndActivityData: updatedSettings.toDictionary)
        WalletCoreData.notify(event: .assetsAndActivityDataUpdated)
    }
    
    private static func update_AccountsAssetsAndActivityDict(_ settingsDict: inout [String: MAssetsAndActivityData],
                                                             withSettings accountAssetsSettings: MAssetsAndActivityData,
                                                             forAccountID accountID: String) -> Bool {
        let dataWasChanged: Bool
        if settingsDict[accountID] != accountAssetsSettings {
            settingsDict[accountID] = accountAssetsSettings
            dataWasChanged = true
        } else {
            dataWasChanged = false
        }
        return dataWasChanged
    }

    // MARK: - Misc
    
    public internal(set) var updatingActivities: Bool {
        get { _updatingActivities.withLock { $0 } }
        set { _updatingActivities.withLock { $0 = newValue } }
    }

    public internal(set) var updatingBalance: Bool {
        get { _updatingBalance.withLock { $0 } }
        set { _updatingBalance.withLock { $0 = newValue } }
    }

    public func clean() {
        self.walletVersionsData = nil
        self.updatingActivities = false
        self.updatingBalance = false
    }
}

extension _AccountStore: DependencyKey {
    static public var liveValue: _AccountStore = .shared
    static public var previewValue: _AccountStore = {
        let accountStore = _AccountStore()
        accountStore.accountsById = [
            MAccount(
                id: "0-mainnet",
                title: "MyTonWallet",
                type: .mnemonic,
                byChain: [
                    .ton: AccountChain(address: "UQf7abcd1234efgh5678ijkl9012mnop34Aef3dsdaQ8N", domain: nil),
                    .tron: AccountChain(address: "TUQf7abcd1234efgh5678ijkl9012mnop34ef3dsdaPqh", domain: nil),
                ]
            ),
            MAccount(
                id: "1-mainnet",
                title: "Personal Wallet",
                type: .mnemonic,
                byChain: [
                    .ton: AccountChain(address: "UQf7abcd1234efgh5678ijkl9012mnop34ef3dsdaQ8N", domain: "tema.ton"),
                    .tron: AccountChain(address: "TUQf7abcd1234efgh5678ijkl9012mnop34ef3dsdacC9", domain: "screamingseagull.tron"),
                ]
            ),
            MAccount(
                id: "2-mainnet",
                title: "My Saved",
                type: .view,
                byChain: [
                    .ton: AccountChain(address: "UQf7abcd1234efgh5678ijkl9012mnop3456qrst7890d0Gh", domain: nil),
                ]
            ),
            MAccount(
                id: "3-testnet",
                title: "Just for Test",
                type: .view,
                byChain: [
                    .ton: AccountChain(address: "UQdk9876zyxw5432vuts2109rqpo8765nmlk4321jihg7654z7-d", domain: nil),
                ]
            ),
            MAccount(
                id: "4-mainnet",
                title: "Yet Another Walleeeeeeeeeeeeeeeeeeet",
                type: .mnemonic,
                byChain: [
                    .ton: AccountChain(address: "UQ2c1234abcd5678efgh9012ijkl3456mnop7890qrst2345Kd9A", domain: nil),
                ]
            ),
            MAccount(
                id: "5-mainnet",
                title: "Family Wallet",
                type: .hardware,
                byChain: [
                    .ton: AccountChain(address: "EQ9876abcd5432efgh2109ijkl8765mnop4321qrst7890klmn9-d", domain: nil),
                    .tron: AccountChain(address: "T9876543210abcdefghijklmnopqrstuvwxyz01234567890Va", domain: nil),
                ]
            ),
            MAccount(
                id: "6-mainnet",
                title: "Durov's Wallet",
                type: .view,
                byChain: [
                    .ton: AccountChain(address: "EQabcdef1234567890ghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP", domain: "wolf.t.me"),
                ]
            ),
            MAccount(
                id: "7-mainnet",
                title: "Old Wallet",
                type: .mnemonic,
                byChain: [
                    .ton: AccountChain(address: "EQ1234abcd5678efgh9012ijkl3456mnop7890qrst2345uvwxwQ9", domain: nil),
                    .tron: AccountChain(address: "Tabcdef1234567890ghijklmnopqrstuvwxyzABCDEFGHIJKLMN0cH", domain: nil),
                ]
            ),
            MAccount(
                id: "8-mainnet",
                title: "Super Secret",
                type: .mnemonic,
                byChain: [
                    .ton: AccountChain(address: "UQc81234abcd5678efgh9012ijkl3456mnop7890qrst2345uvwxc4Zs", domain: nil),
                ]
            ),
            
        ].dictionaryByKey(\.id)
        accountStore.accountId = "0-mainnet"
        accountStore.orderedAccountIds = OrderedSet(accountStore.accountsById.keys.sorted())
        return accountStore
    }()
}

extension DependencyValues {
    public var accountStore: _AccountStore {
        get { self[_AccountStore.self] }
        set { self[_AccountStore.self] = newValue }
    }
}

public enum ValueFetchingState<T> {
    case notSet
    case data(T)
}
