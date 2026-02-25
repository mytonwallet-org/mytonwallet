//
//  BalanceStore.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/30/24.
//

import Dependencies
import Foundation
import OrderedCollections
import Perception
import WalletContext

private let log = Log("BalanceStore")

public var BalanceStore: _BalanceStore { _BalanceStore.shared }

@Perceptible
public final class _BalanceStore {

    public static let shared = _BalanceStore()

    private let _balances: UnfairLock<[String: [String: BigInt]]> = .init(initialState: [:])
    private var balances: [String: [String: BigInt]] {
        _balances.withLock { $0 }
    }

    public func getAccountBalances(accountId: String) -> [String: BigInt] {
        access(keyPath: \._balances)
        return balances[accountId] ?? [:]
    }

    private let _accountBalanceData: UnfairLock<[String: MAccountBalanceData]> = .init(initialState: [:])
    public var accountBalanceData: [String: MAccountBalanceData] {
        access(keyPath: \._accountBalanceData)
        return _accountBalanceData.withLock { $0 }
    }

    private let _balancesEventCalledOnce: UnfairLock<[String: Bool]> = .init(initialState: [:])
    public var balancesEventCalledOnce: [String: Bool] {
        _balancesEventCalledOnce.withLock { $0 }
    }

    private let _accountsToSave: UnfairLock<Set<String>> = .init(initialState: [])
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

    public func totalBalance(ofWalletsWithType type: AccountType?) -> BaseCurrencyAmount {
        let accounts = AccountStore.accountsById
        var data = accountBalanceData
        data = data.filter { data in
            if let account = accounts[data.key], account.network == .mainnet {
                return if let type {
                    account.type == type
                } else {
                    true
                }
            }
            return false
        }

        // We assume all base currencies in `accountBalanceData` are the same.
        let baseCurrency = data.values.first?.totalBalance.baseCurrency ?? TokenStore.baseCurrency
        let totalAmount: BigInt = data.values.reduce(0) { partialResult, balanceData in
            partialResult + balanceData.totalBalance.amount
        }
        return BaseCurrencyAmount(totalAmount, baseCurrency)
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
            withMutation(keyPath: \._balances) {
                _balances.withLock { [updatedBalancesDict] in
                    $0 = updatedBalancesDict
                }
            }
            self.updateAccountBalanceData()
            WalletCoreData.add(eventObserver: self)
        }
    }

    public func clean() {
        withMutation(keyPath: \._balances) {
            _balances.withLock { $0 = [:] }
        }
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
                if balanceToUpdate == STAKED_TON_SLUG, let stakingState = StakingStore.stakingData(forAccountID: accountId)?.tonState { // use staking data insead, it includes amount earned
                    updatedBalances[balanceToUpdate] = stakingState.balance
                } else if balanceToUpdate == STAKED_MYCOIN_SLUG, let stakingState = StakingStore.stakingData(forAccountID: accountId)?.mycoinState {
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

            withMutation(keyPath: \._balances) {
                self._balances.withLock { [updatedBalances] in
                    $0[accountId] = updatedBalances
                }
            }

            saveToCache(accountId: accountId, balances: updatedBalances)
            recalculateAccountData(accountId: accountId, balances: updatedBalances, staked: [])
        }
    }

    private func saveToCache(accountId: String, balances _: [String: BigInt]) {
        assert(!Thread.isMainThread)
        accountsToSave.insert(accountId)
        saveToCacheTask?.cancel()
        saveToCacheTask = Task.detached(priority: .background) {
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
            } catch {}
        }
    }

    private func recalculateAccountData(accountId: String, balances: [String: BigInt], staked: [MStakingData]) {
        assert(!Thread.isMainThread)
        var walletTokens: [MTokenBalance] = balances.map { slug, amount in
            MTokenBalance(tokenSlug: slug, balance: amount, isStaking: false)
        }
        let account = AccountStore.get(accountId: accountId)
        var allTokensFound = true
        var totalBalance: Double = 0
        var totalBalanceYesterday: Double = 0
        var totalBalanceUsd: Double = 0

        // 1.1 Increment wallet total balance first (for walletTokens)
        for token in walletTokens {
            if token.tokenSlug == TON_USDE_SLUG {
                continue // will be counted with staking states
            }
            if let value = token.toBaseCurrency, let yesterday = token.toBaseCurrency24h {
                totalBalance += value
                totalBalanceYesterday += yesterday
                totalBalanceUsd += token.toUsd ?? 0
            } else if TokenStore.tokens[token.tokenSlug] != nil {
                // it's fine i guess
            } else {
                allTokensFound = false
            }
        }
        if !allTokensFound {
            log.error("not all tokens found \(accountId, .public)")
        }

        // 1.2 Then hide NoCost walletTokens
        if AppStorageHelper.hideNoCostTokens {
            walletTokens = walletTokens.filter { balance in
                if (balance.toUsd ?? 0) <= 0.01, balance.token?.isPricelessToken != true {
                    return false
                }
                return true
            }
        }

        let prefs = AccountStore.assetsAndActivityData(forAccountID: accountId) ?? MAssetsAndActivityData.empty

        for t in prefs.importedSlugs {
            if !walletTokens.contains(where: { $0.tokenSlug == t }) {
                if account.supports(chain: TokenStore.tokens[t]?.chain) {
                    walletTokens.append(MTokenBalance(tokenSlug: t, balance: 0, isStaking: false))
                }
            }
        }

        // If there are no transactions yet, then add default tokens
        if totalBalance == 0 || totalBalanceUsd < TINY_TRANSFER_MAX_COST {
            let slugsInWallet = Set(walletTokens.map { $0.tokenSlug })
            let defaultSlugs = ApiToken.defaultSlugs(forNetwork: account.network)

            for defaultStubSlug in defaultSlugs.subtracting(slugsInWallet) {
                if account.supports(chain: TokenStore.tokens[defaultStubSlug]?.chain) {
                    walletTokens.append(MTokenBalance(tokenSlug: defaultStubSlug, balance: 0, isStaking: false))
                }
            }
        }

        // 1.3 + hide walletTokens that hidden by user
        walletTokens.removeAll(where: { prefs.isTokenHidden(slug: $0.tokenSlug, isStaking: $0.isStaking) })

        var walletStaked: [MTokenBalance] = StakingStore.stakingData(forAccountID: accountId)?.stateById.values.compactMap { stakingState in
            let fullBalance = getFullStakingBalance(state: stakingState)
            return if fullBalance > 0 {
                MTokenBalance(tokenSlug: stakingState.tokenSlug, balance: fullBalance, isStaking: true)
            } else {
                nil
            }
        } ?? []

        if AccountStore.isAssetsAndActivityDataLoaded, StakingStore.isStakingDataLoaded,
           prefs.pinningFeatureHasNotYetBeenEverUsed, !walletStaked.isEmpty {
            // check via `isAssetsAndActivityDataLoaded` state for real AssetsAndActivityData prefs that were
            // loaded from persistent storage.
            // without this check real prefs will erased by MAssetsAndActivityData.empty created above.

            AccountStore.updateAssetsAndActivityData(forAccountID: account.id, update: { settings in
                walletStaked.forEach { token in
                    // Mark current stakings as pinned, it is needed for app release when pinning feature introduced
                    // Not needed for new users, as pinning is made automatically when staking is made
                    settings.saveTokenPinning(slug: token.tokenSlug, isStaking: token.isStaking, isPinned: true)
                }
            })
        }

        // 2.1 Increment wallet total balance first (walletStaked)
        for token in walletStaked {
            if let value = token.toBaseCurrency, let yesterday = token.toBaseCurrency24h {
                totalBalance += value // ?? is it correct to add both value and amountInUSD?
                totalBalanceYesterday += yesterday
                if let amountInUSD = token.toUsd { totalBalanceUsd += amountInUSD }
            }
        }

        // 2.2 Then hide walletStaked tokens
        walletStaked.removeAll(where: { prefs.isTokenHidden(slug: $0.tokenSlug, isStaking: $0.isStaking) })

        let bc = TokenStore.baseCurrency
        let totalBalanceAmount = BaseCurrencyAmount.fromDouble(totalBalance, bc)
        let totalBalanceYesterdayAmount = BaseCurrencyAmount.fromDouble(totalBalanceYesterday, bc)
        let totalBalanceChange: Double? = if totalBalanceYesterday > 0 {
            (totalBalance - totalBalanceYesterday) / totalBalanceYesterday
        } else {
            nil
        }
        let balanceData = MAccountBalanceData(walletTokens: walletTokens,
                                              walletStaked: walletStaked,
                                              totalBalance: totalBalanceAmount,
                                              totalBalanceYesterday: totalBalanceYesterdayAmount,
                                              totalBalanceUsd: totalBalanceUsd,
                                              totalBalanceChange: totalBalanceChange)
        let hasChanged = _accountBalanceData.withLock { $0[accountId] != balanceData }

        guard hasChanged else { return }

        withMutation(keyPath: \._accountBalanceData) {
            self._accountBalanceData.withLock {
                $0[accountId] = balanceData
            }
        }
        log.info("recalculateAccountData \(accountId, .public) balances \(balances.count) staked \(staked.count)", fileOnly: true)
        WalletCoreData.notify(event: .balanceChanged(accountId: accountId, isFirstUpdate: false))
    }

    private func updateAccountBalanceData() {
        assert(!Thread.isMainThread)
        log.info("updateAccountBalanceData (all)", fileOnly: true)
        for accountId in balances.keys {
            updateAccountBalance(accountId: accountId, balancesToUpdate: [:], removeOtherTokens: false)
        }
    }

    private func updateStakingData(accountId: String, stakingData _: MStakingData) {
        updateAccountBalance(accountId: accountId, balancesToUpdate: [:], removeOtherTokens: false)
        WalletCoreData.notify(event: .balanceChanged(accountId: accountId, isFirstUpdate: false))
    }

    private func setBalancesEventCalledOnce(accountId: String) {
        _balancesEventCalledOnce.withLock { $0[accountId] = true }
    }
}

extension _BalanceStore: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountDeleted(let accountId):
            withMutation(keyPath: \._balances) {
                _balances.withLock { $0[accountId] = nil }
            }
            _accountBalanceData.withLock { $0[accountId] = nil }
            _balancesEventCalledOnce.withLock { $0[accountId] = nil }

        case .baseCurrencyChanged, .tokensChanged, .hideNoCostTokensChanged, .assetsAndActivityDataUpdated:
            if Date().timeIntervalSince(lastUpdateData) > 0.1 {
                updateDataTask?.cancel()
                Task.detached {
                    self.lastUpdateData = .now
                    self.updateAccountBalanceData()
                }
            } else {
                updateDataTask?.cancel()
                updateDataTask = Task.detached {
                    do {
                        try await Task.sleep(for: .seconds(0.1))
                        self.lastUpdateData = .now
                        self.updateAccountBalanceData()
                    } catch {}
                }
            }

        case .updateBalances(let update):
            Task.detached {
                log.info("updateBalances \(update.accountId, .public) \(update.chain.rawValue, .public) \(update.balances.count)", fileOnly: true)
                let accountId = update.accountId
                let firstUpdate = self.balancesEventCalledOnce[accountId] != true
                if firstUpdate {
                    self.setBalancesEventCalledOnce(accountId: accountId)
                }
                let bigIntBalancesToUpdate = update.balances.mapValues { $0 }
                self.updateAccountBalance(accountId: accountId,
                                          balancesToUpdate: bigIntBalancesToUpdate,
                                          removeOtherTokens: false)
                WalletCoreData.notify(event: .balanceChanged(accountId: accountId, isFirstUpdate: firstUpdate))
            }

        case .stakingAccountData(let stakingData):
            updateStakingData(accountId: stakingData.accountId, stakingData: stakingData)

        default:
            break
        }
    }
}

extension _BalanceStore: DependencyKey {

    public static var liveValue: _BalanceStore { _BalanceStore.shared }

    public static let previewValue: _BalanceStore = {
        let balanceStore = _BalanceStore()
        let bc = TokenStore.baseCurrency
        balanceStore._accountBalanceData.withLock {
            $0 = [
                "0-mainnet": MAccountBalanceData(
                    walletTokens: [
                        MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: BigInt("85000000000000000"), isStaking: false), // ~85,000 TON
                        MTokenBalance(tokenSlug: TRX_SLUG, balance: BigInt("1500000000000"), isStaking: false), // ~1.5M TRX
                    ],
                    walletStaked: [],
                    totalBalance: BaseCurrencyAmount.fromDouble(523_123.52, bc),
                    totalBalanceYesterday: BaseCurrencyAmount.fromDouble(497_850.0, bc),
                    totalBalanceUsd: 523_123.52,
                    totalBalanceChange: (523_123.52 - 497_850.0) / 497_850.0
                ),
                "1-mainnet": MAccountBalanceData(
                    walletTokens: [
                        MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: BigInt("42000000000000000"), isStaking: false), // ~42,000 TON
                        MTokenBalance(tokenSlug: TON_USDT_SLUG, balance: BigInt("35000000000000"), isStaking: false), // ~35,000 USDT
                    ],
                    walletStaked: [],
                    totalBalance: BaseCurrencyAmount.fromDouble(245_089.70, bc),
                    totalBalanceYesterday: BaseCurrencyAmount.fromDouble(238_000.0, bc),
                    totalBalanceUsd: 245_089.70,
                    totalBalanceChange: (245_089.70 - 238_000.0) / 238_000.0
                ),
                "2-mainnet": MAccountBalanceData(
                    walletTokens: [
                        MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: BigInt("18000000000000000"), isStaking: false), // ~18,000 TON
                    ],
                    walletStaked: [],
                    totalBalance: BaseCurrencyAmount.fromDouble(95000.0, bc),
                    totalBalanceYesterday: BaseCurrencyAmount.fromDouble(91200.0, bc),
                    totalBalanceUsd: 95000.0,
                    totalBalanceChange: (95000.0 - 91200.0) / 91200.0
                ),
                "3-testnet": MAccountBalanceData(
                    walletTokens: [
                        MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: BigInt("0"), isStaking: false), // ~12,000 TON
                    ],
                    walletStaked: [],
                    totalBalance: BaseCurrencyAmount.fromDouble(6_252_000_009.59, bc),
                    totalBalanceYesterday: BaseCurrencyAmount.fromDouble(60120.0, bc),
                    totalBalanceUsd: 6_252_000_009.59,
                    totalBalanceChange: (6_252_000_009.59 - 60120.0) / 60120.0
                ),
                "4-mainnet": MAccountBalanceData(
                    walletTokens: [
                        MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: BigInt("58000000000000000"), isStaking: false), // ~58,000 TON
                        MTokenBalance(tokenSlug: TRX_SLUG, balance: BigInt("800000000000"), isStaking: false), // ~800K TRX
                    ],
                    walletStaked: [],
                    totalBalance: BaseCurrencyAmount.fromDouble(348_000.0, bc),
                    totalBalanceYesterday: BaseCurrencyAmount.fromDouble(331_200.0, bc),
                    totalBalanceUsd: 348_000.0,
                    totalBalanceChange: (348_000.0 - 331_200.0) / 331_200.0
                ),
                "5-mainnet": MAccountBalanceData(
                    walletTokens: [
                        MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: BigInt("32000000000000000"), isStaking: false), // ~32,000 TON
                    ],
                    walletStaked: [],
                    totalBalance: BaseCurrencyAmount.fromDouble(168_000.0, bc),
                    totalBalanceYesterday: BaseCurrencyAmount.fromDouble(159_600.0, bc),
                    totalBalanceUsd: 168_000.0,
                    totalBalanceChange: (168_000.0 - 159_600.0) / 159_600.0
                ),
                "6-mainnet": MAccountBalanceData(
                    walletTokens: [
                        MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: BigInt("95000000000000000"), isStaking: false), // ~95,000 TON
                    ],
                    walletStaked: [],
                    totalBalance: BaseCurrencyAmount.fromDouble(498_000.0, bc),
                    totalBalanceYesterday: BaseCurrencyAmount.fromDouble(473_100.0, bc),
                    totalBalanceUsd: 498_000.0,
                    totalBalanceChange: (498_000.0 - 473_100.0) / 473_100.0
                ),
                "7-mainnet": MAccountBalanceData(
                    walletTokens: [
                        MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: BigInt("26000000000000000"), isStaking: false), // ~26,000 TON
                        MTokenBalance(tokenSlug: TRON_USDT_SLUG, balance: BigInt("25000000000000"), isStaking: false), // ~25,000 USDT
                    ],
                    walletStaked: [],
                    totalBalance: BaseCurrencyAmount.fromDouble(201_000.0, bc),
                    totalBalanceYesterday: BaseCurrencyAmount.fromDouble(190_950.0, bc),
                    totalBalanceUsd: 201_000.0,
                    totalBalanceChange: (201_000.0 - 190_950.0) / 190_950.0
                ),
                "8-mainnet": MAccountBalanceData(
                    walletTokens: [
                        MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: BigInt("15000000000000000"), isStaking: false), // ~15,000 TON
                    ],
                    walletStaked: [],
                    totalBalance: BaseCurrencyAmount.fromDouble(78500.0, bc),
                    totalBalanceYesterday: BaseCurrencyAmount.fromDouble(75360.0, bc),
                    totalBalanceUsd: 78500.0,
                    totalBalanceChange: (78500.0 - 75360.0) / 75360.0
                ),
            ]
        }
        return balanceStore
    }()
}

extension DependencyValues {
    public var balanceStore: _BalanceStore {
        get { self[_BalanceStore.self] }
        set { self[_BalanceStore.self] = newValue }
    }
}
