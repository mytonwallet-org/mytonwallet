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

    private var _accountsById: UnfairLock<OrderedDictionary<String, MAccount>> = .init(initialState: [:])
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

    public var allAccounts: [MAccount] {
        Array(accountsById.values)
    }

    public private(set) var accountsById: OrderedDictionary<String, MAccount> {
        get { _accountsById.withLock { $0 } }
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
    
    /// Observable
    public var currentAccountId: String {
        access(keyPath: \._accountId)
        return accountId ?? DUMMY_ACCOUNT.id
    }
    
    /// Observable
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
        
    /// Observable
    public var orderedAccounts: [MAccount] {
        access(keyPath: \._accountsById)
        let accountsById = accountsById
        return orderedAccountIds.compactMap { accountsById[$0] }
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
        var accountsById: OrderedDictionary<String, MAccount> = [:]
        for account in accounts {
            accountsById[account.id] = account
        }
        accountsById.sort { a1, a2 in
            a1.value.id.compare(a2.value.id, options: [.numeric], range: nil, locale: nil) == .orderedAscending
        }
        let accountIds = accountsById.keys
        self.accountsById = accountsById

        let orderedAccountIds = orderedAccountIds.intersection(accountIds).union(accountIds)
        if orderedAccountIds != self.orderedAccountIds {
            self.orderedAccountIds = orderedAccountIds
            saveOrderedAccountIds()
        }
    }
    
    // MARK: - Current account

    public func activateAccount(accountId: String, isNew: Bool = false) async throws -> MAccount {
        let timestamps = await ActivityStore.getNewestActivityTimestamps(accountId: accountId)
        if timestamps?.nilIfEmpty == nil {
            Log.api.info("No newestTransactionsBySlug for \(accountId, .public), loading will be slow")
        }
        try await Api.activateAccount(accountId: accountId, newestActivityTimestamps: timestamps)

        guard let account = AccountStore.accountsById[accountId] else {
            throw BridgeCallError.unknown()
        }

        self.accountId = accountId
        try await db.write { db in
            try db.execute(sql: "UPDATE common SET current_account_id = ?", arguments: [accountId])
        }

        Task.detached {
            WalletCoreData.notifyAccountChanged(to: account, isNew: isNew)
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

    // MARK: - Account management

    public func createWallet(network: ApiNetwork, words: [String], passcode: String, version: ApiTonWalletVersion?) async throws -> MAccount {
        let result = try await Api.createWallet(network: network, mnemonic: words, password: passcode, version: version)
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

    public func importMnemonic(network: ApiNetwork, words: [String], passcode: String, version: ApiTonWalletVersion?) async throws -> MAccount {
        let result = try await Api.importMnemonic(network: network, mnemonic: words, password: passcode, version: version)
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
                        ledgerIndex: result.ledger?.index
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

    public func importViewWallet(network: ApiNetwork, tonAddress: String?, tronAddress: String?) async throws -> MAccount {
        var addressByChain: [String:String] = [:]
        addressByChain[ApiChain.ton.rawValue] = tonAddress?.nilIfEmpty
        addressByChain[ApiChain.tron.rawValue] = tronAddress?.nilIfEmpty
        if addressByChain.isEmpty { throw NilError("At least one address needed") }

        let result = try await Api.importViewAccount(network: network, addressByChain: addressByChain)
        let account = MAccount(
            id: result.accountId,
            title: result.title ?? "View Wallet \(AccountStore.accountsById.count + 1)",
            type: .view,
            byChain: result.byChain,
        )

        try await _storeAccount(account: account)
        _ = try await self.activateAccount(accountId: result.accountId, isNew: true)
        await subscribeNotificationsIfAvailable(account: account)
        return account
    }

    private func _defaultTitle() -> String{
        let accountsCount = AccountStore.accountsById.count + 1
        return accountsCount < 2 ? APP_NAME : "\(lang("Wallet")) \(accountsCount)"
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
            WalletCoreData.notify(event: .accountNameChanged, for: nil)
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
        WalletContextManager.delegate?.restartApp()
    }

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
        switch update.domain {
        case .unchanged:
            break
        case .changed(let domain):
            if var account = accountsById[update.accountId], account.byChain[update.chain.rawValue]?.domain != domain {
                account.byChain[update.chain.rawValue]?.domain = domain
                try? await _storeAccount(account: account)
            }
        case .removed:
            if var account = accountsById[update.accountId], account.byChain[update.chain.rawValue]?.domain != nil {
                account.byChain[update.chain.rawValue]?.domain = nil
                try? await _storeAccount(account: account)
            }
        }
    }


    // MARK: - Notifications

    public var notificationsEnabledAccountIds: Set<String> {
        Set((AppStorageHelper.pushNotifications?.enabledAccounts ?? [:]).keys)
    }
    
    public func didRegisterForPushNotifications(userToken: String) {
        let info = AppStorageHelper.pushNotifications
        if info == nil || info?.userToken != userToken {
            AppStorageHelper.pushNotifications = GlobalPushNotifications(
                isAvailable: true,
                userToken: userToken,
                platform: .ios,
                enabledAccounts: [:]
            )
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
            let oldEnabledAccountIds = Set((AppStorageHelper.pushNotifications?.enabledAccounts ?? [:]).keys)
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

    private func _subscribeNotifications(account: MAccount) async {
        do {
            if var info = AppStorageHelper.pushNotifications,
                let userToken = info.userToken,
                let tonAddress = account.tonAddress
            {
                let result = try await Api.subscribeNotifications(props: ApiSubscribeNotificationsProps(
                    userToken: userToken,
                    platform: .ios,
                    addresses: [ApiNotificationAddress(
                        title: account.displayName.nilIfEmpty,
                        address: tonAddress,
                        chain: .ton
                    )]
                ))
                info.enabledAccounts[account.id] = result.addressKeys.values.first
                AppStorageHelper.pushNotifications = info
            } else {
                log.info("_subscribeNotifications: no info or token or ton address")
            }
        } catch {
            log.info("_subscribeNotifications: \(error)")
        }
    }

    private func _unsubscribeNotifications(account: MAccount) async {
        do {
            if var info = AppStorageHelper.pushNotifications,
                let userToken = info.userToken,
                let tonAddress = account.tonAddress
            {
                let result = try await Api.unsubscribeNotifications(props: ApiUnsubscribeNotificationsProps(
                    userToken: userToken,
                    addresses: [ApiNotificationAddress(
                        title: account.displayName.nilIfEmpty,
                        address: tonAddress,
                        chain: .ton
                    )]
                ))
                log.info("\(result as Any)")
                info.enabledAccounts[account.id] = nil
                AppStorageHelper.pushNotifications = info
            } else {
                log.info("_unsubscribeNotifications: no info or userToken or ton address")
            }
        } catch {
            log.info("\(error)")
        }
    }

    // MARK: - Misc

    private var _assetsAndActivityData: UnfairLock<[String: MAssetsAndActivityData]> = .init(initialState: [:])
    public var assetsAndActivityData: [String: MAssetsAndActivityData] {
        _assetsAndActivityData.withLock { $0 }
    }
    public var currentAccountAssetsAndActivityData: MAssetsAndActivityData? {
        _assetsAndActivityData.withLock { $0[AccountStore.accountId ?? ""]}
    }
    public func setAssetsAndActivityData(accountId: String, value: MAssetsAndActivityData) {
        _assetsAndActivityData.withLock { $0[accountId] = value }
        AppStorageHelper.save(accountId: accountId, assetsAndActivityData: value.toDictionary)
        WalletCoreData.notify(event: .assetsAndActivityDataUpdated, for: accountId)
    }

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
                    "ton": AccountChain(address: "UQf7abcd1234efgh5678ijkl9012mnop34Aef3dsdaQ8N", domain: nil),
                    "tron": AccountChain(address: "TUQf7abcd1234efgh5678ijkl9012mnop34ef3dsdaPqh", domain: nil),
                ]
            ),
            MAccount(
                id: "1-mainnet",
                title: "Personal Wallet",
                type: .mnemonic,
                byChain: [
                    "ton": AccountChain(address: "UQf7abcd1234efgh5678ijkl9012mnop34ef3dsdaQ8N", domain: "tema.ton"),
                    "tron": AccountChain(address: "TUQf7abcd1234efgh5678ijkl9012mnop34ef3dsdacC9", domain: "screamingseagull.tron"),
                ]
            ),
            MAccount(
                id: "2-mainnet",
                title: "My Saved",
                type: .view,
                byChain: [
                    "ton": AccountChain(address: "UQf7abcd1234efgh5678ijkl9012mnop3456qrst7890d0Gh", domain: nil),
                ]
            ),
            MAccount(
                id: "3-testnet",
                title: "Just for Test",
                type: .view,
                byChain: [
                    "ton": AccountChain(address: "UQdk9876zyxw5432vuts2109rqpo8765nmlk4321jihg7654z7-d", domain: nil),
                ]
            ),
            MAccount(
                id: "4-mainnet",
                title: "Yet Another Walleeeeeeeeeeeeeeeeeeet",
                type: .mnemonic,
                byChain: [
                    "ton": AccountChain(address: "UQ2c1234abcd5678efgh9012ijkl3456mnop7890qrst2345Kd9A", domain: nil),
                ]
            ),
            MAccount(
                id: "5-mainnet",
                title: "Family Wallet",
                type: .hardware,
                byChain: [
                    "ton": AccountChain(address: "EQ9876abcd5432efgh2109ijkl8765mnop4321qrst7890klmn9-d", domain: nil),
                    "tron": AccountChain(address: "T9876543210abcdefghijklmnopqrstuvwxyz01234567890Va", domain: nil),
                ]
            ),
            MAccount(
                id: "6-mainnet",
                title: "Durov's Wallet",
                type: .view,
                byChain: [
                    "ton": AccountChain(address: "EQabcdef1234567890ghijklmnopqrstuvwxyzABCDEFGHIJKLMNOP", domain: "wolf.t.me"),
                ]
            ),
            MAccount(
                id: "7-mainnet",
                title: "Old Wallet",
                type: .mnemonic,
                byChain: [
                    "ton": AccountChain(address: "EQ1234abcd5678efgh9012ijkl3456mnop7890qrst2345uvwxwQ9", domain: nil),
                    "tron": AccountChain(address: "Tabcdef1234567890ghijklmnopqrstuvwxyzABCDEFGHIJKLMN0cH", domain: nil),
                ]
            ),
            MAccount(
                id: "8-mainnet",
                title: "Super Secret",
                type: .mnemonic,
                byChain: [
                    "ton": AccountChain(address: "UQc81234abcd5678efgh9012ijkl3456mnop7890qrst2345uvwxc4Zs", domain: nil),
                ]
            ),
            
        ].orderedDictionaryByKey(\.id)
        accountStore.accountId = "0-mainnet"
        accountStore.orderedAccountIds = accountStore.accountsById.keys
        return accountStore
    }()
}

extension DependencyValues {
    public var accountStore: _AccountStore {
        get { self[_AccountStore.self] }
        set { self[_AccountStore.self] = newValue }
    }
}
