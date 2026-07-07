import Dependencies
import Foundation
import Perception
import WalletContext
import WalletCoreTypes

private let log = Log("BalanceDataStore")

public var BalanceDataStore: _BalanceDataStore { _BalanceDataStore.shared }

@MainActor
@Perceptible
public final class AccountBalanceData: Sendable {
    public let accountId: String
    public private(set) var walletTokensData: MAccountWalletTokensData?
    public private(set) var balanceTotals: MAccountBalanceTotals?

    nonisolated init(accountId: String) {
        self.accountId = accountId
    }

    fileprivate var isMissing: Bool {
        walletTokensData == nil || balanceTotals == nil
    }

    @discardableResult
    fileprivate func replace(
        walletTokensData nextWalletTokensData: MAccountWalletTokensData?,
        balanceTotals nextBalanceTotals: MAccountBalanceTotals?
    ) -> Bool {
        let walletTokensChanged = walletTokensData != nextWalletTokensData
        let balanceTotalsChanged = balanceTotals != nextBalanceTotals

        if walletTokensChanged {
            walletTokensData = nextWalletTokensData
        }
        if balanceTotalsChanged {
            balanceTotals = nextBalanceTotals
        }

        return walletTokensChanged || balanceTotalsChanged
    }
}

public actor _BalanceDataStore: WalletCoreData.EventsObserver {
    public static let shared = _BalanceDataStore()

    private struct ComputedAccountData: Sendable {
        let walletTokensData: MAccountWalletTokensData
        let balanceTotals: MAccountBalanceTotals
    }

    // dependencies
    private let balancesStore: _BalancesStore
    private let stakingStore: _StakingStore
    private let assetsAndActivityDataStore: _AssetsAndActivityDataStore
    private let accountStore: _AccountStore
    private let tokenStore: _TokenStore

    @MainActor private var byAccountId: MainActorByAccountIdStore<AccountBalanceData> = .init(initialValue: AccountBalanceData.init(accountId:))
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

    public func clean() async {
        updateDataTask?.cancel()
        updateDataTask = nil
        lastUpdateData = .distantPast
        await MainActor.run {
            byAccountId.removeAll()
        }
    }

    @MainActor public func `for`(accountId: String) -> AccountBalanceData {
        let context = byAccountId.for(accountId: accountId)
        if context.isMissing {
            Task {
                await recomputeAccountIfMissing(accountId: accountId)
            }
        }
        return context
    }

    @MainActor public func walletTokensData(accountId: String) -> MAccountWalletTokensData? {
        self.for(accountId: accountId).walletTokensData
    }

    @MainActor public func balanceTotals(accountId: String) -> MAccountBalanceTotals? {
        self.for(accountId: accountId).balanceTotals
    }

    @MainActor public func totalBalance(ofWalletsWithType type: AccountType?) -> BaseCurrencyAmount {
        let filteredAccounts = accountStore.accountsById.values.filter { account in
            guard account.network == .mainnet else { return false }
            return if let type {
                account.type == type
            } else {
                true
            }
        }

        var baseCurrency = tokenStore.baseCurrency
        let amount = filteredAccounts.reduce(BigInt.zero) { partialResult, account in
            let context = byAccountId.for(accountId: account.id)
            if context.isMissing {
                Task {
                    await recomputeAccountIfMissing(accountId: account.id)
                }
            }
            guard let totals = context.balanceTotals else {
                return partialResult
            }
            baseCurrency = totals.totalBalance.baseCurrency
            return partialResult + totals.totalBalance.amount
        }
        return BaseCurrencyAmount(amount, baseCurrency)
    }

    @MainActor public func walletCore(event: WalletCoreData.Event) {
        Task {
            await handleEvent(event)
        }
    }

    private func handleEvent(_ event: WalletCoreData.Event) async {
        switch event {
        case .rawBalancesChanged(let accountId):
            await recomputeAccount(accountId: accountId)
        case .stakingAccountData(let stakingData):
            await recomputeAccount(accountId: stakingData.accountId)
        case .baseCurrencyChanged, .tokensChanged, .hideNoCostTokensChanged, .assetsAndActivityDataUpdated:
            scheduleRecomputeAllKnownAccounts()
        case .accountDeleted(let accountId):
            await removeAccountData(accountId: accountId)
        case .accountsReset:
            await clean()
        default:
            break
        }
    }

    private func scheduleRecomputeAllKnownAccounts() {
        if Date().timeIntervalSince(lastUpdateData) > 0.1 {
            updateDataTask?.cancel()
            updateDataTask = Task {
                await recomputeAllKnownAccounts()
            }
        } else {
            updateDataTask?.cancel()
            updateDataTask = Task {
                do {
                    try await Task.sleep(for: .seconds(0.1))
                    await recomputeAllKnownAccounts()
                } catch {}
            }
        }
    }

    private func recomputeAllKnownAccounts() async {
        lastUpdateData = .now
        let accountIds = await MainActor.run {
            byAccountId.accountIds()
        }
        for accountId in accountIds {
            await recomputeAccount(accountId: accountId)
        }
    }

    private func recomputeAccountIfMissing(accountId: String) async {
        let isMissing = await MainActor.run {
            byAccountId.for(accountId: accountId).isMissing
        }
        guard isMissing else { return }
        await recomputeAccount(accountId: accountId)
    }

    private func recomputeAccount(accountId: String) async {
        let nextData = computeAccountData(accountId: accountId)
        let changed = await applyAccountData(accountId: accountId, nextData: nextData)
        if changed {
            WalletCoreData.notify(event: .balanceChanged(accountId: accountId))
        }
    }

    @MainActor private func applyAccountData(accountId: String, nextData: ComputedAccountData) -> Bool {
        byAccountId
            .for(accountId: accountId)
            .replace(walletTokensData: nextData.walletTokensData, balanceTotals: nextData.balanceTotals)
    }

    @MainActor private func removeAccountData(accountId: String) {
        if let context = byAccountId.existing(accountId: accountId) {
            context.replace(walletTokensData: nil, balanceTotals: nil)
        }
        byAccountId.remove(accountId: accountId)
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

        var stakingSlugsToAutoPin: [String] = []
        var walletStaked: [MTokenBalance] = stakingData?.stateById.values.compactMap { stakingState in
            let fullBalance = getFullStakingBalance(state: stakingState)
            guard fullBalance > 0 else {
                return nil
            }
            if getHasPositiveStakingYield(state: stakingState) {
                stakingSlugsToAutoPin.append(stakingState.tokenSlug)
            }
            return MTokenBalance(tokenSlug: stakingState.tokenSlug, balance: fullBalance, isStaking: true)
        } ?? []

        if !stakingSlugsToAutoPin.isEmpty {
            assetsAndActivityDataStore.autoPinStakingIfNeeded(accountId: account.id, slugs: stakingSlugsToAutoPin)
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
