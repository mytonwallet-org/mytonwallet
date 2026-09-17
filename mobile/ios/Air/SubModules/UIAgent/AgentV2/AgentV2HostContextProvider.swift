import BigInt
import Foundation
import UIKit
import WalletContext
import WalletCore

private let log = Log("AgentV2HostContext")

@MainActor
final class AgentV2HostContextProvider: WalletCoreData.EventsObserver, @unchecked Sendable {
    private enum LifecycleState: Equatable {
        case stopped
        case publishingInitial(needsRepublish: Bool)
        case ready

        var isStarted: Bool {
            self != .stopped
        }
    }

    private enum ScheduledUpdate: Equatable {
        case none
        case immediate(needsDebouncedUpdate: Bool)
        case debounced
        case deferredForRun
    }

    nonisolated private static let supportedChains: [ApiChain] = [.ton, .ethereum, .tron, .solana]
    nonisolated private static let maxCatalogAssets = 10_000
    private static let maxDynamicAuthorityUpdateAttempts = 3

    private let client: AgentV2Client
    private let dynamicAuthorityUpdateRetryDelay: Duration
    private var initialUpdateTask: Task<Bool, Never>?
    private var updateTask: Task<Void, Never>?
    private var updateGeneration = 0
    private var lifecycleState = LifecycleState.stopped
    private var scheduledUpdate = ScheduledUpdate.none
    private(set) var isAuthorityContextCurrent = true
    private(set) var publishedActiveAccountId: String?
    var isRunActive: @MainActor () -> Bool = { false }
    var onAuthorityContextInvalidated: @MainActor () -> Void = {}
    var onAuthorityContextPublished: @MainActor () -> Void = {}

    init(
        client: AgentV2Client,
        dynamicAuthorityUpdateRetryDelay: Duration = .milliseconds(250)
    ) {
        self.client = client
        self.dynamicAuthorityUpdateRetryDelay = dynamicAuthorityUpdateRetryDelay
    }

    deinit {
        initialUpdateTask?.cancel()
        updateTask?.cancel()
    }

    func start() async -> Bool {
        switch lifecycleState {
        case .ready:
            return true
        case .publishingInitial:
            return false
        case .stopped:
            break
        }
        isAuthorityContextCurrent = false
        lifecycleState = .publishingInitial(needsRepublish: false)
        WalletCoreData.add(eventObserver: self)
        updateGeneration += 1
        let generation = updateGeneration
        while true {
            lifecycleState = .publishingInitial(needsRepublish: false)
            let snapshot = await makeSnapshot()
            guard lifecycleState.isStarted, updateGeneration == generation else { return false }
            guard !Task.isCancelled else {
                resetFailedStart()
                return false
            }
            if lifecycleState == .publishingInitial(needsRepublish: true) {
                continue
            }
            let initialUpdateTask = Task { [client] in
                do {
                    try await client.updateHostContext(snapshot)
                    return !Task.isCancelled
                } catch {
                    log.error("initial update failed error=\(error)")
                    return false
                }
            }
            self.initialUpdateTask = initialUpdateTask
            let didPublishContext = await initialUpdateTask.value
            guard lifecycleState.isStarted, updateGeneration == generation else {
                return false
            }
            guard didPublishContext else {
                resetFailedStart()
                return false
            }
            if lifecycleState == .publishingInitial(needsRepublish: true) {
                continue
            }
            self.initialUpdateTask = nil
            lifecycleState = .ready
            publishAuthorityContext(snapshot)
            return true
        }
    }

    func stop() {
        guard lifecycleState.isStarted else { return }
        lifecycleState = .stopped
        isAuthorityContextCurrent = false
        cancelScheduledUpdate()
        WalletCoreData.remove(observer: self)
    }

    func flushDeferredDynamicUpdate() {
        guard lifecycleState.isStarted,
              scheduledUpdate == .deferredForRun,
              !isRunActive() else { return }
        scheduledUpdate = .none
        scheduleUpdate(immediately: false)
    }

    func walletCore(event: WalletCoreData.Event) {
        guard lifecycleState.isStarted else { return }
        switch event {
        case .accountsReset:
            invalidateAuthorityContext()
            cancelScheduledUpdate()
        case .accountChanged,
             .accountDeleted,
             .updateAccount:
            invalidateAuthorityContext()
            scheduleUpdate(immediately: true)
        case .accountNameChanged,
             .savedAddressesChanged:
            scheduleUpdate(immediately: true)
        case .balanceChanged,
             .notActiveAccountBalanceChanged,
             .swapTokensChanged,
             .nftsChanged,
             .rawBalancesChanged,
             .stakingAccountData,
             .tokensChanged,
             .baseCurrencyChanged,
             .hideUnverifiedNftsChanged,
             .assetsAndActivityDataUpdated:
            scheduleUpdate(immediately: false)
        default:
            break
        }
    }

    private func scheduleUpdate(immediately: Bool, retryAttempt: Int = 0) {
        if case .publishingInitial = lifecycleState {
            lifecycleState = .publishingInitial(needsRepublish: true)
            return
        }
        if !immediately, case .immediate = scheduledUpdate {
            scheduledUpdate = .immediate(needsDebouncedUpdate: true)
            return
        }

        updateGeneration += 1
        let generation = updateGeneration
        updateTask?.cancel()
        if immediately {
            scheduledUpdate = .immediate(needsDebouncedUpdate: false)
        } else {
            scheduledUpdate = .debounced
        }
        updateTask = Task { [weak self] in
            guard let self else { return }
            if retryAttempt > 0 {
                try? await Task.sleep(for: self.dynamicAuthorityUpdateRetryDelay)
            } else if !immediately {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled, self.lifecycleState.isStarted else { return }
            if !immediately, self.isRunActive() {
                self.updateTask = nil
                self.scheduledUpdate = .deferredForRun
                return
            }
            let snapshot = await self.makeSnapshot()
            guard !Task.isCancelled, self.lifecycleState.isStarted,
                  self.updateGeneration == generation else { return }
            do {
                try await self.client.updateHostContext(snapshot)
            } catch {
                guard self.updateGeneration == generation else { return }
                log.error("dynamic update failed error=\(error)")
                self.updateTask = nil
                self.scheduledUpdate = .none
                if (immediately || !self.isAuthorityContextCurrent),
                   retryAttempt + 1 < Self.maxDynamicAuthorityUpdateAttempts {
                    self.scheduleUpdate(immediately: true, retryAttempt: retryAttempt + 1)
                }
                return
            }
            guard self.updateGeneration == generation else { return }
            self.updateTask = nil
            if immediately || !self.isAuthorityContextCurrent {
                self.publishAuthorityContext(snapshot)
            }
            guard immediately else {
                self.scheduledUpdate = .none
                return
            }
            guard self.scheduledUpdate == .immediate(needsDebouncedUpdate: true) else {
                self.scheduledUpdate = .none
                return
            }
            self.scheduledUpdate = .none
            self.scheduleUpdate(immediately: false)
        }
    }

    private func invalidateAuthorityContext() {
        isAuthorityContextCurrent = false
        onAuthorityContextInvalidated()
    }

    private func publishAuthorityContext(_ snapshot: ApiAgentV2HostContext) {
        publishedActiveAccountId = snapshot.activeAccountId
        isAuthorityContextCurrent = true
        onAuthorityContextPublished()
    }

    private func cancelScheduledUpdate() {
        updateGeneration += 1
        initialUpdateTask?.cancel()
        initialUpdateTask = nil
        updateTask?.cancel()
        updateTask = nil
        scheduledUpdate = .none
    }

    private func resetFailedStart() {
        lifecycleState = .stopped
        cancelScheduledUpdate()
        WalletCoreData.remove(observer: self)
    }

    struct AccountSnapshot: Sendable {
        let account: MAccount
        let balances: [MTokenBalance]?
        let assetPreferences: MAssetsAndActivityData
        let nfts: [DisplayNft]?
        let stakingData: MStakingData?
        let savedAddresses: [SavedAddress]
    }

    struct SnapshotInput: Sendable {
        let activeAccount: MAccount?
        let accounts: [AccountSnapshot]
        let savedAddresses: [SavedAddress]
        let tokens: [String: ApiToken]
        let swapAssets: [ApiToken]?
        let areUnverifiedNftsHidden: Bool
        let lang: String
        let baseCurrency: String
        let currencyRate: Double?
        let timeZone: String
        let appVersion: String?
        let theme: String
    }

    private func makeSnapshot() async -> ApiAgentV2HostContext {
        // Capture actor-owned state together before suspending. Formatting must not read live stores.
        let activeAccount = AccountStore.account
        let accounts = AccountStore.orderedAccounts.map { account in
            let context = AccountContext(accountId: account.id)
            return AccountSnapshot(
                account: account,
                balances: context.walletTokensData?.orderedTokenBalances,
                assetPreferences: AssetsAndActivityDataStore.data(accountId: account.id) ?? .empty,
                nfts: NftStore.getAccountNfts(accountId: account.id).map { Array($0.values) },
                stakingData: context.stakingData,
                savedAddresses: context.savedAddresses.values
            )
        }
        let baseCurrency = TokenStore.baseCurrency
        let input = SnapshotInput(
            activeAccount: activeAccount,
            accounts: accounts,
            savedAddresses: activeAccount.map { AccountContext(accountId: $0.id).savedAddresses.values } ?? [],
            tokens: TokenStore.tokens,
            swapAssets: TokenStore.swapAssets,
            areUnverifiedNftsHidden: AppStorageHelper.hideUnverifiedNfts,
            lang: LocalizationSupport.shared.langCode,
            baseCurrency: baseCurrency.rawValue,
            currencyRate: baseCurrency == .USD ? 1 : TokenStore.currencyRates[baseCurrency.rawValue]?.value,
            timeZone: TimeZone.autoupdatingCurrent.identifier,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            theme: UIApplication.shared.sceneKeyWindow?.traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
        )
        return await Self.makeSnapshot(input: input)
    }

    @concurrent static func makeSnapshot(input: SnapshotInput) async -> ApiAgentV2HostContext {
        assert(!Thread.isMainThread)
        let (assetCatalog, swapAssetCatalog) = makeCatalogs(tokens: input.tokens, swapAssets: input.swapAssets)
        let activeAccount = input.activeAccount
        let accounts = input.accounts.map {
            makeAccount($0, tokens: input.tokens, swapAssets: input.swapAssets, areUnverifiedNftsHidden: input.areUnverifiedNftsHidden)
        }
        let activeNetwork = activeAccount.flatMap { account in
            supportedChains.first(where: account.supports(chain:))
        }
        let savedAddresses = makeSavedAddresses(input.savedAddresses)
        let currencyRate = input.currencyRate.flatMap { $0 > 0 ? decimalString($0) : nil }
        let stakingOffers = activeAccount.flatMap { account in
            input.accounts.first(where: { $0.account.id == account.id })?.stakingData.map { stakingData in
                makeStakingOffers(account: account, stakingData: stakingData, assetCatalog: assetCatalog)
            }
        } ?? []

        return ApiAgentV2HostContext(
            lang: input.lang,
            baseCurrency: input.baseCurrency,
            currencyRate: currencyRate,
            timeZone: input.timeZone,
            appVersion: input.appVersion,
            theme: input.theme,
            activeAccountId: activeAccount?.id,
            activeNetwork: activeNetwork?.rawValue,
            isTestnet: activeAccount.map { $0.network == .testnet },
            stakingOffers: stakingOffers.isEmpty ? nil : stakingOffers,
            accounts: accounts,
            assetCatalog: assetCatalog,
            swapAssetCatalog: swapAssetCatalog,
            savedAddresses: savedAddresses
        )
    }

    nonisolated private static func makeCatalogs(
        tokens: [String: ApiToken],
        swapAssets: [ApiToken]?
    ) -> ([ApiAgentV2HostAsset], [ApiAgentV2HostAsset]?) {
        let assetCatalog = tokens.values
            .lazy
            .filter { supportedChains.contains($0.chain) }
            .prefix(maxCatalogAssets)
            .map { token in
                ApiAgentV2HostAsset(
                    slug: token.slug,
                    chain: token.chain.rawValue,
                    symbol: bounded(token.symbol, limit: 32),
                    name: bounded(token.name, limit: 80),
                    tokenAddress: token.tokenAddress,
                    decimals: token.decimals,
                    priceUsd: token.priceUsd.flatMap { $0 >= 0 ? decimalString($0) : nil },
                    percentChange24h: token.percentChange24h.flatMap(decimalString)
                )
            }
        return (Array(assetCatalog), makeSwapAssetCatalog(tokens: swapAssets))
    }

    nonisolated static func makeSwapAssetCatalog(
        tokens: [ApiToken]?
    ) -> [ApiAgentV2HostAsset]? {
        guard let tokens else { return nil }
        return Array(tokens.lazy.filter { token in
            supportedChains.contains(token.chain)
        }.prefix(Self.maxCatalogAssets).map { token in
            ApiAgentV2HostAsset(
                slug: token.slug,
                chain: token.chain.rawValue,
                symbol: Self.bounded(token.symbol, limit: 32),
                name: Self.bounded(token.name, limit: 80),
                tokenAddress: token.tokenAddress,
                decimals: token.decimals,
                priceUsd: token.priceUsd.flatMap { $0 > 0 ? Self.decimalString($0) : nil },
                percentChange24h: nil
            )
        })
    }

    nonisolated private static func makeStakingOffers(
        account: MAccount,
        stakingData: MStakingData,
        assetCatalog: [ApiAgentV2HostAsset]
    ) -> [ApiAgentV2HostStakingOffer] {
        let states = selectStakingOfferStates(
            Array(stakingData.stateById.values),
            shouldUseNominators: stakingData.shouldUseNominators
        )

        return states.compactMap { state in
            guard state.type != .unknown,
                  Self.isSafeStakingProductId(state.id),
                  let asset = assetCatalog.first(where: { $0.slug == state.tokenSlug })
            else { return nil }
            let annualYield = state.annualYield.value
            guard annualYield.isFinite,
                  annualYield >= 0,
                  annualYield <= 100_000,
                  let annualYieldString = Self.decimalString(annualYield)
            else { return nil }
            return ApiAgentV2HostStakingOffer(
                productId: state.id,
                asset: ApiAgentV2AssetIdentity(
                    slug: asset.slug,
                    chain: asset.chain,
                    symbol: asset.symbol,
                    name: asset.name,
                    tokenAddress: asset.tokenAddress,
                    decimals: asset.decimals
                ),
                annualYield: annualYieldString,
                yieldType: state.yieldType.rawValue,
                availability: account.supportsEarn && state.tokenSlug != MYCOIN_SLUG
                    ? "available"
                    : "disabled"
            )
        }.prefix(8).map { $0 }
    }

    nonisolated static func selectStakingOfferStates(
        _ states: [ApiStakingState],
        shouldUseNominators: Bool?
    ) -> [ApiStakingState] {
        states.filter { state in
            guard state.tokenSlug == TONCOIN_SLUG else { return true }
            return shouldUseNominators == true ? state.type == .nominators : state.type == .liquid
        }
    }

    nonisolated private static func isSafeStakingProductId(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$"#,
            options: .regularExpression
        ) != nil
    }

    nonisolated private static func makeAccount(
        _ snapshot: AccountSnapshot,
        tokens: [String: ApiToken],
        swapAssets: [ApiToken]?,
        areUnverifiedNftsHidden: Bool
    ) -> ApiAgentV2HostAccount {
        let account = snapshot.account
        let chains = Self.supportedChains.filter(account.supports(chain:))
        let addresses = Dictionary(uniqueKeysWithValues: chains.compactMap { chain in
            account.getAddress(chain: chain).map { (chain.rawValue, $0) }
        })
        let portfolioWalletKeys: [String] = account.network == .mainnet
            ? ApiChain.allCases.compactMap { chain in
                guard account.supports(chain: chain),
                      let address = account.getAddress(chain: chain),
                      !address.isEmpty else { return nil }
                return "\(chain.rawValue):\(address)"
            }
            : []
        let savedAddresses = makeSavedAddresses(snapshot.savedAddresses)
        let balances = snapshot.balances ?? []
        let assetPreferences = snapshot.assetPreferences
        let holdings: [ApiAgentV2HostHolding] = balances.compactMap { balance -> ApiAgentV2HostHolding? in
            guard let token = tokens[balance.tokenSlug], Self.supportedChains.contains(token.chain) else { return nil }
            return Self.makeHolding(
                tokenBalance: balance,
                token: token,
                visibility: assetPreferences.isTokenHidden(
                    slug: balance.tokenSlug,
                    isStaking: balance.isStaking
                ) ? "hidden" : "visible"
            )
        }
        let nftPositions = snapshot.nfts?.compactMap {
            makeNftPosition($0, areUnverifiedNftsHidden: areUnverifiedNftsHidden)
        } ?? []
        let stakingPositions = snapshot.stakingData.map { makeStakingPositions($0, tokens: tokens, swapAssets: swapAssets) } ?? []
        let positions = (nftPositions + stakingPositions).sorted { $0.id < $1.id }

        return ApiAgentV2HostAccount(
            accountId: account.id,
            label: Self.bounded(account.displayName, limit: 80),
            state: "active",
            accountType: account.isView ? "viewOnly" : account.isHardware ? "ledger" : "regular",
            isViewOnly: account.isView,
            chains: chains.map(\.rawValue),
            addresses: addresses,
            portfolioWalletKeys: portfolioWalletKeys,
            holdings: holdings,
            positions: positions,
            savedAddresses: savedAddresses,
            domainStates: [
                "accounts": ApiAgentV2HostDomainState(state: "fresh"),
                "positions": ApiAgentV2HostDomainState(
                    state: snapshot.balances == nil ? "notLoaded" : "fresh"
                ),
                "transactions": ApiAgentV2HostDomainState(state: "stale"),
                "value_series": ApiAgentV2HostDomainState(
                    state: portfolioWalletKeys.isEmpty ? "unavailable" : "stale"
                ),
                "contacts": ApiAgentV2HostDomainState(state: "fresh")
            ]
        )
    }

    nonisolated static func makeSavedAddresses(_ values: [SavedAddress]) -> [ApiAgentV2HostSavedAddress] {
        values.compactMap { saved in
            guard Self.supportedChains.contains(saved.chain) else { return nil }
            return ApiAgentV2HostSavedAddress(
                id: "\(saved.chain.rawValue):\(saved.address)",
                name: Self.bounded(saved.name, limit: 80),
                chain: saved.chain.rawValue,
                address: saved.address
            )
        }
    }

    nonisolated static func makeHolding(
        tokenBalance: MTokenBalance,
        token: ApiToken,
        visibility: String = "visible"
    ) -> ApiAgentV2HostHolding {
        let fiatValue = tokenBalance.toBaseCurrency.flatMap { value in
            value > 0 ? Self.decimalString(value) : nil
        }
        let balance = Self.decimalString(tokenBalance.balance, decimals: token.decimals)
        return ApiAgentV2HostHolding(
            asset: ApiAgentV2HostAsset(
                slug: token.slug,
                chain: token.chain.rawValue,
                symbol: Self.bounded(token.symbol, limit: 32),
                name: Self.bounded(token.name, limit: 80),
                tokenAddress: token.tokenAddress,
                decimals: token.decimals
            ),
            balance: balance,
            availableBalance: tokenBalance.isStaking ? nil : balance,
            fiatValue: fiatValue,
            fiatPrice: tokenBalance.tokenPrice.flatMap { $0 > 0 ? Self.decimalString($0) : nil },
            valuationStatus: fiatValue == nil ? "unpriced" : "valued",
            visibility: visibility,
            riskVerdict: nil
        )
    }

    nonisolated static func makeNftPosition(_ displayNft: DisplayNft, areUnverifiedNftsHidden: Bool) -> ApiAgentV2HostPosition? {
        let nft = displayNft.nft
        guard supportedChains.contains(nft.chain) else { return nil }
        return ApiAgentV2HostPosition(
            id: "nft-\(nft.id)",
            kind: "nft",
            chain: nft.chain.rawValue,
            label: bounded(nft.name ?? nft.collectionName ?? "NFT", limit: 80),
            valuationStatus: "not_applicable",
            collection: nft.collectionName.map { bounded($0, limit: 80) },
            isOnSale: nft.isOnSale,
            visibility: displayNft.shouldHide(areUnverifiedNftsHidden: areUnverifiedNftsHidden) ? "hidden" : "visible",
            riskVerdict: nft.isScam == true ? "spam" : nil
        )
    }

    nonisolated static func makeStakingPositions(_ stakingData: MStakingData, tokens: [String: ApiToken], swapAssets: [ApiToken]?) -> [ApiAgentV2HostPosition] {
        stakingData.stateById.values.compactMap { state in
            guard state.type != .unknown,
                  state.balance > 0,
                  let token = tokens[state.tokenSlug] ?? swapAssets?.first(where: { $0.slug == state.tokenSlug }),
                  supportedChains.contains(token.chain) else { return nil }
            return ApiAgentV2HostPosition(
                id: "staking-\(state.id)",
                kind: "staking",
                chain: token.chain.rawValue,
                label: "\(bounded(token.symbol, limit: 32)) staking",
                asset: ApiAgentV2HostAsset(
                    slug: token.slug,
                    chain: token.chain.rawValue,
                    symbol: bounded(token.symbol, limit: 32),
                    name: bounded(token.name, limit: 80),
                    tokenAddress: token.tokenAddress,
                    decimals: token.decimals
                ),
                quantity: decimalString(state.balance, decimals: token.decimals),
                valuationStatus: "unpriced",
                status: (state.unstakeRequestAmount ?? 0) > 0 ? "unstaking" : "active",
                apy: decimalString(state.apy),
                rewards: state.unclaimedRewards.flatMap { rewards in
                    rewards > 0 ? decimalString(rewards, decimals: token.decimals) : nil
                },
                visibility: "visible"
            )
        }
    }

    nonisolated private static func decimalString(_ value: BigInt, decimals: Int) -> String {
        let raw = String(value)
        let isNegative = raw.first == "-"
        let digits = isNegative ? String(raw.dropFirst()) : raw
        guard decimals > 0 else { return raw }

        let padded = String(repeating: "0", count: max(0, decimals + 1 - digits.count)) + digits
        let splitIndex = padded.index(padded.endIndex, offsetBy: -decimals)
        let integerPart = padded[..<splitIndex]
        var fractionalPart = String(padded[splitIndex...])
        while fractionalPart.last == "0" {
            fractionalPart.removeLast()
        }
        let sign = isNegative ? "-" : ""
        return fractionalPart.isEmpty
            ? "\(sign)\(integerPart)"
            : "\(sign)\(integerPart).\(fractionalPart)"
    }

    nonisolated private static func decimalString(_ value: Double) -> String? {
        guard value.isFinite,
              let decimal = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return NSDecimalNumber(decimal: decimal).stringValue
    }

    nonisolated private static func bounded(_ value: String, limit: Int) -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
            .components(separatedBy: .controlCharacters)
            .joined()
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return String(normalized.prefix(limit))
    }
}
