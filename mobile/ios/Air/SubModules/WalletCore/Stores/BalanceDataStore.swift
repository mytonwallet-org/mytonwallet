import Dependencies
import Foundation
import Perception
import WalletContext

private let log = Log("BalanceDataStore")

public var BalanceDataStore: _BalanceDataStore { _BalanceDataStore.shared }

public final class AccountBalanceData: Sendable {
    @Perceptible
    public final class State: Sendable {
        private let _walletTokensData: UnfairLock<MAccountWalletTokensData?> = .init(initialState: nil)
        private let _balanceTotals: UnfairLock<MAccountBalanceTotals?> = .init(initialState: nil)

        nonisolated init() {}

        public var walletTokensData: MAccountWalletTokensData? {
            access(keyPath: \._walletTokensData)
            return _walletTokensData.withLock { $0 }
        }

        public var balanceTotals: MAccountBalanceTotals? {
            access(keyPath: \._balanceTotals)
            return _balanceTotals.withLock { $0 }
        }

        fileprivate func replace(walletTokensData: MAccountWalletTokensData?) {
            withMutation(keyPath: \._walletTokensData) {
                _walletTokensData.withLock { $0 = walletTokensData }
            }
        }

        fileprivate func replace(balanceTotals: MAccountBalanceTotals?) {
            withMutation(keyPath: \._balanceTotals) {
                _balanceTotals.withLock { $0 = balanceTotals }
            }
        }
    }

    public let accountId: String
    public let state = State()

    init(accountId: String) {
        self.accountId = accountId
    }

    public var walletTokensData: MAccountWalletTokensData? {
        state.walletTokensData
    }

    public var balanceTotals: MAccountBalanceTotals? {
        state.balanceTotals
    }

    func replace(walletTokensData: MAccountWalletTokensData?) {
        state.replace(walletTokensData: walletTokensData)
    }

    func replace(balanceTotals: MAccountBalanceTotals?) {
        state.replace(balanceTotals: balanceTotals)
    }
}

public actor _BalanceDataStore: WalletCoreData.EventsObserver {
    public static let shared = _BalanceDataStore()

    private struct ComputedAccountData {
        let walletTokensData: MAccountWalletTokensData
        let balanceTotals: MAccountBalanceTotals
    }

    // dependencies
    private let balancesStore: _BalancesStore
    private let stakingStore: _StakingStore
    private let assetsAndActivityDataStore: _AssetsAndActivityDataStore
    private let accountStore: _AccountStore
    private let tokenStore: _TokenStore

    private let byAccountId: ByAccountIdStore<AccountBalanceData> = .init(initialValue: { AccountBalanceData(accountId: $0) })
    private var updateDataTask: Task<Void, Never>?
    private var lastUpdateData: Date = .distantPast

    private init() {
        @Dependency(\.balancesStore) var balancesStore
        @Dependency(\.stakingStore) var stakingStore
        @Dependency(\.assetsAndActivityDataStore) var assetsAndActivityDataStore
        @Dependency(\.accountStore) var accountStore
        @Dependency(\.tokenStore) var tokenStore

        self.balancesStore = balancesStore
        self.stakingStore = stakingStore
        self.assetsAndActivityDataStore = assetsAndActivityDataStore
        self.accountStore = accountStore
        self.tokenStore = tokenStore
    }

    public func use() {
        WalletCoreData.add(eventObserver: self)
    }

    public func clean() {
        updateDataTask?.cancel()
        updateDataTask = nil
        lastUpdateData = .distantPast
        byAccountId.removeAll()
    }

    public nonisolated func `for`(accountId: String) -> AccountBalanceData {
        let context = byAccountId.for(accountId: accountId)
        if context.walletTokensData == nil || context.balanceTotals == nil {
            Task {
                await recomputeAccountIfMissing(accountId: accountId)
            }
        }
        return context
    }

    public nonisolated func walletTokensData(accountId: String) -> MAccountWalletTokensData? {
        self.for(accountId: accountId).walletTokensData
    }

    public nonisolated func balanceTotals(accountId: String) -> MAccountBalanceTotals? {
        self.for(accountId: accountId).balanceTotals
    }

    public nonisolated func totalBalance(ofWalletsWithType type: AccountType?) -> BaseCurrencyAmount {
        let filteredAccounts = accountStore.accountsById.values.filter { account in
            guard account.network == .mainnet else { return false }
            return if let type {
                account.type == type
            } else {
                true
            }
        }

        computeMissingAccounts(accountIds: filteredAccounts.map(\.id))

        var baseCurrency = tokenStore.baseCurrency
        let amount = filteredAccounts.reduce(BigInt.zero) { partialResult, account in
            guard let totals = byAccountId.existing(accountId: account.id)?.balanceTotals else {
                return partialResult
            }
            baseCurrency = totals.totalBalance.baseCurrency
            return partialResult + totals.totalBalance.amount
        }
        return BaseCurrencyAmount(amount, baseCurrency)
    }

    private nonisolated func computeMissingAccounts(accountIds: [String]) {
        for accountId in accountIds {
            let context = byAccountId.for(accountId: accountId)
            guard context.walletTokensData == nil || context.balanceTotals == nil else { continue }
            let nextData = computeAccountData(accountId: accountId)
            context.replace(walletTokensData: nextData.walletTokensData)
            context.replace(balanceTotals: nextData.balanceTotals)
        }
    }

    @MainActor public func walletCore(event: WalletCoreData.Event) {
        Task {
            await handleEvent(event)
        }
    }

    private func handleEvent(_ event: WalletCoreData.Event) {
        switch event {
        case .rawBalancesChanged(let accountId):
            recomputeAccount(accountId: accountId)
        case .stakingAccountData(let stakingData):
            recomputeAccount(accountId: stakingData.accountId)
        case .baseCurrencyChanged, .tokensChanged, .hideNoCostTokensChanged, .assetsAndActivityDataUpdated:
            scheduleRecomputeAllKnownAccounts()
        case .accountDeleted(let accountId):
            if let context = byAccountId.existing(accountId: accountId) {
                context.replace(walletTokensData: nil)
                context.replace(balanceTotals: nil)
            }
            byAccountId.remove(accountId: accountId)
        case .accountsReset:
            clean()
        default:
            break
        }
    }

    private func scheduleRecomputeAllKnownAccounts() {
        if Date().timeIntervalSince(lastUpdateData) > 0.1 {
            updateDataTask?.cancel()
            updateDataTask = Task {
                recomputeAllKnownAccounts()
            }
        } else {
            updateDataTask?.cancel()
            updateDataTask = Task {
                do {
                    try await Task.sleep(for: .seconds(0.1))
                    recomputeAllKnownAccounts()
                } catch {}
            }
        }
    }

    private func recomputeAllKnownAccounts() {
        lastUpdateData = .now
        for accountId in byAccountId.accountIds() {
            recomputeAccount(accountId: accountId)
        }
    }

    private func recomputeAccountIfMissing(accountId: String) {
        let context = byAccountId.for(accountId: accountId)
        guard context.walletTokensData == nil || context.balanceTotals == nil else { return }
        recomputeAccount(accountId: accountId)
    }

    private func recomputeAccount(accountId: String) {
        let nextData = computeAccountData(accountId: accountId)
        let context = byAccountId.for(accountId: accountId)
        let walletTokensChanged = context.walletTokensData != nextData.walletTokensData
        let balanceTotalsChanged = context.balanceTotals != nextData.balanceTotals

        if walletTokensChanged {
            context.replace(walletTokensData: nextData.walletTokensData)
        }
        if balanceTotalsChanged {
            context.replace(balanceTotals: nextData.balanceTotals)
        }

        if walletTokensChanged || balanceTotalsChanged {
            WalletCoreData.notify(event: .balanceChanged(accountId: accountId))
        }
    }

    private nonisolated func computeAccountData(accountId: String) -> ComputedAccountData {
        let balances = balancesStore.getAccountBalances(accountId: accountId)
        let stakingData = stakingStore.stakingData(accountId: accountId)
        let account = accountStore.get(accountId: accountId)
        var walletTokens: [MTokenBalance] = balances.map { slug, amount in
            MTokenBalance(tokenSlug: slug, balance: amount, isStaking: false)
        }

        var allTokensFound = true
        var totalBalance: Double = 0
        var totalBalanceYesterday: Double = 0
        var totalBalanceUsd: Double = 0
        var totalBalanceUsdByChain: [ApiChain: Double] = [:]

        for token in walletTokens {
            if token.tokenSlug == STAKED_TON_SLUG
                || token.tokenSlug == STAKED_MYCOIN_SLUG
                || token.tokenSlug == TON_TSUSDE_SLUG
            {
                continue
            }
            if let value = token.toBaseCurrency, let yesterday = token.toBaseCurrency24h {
                totalBalance += value
                totalBalanceYesterday += yesterday
                let amountInUsd = token.toUsd ?? 0
                totalBalanceUsd += amountInUsd
                if let chain = token.token?.chain {
                    totalBalanceUsdByChain[chain, default: 0] += amountInUsd
                }
            } else if tokenStore.tokens[token.tokenSlug] == nil {
                allTokensFound = false
            }
        }
        if !allTokensFound {
            log.error("not all tokens found \(accountId, .public)")
        }

        if AppStorageHelper.hideNoCostTokens {
            walletTokens = walletTokens.filter { balance in
                if (balance.toUsd ?? 0) <= 0.01, balance.token?.isPricelessToken != true {
                    return false
                }
                return true
            }
        }

        let prefs = assetsAndActivityDataStore.data(accountId: accountId) ?? MAssetsAndActivityData.empty

        for slug in prefs.importedSlugs {
            if !walletTokens.contains(where: { $0.tokenSlug == slug }),
               account.supports(chain: tokenStore.tokens[slug]?.chain) {
                walletTokens.append(MTokenBalance(tokenSlug: slug, balance: 0, isStaking: false))
            }
        }

        if totalBalance == 0 || totalBalanceUsd < TINY_TRANSFER_MAX_COST {
            let slugsInWallet = Set(walletTokens.map { $0.tokenSlug })
            let defaultSlugs = ApiToken.defaultSlugs(forNetwork: account.network, account: account)
            for slug in defaultSlugs.subtracting(slugsInWallet) {
                if account.supports(chain: tokenStore.tokens[slug]?.chain) {
                    walletTokens.append(MTokenBalance(tokenSlug: slug, balance: 0, isStaking: false))
                }
            }
        }

        walletTokens.removeAll(where: { prefs.isTokenHidden(slug: $0.tokenSlug, isStaking: $0.isStaking) })

        var walletStaked: [MTokenBalance] = stakingData?.stateById.values.compactMap { stakingState in
            let fullBalance = getFullStakingBalance(state: stakingState)
            return if fullBalance > 0 {
                MTokenBalance(tokenSlug: stakingState.tokenSlug, balance: fullBalance, isStaking: true)
            } else {
                nil
            }
        } ?? []

        if !walletStaked.isEmpty {
            assetsAndActivityDataStore.autoPinStakingIfNeeded(accountId: account.id, slugs: walletStaked.map(\.tokenSlug))
        }

        for token in walletStaked {
            if let value = token.toBaseCurrency, let yesterday = token.toBaseCurrency24h {
                totalBalance += value
                totalBalanceYesterday += yesterday
                if let amountInUSD = token.toUsd {
                    totalBalanceUsd += amountInUSD
                    if let chain = token.token?.chain {
                        totalBalanceUsdByChain[chain, default: 0] += amountInUSD
                    }
                }
            }
        }

        walletStaked.removeAll(where: { prefs.isTokenHidden(slug: $0.tokenSlug, isStaking: $0.isStaking) })

        let baseCurrency = tokenStore.baseCurrency
        let totalBalanceAmount = BaseCurrencyAmount.fromDouble(totalBalance, baseCurrency)
        let totalBalanceYesterdayAmount = BaseCurrencyAmount.fromDouble(totalBalanceYesterday, baseCurrency)
        let totalBalanceChange: Double? = if totalBalanceYesterday > 0 {
            (totalBalance - totalBalanceYesterday) / totalBalanceYesterday
        } else {
            nil
        }
        let orderedTokenBalances = MTokenBalance.sortedForBalanceData(
            tokenBalances: walletTokens + walletStaked,
            balances: balances,
            defaultTokenSlugs: ApiToken.defaultSlugs(forNetwork: account.network, account: account),
            importedTokenSlugs: prefs.importedSlugs
        )
        let walletTokensData = MAccountWalletTokensData(orderedTokenBalances: orderedTokenBalances)
        let balanceTotals = MAccountBalanceTotals(
            totalBalance: totalBalanceAmount,
            totalBalanceYesterday: totalBalanceYesterdayAmount,
            totalBalanceUsd: totalBalanceUsd,
            totalBalanceChange: totalBalanceChange,
            totalBalanceUsdByChain: totalBalanceUsdByChain
        )
        return ComputedAccountData(walletTokensData: walletTokensData, balanceTotals: balanceTotals)
    }
}

extension _BalanceDataStore: DependencyKey {
    public static let liveValue: _BalanceDataStore = .shared
}

public extension DependencyValues {
    var balanceDataStore: _BalanceDataStore {
        get { self[_BalanceDataStore.self] }
        set { self[_BalanceDataStore.self] = newValue }
    }
}
