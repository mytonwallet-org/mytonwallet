//
//  BalanceStore.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/30/24.
//

import Foundation
import WalletContext

private let log = Log("BalanceStore")

public var BalanceStore: _BalanceStore { _BalanceStore.shared }


public final class _BalanceStore {

    public static let shared = _BalanceStore()
    
    private var _balances: UnfairLock<[String: [String: BigInt]]> = .init(initialState: [:])
    private var balances: [String: [String: BigInt]] {
        _balances.withLock { $0 }
    }
    public func getAccountBalances(accountId: String) -> [String: BigInt] {
        balances[accountId] ?? [:]
    }
    public var currentAccountBalances: [String: BigInt] {
        getAccountBalances(accountId: AccountStore.accountId ?? "")
    }

    private var _accountBalanceData: UnfairLock<[String: MAccountBalanceData]> = .init(initialState: [:])
    public var accountBalanceData: [String: MAccountBalanceData] {
        _accountBalanceData.withLock { $0 }
    }
    public var currentAccountBalanceData: MAccountBalanceData? {
        _accountBalanceData.withLock { $0[AccountStore.accountId ?? ""] }
    }

    private var _balancesEventCalledOnce: UnfairLock<[String: Bool]> = .init(initialState: [:])
    public var balancesEventCalledOnce: [String: Bool] {
        _balancesEventCalledOnce.withLock { $0 }
    }
    
    public var currentAccountStakingData: MStakingData? {
        StakingStore.currentAccount
    }
    
    private var _accountsToSave: UnfairLock<Set<String>> = .init(initialState: [])
    private var accountsToSave: Set<String> {
        get { _accountsToSave.withLock { $0 } }
        set { _accountsToSave.withLock { $0 = newValue } }
    }

    private let processorQueue = DispatchQueue(label: "org.mytonwallet.app.balance_store_background_processor", qos: .utility)
    private var lastUpdateData: Date = .distantPast
    private var updateDataTask: Task<Void, Never>?
    private var saveToCacheTask: Task<Void, Never>?
    
    private init() {}
    
    // MARK: - Data providers

    public var totalBalanceInBaseCurrency: Double? {
        getTotalBalanceInBaseCurrency(for: AccountStore.accountId ?? "")
    }
    
    
    public func getTotalBalanceInBaseCurrency(for accountId: String) -> Double? {
        accountBalanceData[accountId]?.totalBalance
    }
    
    // MARK: - Lifecycle

    /// Loads all the balances from global storage on app start
    public func loadFromCache(accountIds: Set<String>) {
        processorQueue.async { [self] in
            var updatedBalancesDict = balances
            for account in accountIds {
                if let accountBalances = GlobalStorage.getDict(key: "byAccountId.\(account).balances.bySlug") {
                    if updatedBalancesDict[account] == nil {
                        updatedBalancesDict[account] = [:]
                    }
                    for (slug, value) in accountBalances {
                        if let amountValue = (value as? String)?.components(separatedBy: "bigint:")[1] {
                            updatedBalancesDict[account]![slug] = BigInt(amountValue) ?? 0
                        }
                    }
                    if !accountBalances.keys.isEmpty {
                        setBalancesEventCalledOnce(accountId: account)
                    }
                }
            }
            _balances.withLock { [updatedBalancesDict] in
                $0 = updatedBalancesDict
            }
            self.updateAccountBalanceData()
            WalletCoreData.add(eventObserver: self)
        }
    }

    public func clean() {
        _balances.withLock { $0 = [:] }
        _accountBalanceData.withLock { $0 = [:] }
        _balancesEventCalledOnce.withLock { $0 = [:] }
    }
    
    // MARK: - Internals
    
    /// Update an account balance
    private func updateAccountBalance(accountId: String, balancesToUpdate: [String: BigInt], removeOtherTokens: Bool) {
        processorQueue.async { [self] in
            assert(!Thread.isMainThread)
            var updatedBalances = removeOtherTokens ? [:] : self.balances[accountId] ?? [:]
            if updatedBalances[STAKED_TON_SLUG] == nil {
                updatedBalances[STAKED_TON_SLUG] = 0
            }
            if updatedBalances[STAKED_MYCOIN_SLUG] == nil {
                updatedBalances[STAKED_MYCOIN_SLUG] = 0
            }
            
            for (balanceToUpdate, val) in balancesToUpdate {
                if balanceToUpdate == STAKED_TON_SLUG, let stakingState = StakingStore.byId(accountId)?.tonState { // use staking data insead, it includes amount earned
                    updatedBalances[balanceToUpdate] = stakingState.balance
                } else if balanceToUpdate == STAKED_MYCOIN_SLUG, let stakingState = StakingStore.byId(accountId)?.mycoinState {
                    updatedBalances[balanceToUpdate] = stakingState.balance
                } else {
                    updatedBalances[balanceToUpdate] = val
                }
            }
            if updatedBalances[STAKED_TON_SLUG] == 0 {
                updatedBalances[STAKED_TON_SLUG] = nil
            }
            if updatedBalances[STAKED_MYCOIN_SLUG] == 0 {
                updatedBalances[STAKED_MYCOIN_SLUG] = nil
            }
            
            self._balances.withLock { [updatedBalances] in
                $0[accountId] = updatedBalances
            }
            
            saveToCache(accountId: accountId, balances: updatedBalances)
            recalculateAccountData(accountId: accountId, balances: updatedBalances, staked: [])
        }
    }
    
    private func saveToCache(accountId: String, balances: [String: BigInt]) {
        assert(!Thread.isMainThread)
        self.accountsToSave.insert(accountId)
        self.saveToCacheTask?.cancel()
        self.saveToCacheTask = Task.detached(priority: .background) {
            do {
                try await Task.sleep(for: .seconds(1))
                assert(!Thread.isMainThread)
                let accountsToSave = self.accountsToSave
                self.accountsToSave = []
                for accountId in accountsToSave {
                    let items: [String: String] = self.getAccountBalances(accountId: accountId).mapValues { "bigint:\($0)" }
                    GlobalStorage.update {
                        $0["byAccountId.\(accountId).balances.bySlug"] = items
                    }
                }
            } catch {
            }
        }
    }
    
    private func recalculateAccountData(accountId: String, balances: [String: BigInt], staked: [MStakingData]) {
        assert(!Thread.isMainThread)
        var walletTokens: [MTokenBalance] = balances.map { (slug, amount) in
            MTokenBalance(tokenSlug: slug, balance: amount, isStaking: false)
        }
        var allTokensFound = true
        var totalBalance: Double = 0
        var totalBalanceYesterday: Double = 0
        var totalBalanceUsd: Double = 0
        for token in walletTokens {
            if token.tokenSlug == TON_USDE_SLUG {
                continue // will be counted with staking states
            }
            if let value = token.toBaseCurrency, let yesterday = token.toBaseCurrency24h {
                totalBalance += value
                totalBalanceYesterday += yesterday
                totalBalanceUsd += token.toUsd ?? 0
            } else if let token = TokenStore.tokens[token.tokenSlug] {
                // it's fine i guess
            } else {
                allTokensFound = false
            }
        }
        if !allTokensFound {
            log.error("not all tokens found \(accountId, .public)")
        }
        if AppStorageHelper.hideNoCostTokens {
            walletTokens = walletTokens.filter { balance in
                if (balance.toUsd ?? 0) <= 0.01 && balance.token?.isPricelessToken != true {
                    return false
                }
                return true
            }
        }
        let prefs = AccountStore.assetsAndActivityData[accountId] ?? MAssetsAndActivityData.defaultData
        for t in prefs.alwaysShownSlugs {
            if !walletTokens.contains(where: { $0.tokenSlug == t }) {
                if AccountStore.accountsById[accountId]?.supports(chain: TokenStore.tokens[t]?.chain) == true {
                    walletTokens.append(MTokenBalance(tokenSlug: t, balance: 0, isStaking: false))
                }
            }
        }
        for t in prefs.importedSlugs {
            if !walletTokens.contains(where: { $0.tokenSlug == t }) {
                if AccountStore.accountsById[accountId]?.supports(chain: TokenStore.tokens[t]?.chain) == true {
                    walletTokens.append(MTokenBalance(tokenSlug: t, balance: 0, isStaking: false))
                }
            }
        }
        if totalBalance == 0 || totalBalanceUsd < TINY_TRANSFER_MAX_COST {
            for t in DEFAULT_SLUGS {
                if !walletTokens.contains(where: { $0.tokenSlug == t }) {
                    if AccountStore.accountsById[accountId]?.supports(chain: TokenStore.tokens[t]?.chain) == true {
                        walletTokens.append(MTokenBalance(tokenSlug: t, balance: 0, isStaking: false))
                    }
                }
            }
        }
        for t in prefs.alwaysHiddenSlugs {
            walletTokens.removeAll(where: { $0.tokenSlug == t })
        }
        for t in prefs.deletedSlugs {
            walletTokens.removeAll(where: { $0.tokenSlug == t })
        }
        walletTokens.sort()
        
        let walletStaked: [MTokenBalance] = StakingStore.byId(accountId)?.stateById.values
            .filter { stakingState in
                getFullStakingBalance(state: stakingState) > 0
            }
            .compactMap { stakingState in
                let fullBalance = getFullStakingBalance(state: stakingState)
                if fullBalance > 0 {
                    return MTokenBalance(tokenSlug: stakingState.tokenSlug, balance: fullBalance, isStaking: true)
                } else {
                    return nil
                }
            }
            .sorted() ?? []
        for token in walletStaked {
            if let value = token.toBaseCurrency, let yesterday = token.toBaseCurrency24h {
                totalBalance += value
                totalBalanceYesterday += yesterday
                totalBalanceUsd += token.toUsd ?? 0
            }
        }
        
        let balanceData = MAccountBalanceData(
            walletTokens: walletTokens,
            walletStaked: walletStaked,
            totalBalance: totalBalance,
            totalBalanceYesterday: totalBalanceYesterday
        )
        self._accountBalanceData.withLock {
            $0[accountId] = balanceData
        }
        WalletCoreData.notify(event: .balanceChanged(isFirstUpdate: false), for: accountId)
    }
    
    private func updateAccountBalanceData() {
        assert(!Thread.isMainThread)
        log.info("updateAccountBalanceData (all)", fileOnly: true)
        for accountId in balances.keys {
            updateAccountBalance(accountId: accountId, balancesToUpdate: [:], removeOtherTokens: false)
        }
    }
    
    private func updateStakingData(accountId: String, stakingData: MStakingData) {
        updateAccountBalance(accountId: accountId, balancesToUpdate: [:], removeOtherTokens: false)
        if AccountStore.accountId != accountId {
            WalletCoreData.notify(event: .notActiveAccountBalanceChanged, for: nil)
            return
        }
        WalletCoreData.notify(event: .balanceChanged(isFirstUpdate: false), for: accountId)
    }
    
    private func setBalancesEventCalledOnce(accountId: String) {
        _balancesEventCalledOnce.withLock { $0[accountId] = true }
    }
}


extension _BalanceStore: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged(isNew: _):
            Task.detached {
                self.updateAccountBalanceData()
            }
            
        case .accountDeleted(let accountId):
            _balances.withLock { $0[accountId] = nil }
            _accountBalanceData.withLock { $0[accountId] = nil }
            _balancesEventCalledOnce.withLock { $0[accountId] = nil }
            
        case .baseCurrencyChanged, .tokensChanged, .hideNoCostTokensChanged, .assetsAndActivityDataUpdated:
            if Date().timeIntervalSince(lastUpdateData) > 0.1 {
                self.updateDataTask?.cancel()
                Task.detached {
                    self.lastUpdateData = .now
                    self.updateAccountBalanceData()
                }
            } else {
                self.updateDataTask?.cancel()
                self.updateDataTask = Task.detached {
                    do {
                        try await Task.sleep(for: .seconds(0.1))
                        self.lastUpdateData = .now
                        self.updateAccountBalanceData()
                    } catch {
                    }
                }
            }

        case .updateBalances(let update):
//            log.debug("updateBalances")
            Task.detached {
                let accountId = update.accountId
                let firstUpdate = self.balancesEventCalledOnce[accountId] != true
                if firstUpdate {
                    self.setBalancesEventCalledOnce(accountId: accountId)
                }
                let bigIntBalancesToUpdate = update.balances.mapValues { $0 }
                self.updateAccountBalance(accountId: accountId,
                                     balancesToUpdate: bigIntBalancesToUpdate,
                                     removeOtherTokens: false)
                if AccountStore.accountId != accountId {
                    WalletCoreData.notify(event: .notActiveAccountBalanceChanged, for: nil)
                    return
                }
                WalletCoreData.notify(event: .balanceChanged(isFirstUpdate: firstUpdate), for: accountId)
            }
            
        case .stakingAccountData(let stakingData):
            updateStakingData(accountId: stakingData.accountId, stakingData: stakingData)

        default:
            break
        }
    }
}


