//
//  TokenStore.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/30/24.
//

import Foundation
import WalletContext
import Perception
import Dependencies
import WalletCoreTypes

public var TokenStore: _TokenStore { _TokenStore.shared }
private let HISTORY_DATA_STALENESS = 120.0
private let TOKEN_DETAILS_CACHE_VALIDITY: TimeInterval = 15 * 60
private let TOKEN_DETAILS_PRELOAD_LIMIT = 20
private let TOKEN_DETAILS_CACHE_LIMIT_PER_ACCOUNT = 50
private let log = Log("TokenStore")

private struct TokenDetailsRequest: Sendable {
    let id: UUID
    let task: Task<ApiTokenDetails?, Error>
}

private struct TokenDetailsPreloadSnapshot: Sendable {
    let accountId: String
    let tokens: [ApiToken]
}

private struct TokenDetailsPreloadRequest: Sendable {
    let id: UUID
    let task: Task<Void, Never>
}

private struct TokenDetailsPreloadState: Sendable {
    var isPending = false
    var request: TokenDetailsPreloadRequest?
}

private struct TokenDetailsPersistenceRequest: Sendable {
    let id: UUID
    let task: Task<Void, Never>
}

@Perceptible
public final class _TokenStore: Sendable {

    public static let shared = _TokenStore()
    
    private let _baseCurrency: UnfairLock<MBaseCurrency?> = .init(initialState: nil)
    private let _tokens: UnfairLock<[String: ApiToken]> = .init(initialState: _TokenStore.defaultTokens)
    private let _swapAssets: UnfairLock<[ApiToken]?> = .init(initialState: nil)
    private let _swapPairs: UnfairLock<[String: [MPair]]> = .init(initialState: [:])
    private let _currencyRates: UnfairLock<[String: MDouble]> = .init(initialState: [:])
    private let _tokenDetails: UnfairLock<TokenDetailsCache> = .init(initialState: TokenDetailsCache())
    private let tokenDetailsRequests: UnfairLock<[String: TokenDetailsRequest]> = .init(initialState: [:])
    private let isAppForeground: UnfairLock<Bool> = .init(initialState: true)

    private let sharedCache = SharedCache()

    @PerceptionIgnored
    private let updateTokensTask: UnfairLock<Task<Void, Never>?> = .init(initialState: nil)
    @PerceptionIgnored
    private let tokenDetailsPreloadState: UnfairLock<TokenDetailsPreloadState> = .init(initialState: .init())
    @PerceptionIgnored
    private let tokenDetailsMaintenanceTask: UnfairLock<Task<Void, Never>?> = .init(initialState: nil)
    @PerceptionIgnored
    private let tokenDetailsPersistenceRequest: UnfairLock<TokenDetailsPersistenceRequest?> = .init(initialState: nil)
    @PerceptionIgnored
    private let tokenDetailsDiskAccess: UnfairLock<Void> = .init(initialState: ())
    
    private init() {}

    public private(set) var baseCurrency: MBaseCurrency {
        get { _baseCurrency.withLock { $0 } ?? DEFAULT_PRICE_CURRENCY }
        set { _baseCurrency.withLock { $0 = newValue } }
    }
    
    public private(set) var currencyRates: [String: MDouble] {
        get { _currencyRates.withLock { $0 } }
        set { _currencyRates.withLock { $0 = newValue } }
    }
    
    public private(set) var tokens: [String: ApiToken] {
        get { _tokens.withLock { $0 } }
        set {
            withMutation(keyPath: \._tokens) {
                _tokens.withLock { $0 = newValue }
            }
        }
    }
    
    public subscript(_ slug: String) -> ApiToken? {
        access(keyPath: \._tokens)
        return _tokens.withLock { $0[slug] }
    }

    public private(set) var swapAssets: [ApiToken]? {
        get { _swapAssets.withLock { $0 } }
        set { _swapAssets.withLock { $0 = newValue } }
    }

    public var swapPairs: [String: [MPair]] {
        get { _swapPairs.withLock { $0 } }
        set { _swapPairs.withLock { $0 = newValue } }
    }
    
    public var baseCurrencyRate: Double {
        return currencyRates[baseCurrency.rawValue]?.value ?? 1.0
    }
    
    private func loadTokensFromCache() {
        self.baseCurrency = AppStorageHelper.tokensCurrency() ?? DEFAULT_PRICE_CURRENCY
        if let ratesDict = AppStorageHelper.currencyRatesDict() {
            self.currencyRates = ratesDict
        }
        if var tokensDict = AppStorageHelper.tokensDict() {
            self.baseCurrency = baseCurrency
            tokensDict.merge(Self.defaultTokens) { old, _ in old }
            self.tokens = tokensDict
            WalletCoreData.notify(event: .tokensChanged)
        } else {
            self.tokens = Self.defaultTokens
            // do not notify
        }
        scheduleSharedCacheUpdate(
            tokens: self.tokens,
            baseCurrency: self.baseCurrency,
            rates: self.currencyRates
        )
    }
    
    private func loadSwapAssetsFromCache() {
        guard let swapAssetsArray = AppStorageHelper.swapAssetsArray() else {
            return
        }
        process(swapAssetsArray: swapAssetsArray)
    }
    
    public func loadFromCache() {
        loadTokensFromCache()
        loadSwapAssetsFromCache()
        loadTokenDetailsFromCache()
        WalletCoreData.add(eventObserver: self)
        startTokenDetailsMaintenance()
        scheduleTokenDetailsPreload()
    }
    
    public func getToken(slug: String) -> ApiToken? {
        return tokens[slug] ?? TokenStore.swapAssets?.first(where: { swapAsset in
            swapAsset.slug == slug
        })
    }
    
    public func getToken(slugOrAddress: String) -> ApiToken? {
        tokens[slugOrAddress] ?? tokens.values.first(where: { token in
            token.tokenAddress == slugOrAddress
        }) ?? TokenStore.swapAssets?.first(where: { swapAsset in
            swapAsset.slug == slugOrAddress || swapAsset.tokenAddress == slugOrAddress
        })
    }

    public func getDisplayToken(slugOrAddress: String) -> ApiToken {
        getToken(slugOrAddress: slugOrAddress) ?? .unknown(slug: slugOrAddress)
    }
    
    public func getNativeToken(chain: ApiChain) -> ApiToken {
        tokens[chain.nativeToken.slug]!
    }
    
    private func process(
        newTokens: [String: ApiToken],
        kind: ApiUpdate.UpdateTokens.Kind,
        removedSlugs: [String],
        isIncomplete: Bool,
        unpricedSlugs: Set<String>
    ) {
        assert(!Thread.isMainThread)
        var tokens = _mergingTokenUpdate(
            currentTokens: self.tokens,
            newTokens: newTokens,
            kind: kind,
            removedSlugs: removedSlugs,
            isIncomplete: isIncomplete,
            unpricedSlugs: unpricedSlugs
        )
        _applyFixups(tokens: &tokens)
        guard self.tokens != tokens else {
            return
        }
        self.tokens = tokens
        WalletCoreData.notify(event: .tokensChanged)
        if tokens.count > 0 {
            AppStorageHelper.save(baseCurrency: self.baseCurrency, tokens: tokens, currencyRates: self.currencyRates)
        }
        scheduleSharedCacheUpdate(tokens: tokens, baseCurrency: self.baseCurrency, rates: self.currencyRates)
    }

    func _mergingTokenUpdate(
        currentTokens: [String: ApiToken],
        newTokens: [String: ApiToken],
        kind: ApiUpdate.UpdateTokens.Kind,
        removedSlugs: [String],
        isIncomplete: Bool = false,
        unpricedSlugs: Set<String> = []
    ) -> [String: ApiToken] {
        var tokens = currentTokens
        let defaultSlugs = Set(Self.defaultTokens.keys)

        if kind.isFull && !isIncomplete {
            let retainedSlugs = Set(newTokens.keys).union(defaultSlugs)
            tokens = tokens.filter { retainedSlugs.contains($0.key) }
        }
        for slug in removedSlugs where !defaultSlugs.contains(slug) {
            tokens[slug] = nil
        }
        for (slug, newToken) in newTokens {
            tokens[slug] = _merge(
                cached: currentTokens[slug],
                incoming: newToken,
                arePricesFresh: kind.arePricesFresh && !unpricedSlugs.contains(slug)
            )
        }

        return tokens
    }
    
    func _merge(cached: ApiToken?, incoming: ApiToken, arePricesFresh: Bool) -> ApiToken {
        guard let cached else { return incoming }

        let merged = ApiToken(
            slug: incoming.slug,
            name: incoming.name.nilIfEmpty ?? cached.name,
            // A missing localized name clears any value cached for the previous language.
            localizedName: incoming.localizedName?.nilIfEmpty,
            symbol: incoming.symbol.nilIfEmpty ?? cached.symbol,
            decimals: incoming.decimals.nilIfZero ?? cached.decimals,
            chain: incoming.chain,
            type: incoming.type ?? cached.type,
            tokenAddress: incoming.tokenAddress?.nilIfEmpty ?? cached.tokenAddress,
            tokenWalletAddress: incoming.tokenWalletAddress?.nilIfEmpty ?? cached.tokenWalletAddress,
            image: incoming.image?.nilIfEmpty ?? cached.image,
            isPopular: incoming.isPopular ?? cached.isPopular,
            keywords: incoming.keywords?.nilIfEmpty ?? cached.keywords,
            cmcSlug: incoming.cmcSlug?.nilIfEmpty ?? cached.cmcSlug,
            color: incoming.color?.nilIfEmpty ?? cached.color,
            isGaslessEnabled: incoming.isGaslessEnabled ?? cached.isGaslessEnabled,
            isStarsEnabled: incoming.isStarsEnabled ?? cached.isStarsEnabled,
            isTiny: incoming.isTiny ?? cached.isTiny,
            customPayloadApiUrl: incoming.customPayloadApiUrl?.nilIfEmpty ?? cached.customPayloadApiUrl,
            codeHash: incoming.codeHash?.nilIfEmpty ?? cached.codeHash,
            label: incoming.label?.nilIfEmpty ?? cached.label,
            isFromBackend: incoming.isFromBackend ?? cached.isFromBackend,
            priceUsd: arePricesFresh ? incoming.priceUsd ?? cached.priceUsd : cached.priceUsd ?? incoming.priceUsd,
            percentChange24h: arePricesFresh
                ? incoming.percentChange24h ?? cached.percentChange24h
                : cached.percentChange24h ?? incoming.percentChange24h
        )
        return merged
    }
    
    private func _applyFixups(tokens: inout [String: ApiToken]) {
        // Set potentially missing images
        if tokens[STAKED_MYCOIN_SLUG]?.image?.nilIfEmpty == nil {
            let image = tokens[MYCOIN_SLUG]!.image
            tokens[STAKED_MYCOIN_SLUG]?.image = image
        }
        if tokens[TRON_USDT_SLUG]?.image?.nilIfEmpty == nil {
            let image = tokens[TON_USDT_SLUG]!.image
            tokens[TRON_USDT_SLUG]?.image = image
        }
        if tokens[BSC_USDT_MAINNET_SLUG]?.image?.nilIfEmpty == nil {
            let image = tokens[TON_USDT_SLUG]!.image
            tokens[BSC_USDT_MAINNET_SLUG]?.image = image
        }
        if tokens[AVALANCHE_USDT_MAINNET_SLUG]?.image?.nilIfEmpty == nil {
            let image = tokens[TON_USDT_SLUG]!.image
            tokens[AVALANCHE_USDT_MAINNET_SLUG]?.image = image
        }
        if tokens[HYPERLIQUID_USDC_MAINNET_SLUG]?.image?.nilIfEmpty == nil {
            let image = tokens[SOLANA_USDC_MAINNET_SLUG]!.image
            tokens[HYPERLIQUID_USDC_MAINNET_SLUG]?.image = image
        }
    }
    
    // MARK: Base currency
    
    public func setBaseCurrency(currency: MBaseCurrency) async throws {
        await MainActor.run {
            AppStorageHelper.save(selectedCurrency: currency.rawValue)
        }
        self.baseCurrency = currency
        clearHistoryData()
        AppStorageHelper.save(baseCurrency: currency, tokens: tokens, currencyRates: self.currencyRates)
        WalletCoreData.notify(event: .baseCurrencyChanged(to: currency))
        scheduleSharedCacheUpdate(tokens: self.tokens, baseCurrency: currency, rates: self.currencyRates)
    }
    
    public func getCurrencyRate(_ currency: MBaseCurrency) -> Double {
        _currencyRates.withLock { $0[currency.rawValue]?.value } ?? currency.fallbackExchangeRate
    }
    
    // MARK: - Swap assets
    
    private func process(swapAssetsArray: [[String: Any]]) {
        do {
            let assets = try JSONSerialization.decode([ApiToken].self, from: swapAssetsArray)
            let hasMissingTonIdentifier = assets.contains {
                $0.chain == .ton && !$0.isNative && $0.tokenAddress?.nilIfEmpty == nil
            }
            guard !hasMissingTonIdentifier else {
                log.error("ignoring invalid swap assets cache")
                return
            }
            TokenStore.swapAssets = assets.sorted {
                $0.displayName(strippingLabelWhenShown: false) < $1.displayName(strippingLabelWhenShown: false)
            }
            DispatchQueue.main.async {
                WalletCoreData.notify(event: .swapTokensChanged)
            }
        } catch {
            log.error("failed to decode swap assets")
        }
    }
    
    // MARK: -
    
    public func clean() {
        self.tokens = Self.defaultTokens
        self.swapAssets = nil
        self.swapPairs = [:]
        clearTokenDetailsCache()
    }

    /// Resets downloaded token data to bundled defaults, preserving the selected base currency.
    public func clearCache() async {
        // Queue the reset behind pending updates and their disk writes so they cannot restore stale data.
        let task = updateTokensTask.withLock {
            let previousTask = $0
            let task = Task.detached { [self] in
                await previousTask?.value
                clean()
                currencyRates = [:]
                clearHistoryData()
                AppStorageHelper.clearTokenCaches()
                AppStorageHelper.save(baseCurrency: baseCurrency, tokens: tokens, currencyRates: currencyRates)
                await sharedCache.update(tokens: tokens, baseCurrency: baseCurrency, rates: currencyRates)
                startTokenDetailsMaintenance()
                WalletCoreData.notify(event: .tokensChanged)
                WalletCoreData.notify(event: .swapTokensChanged)
            }
            $0 = task
            return task
        }
        await task.value
    }
    
    internal static let defaultTokens: [String: ApiToken] = [
        TONCOIN_SLUG: .TONCOIN,
        TRX_SLUG: .TRX,
        SOLANA_SLUG: .SOLANA,
        BITCOIN_SLUG: .BITCOIN,
        LITECOIN_SLUG: .LITECOIN,
        BITCOINCASH_SLUG: .BITCOINCASH,
        DOGECOIN_SLUG: .DOGECOIN,
        MYCOIN_SLUG: .MYCOIN,
        TON_USDE_SLUG: .TON_USDE,
        STAKED_TON_SLUG: .STAKED_TON,
        STAKED_MYCOIN_SLUG: .STAKED_MYCOIN,
        TON_TSUSDE_SLUG: .TON_TSUSDE,
        TON_USDT_SLUG: .TON_USDT,
        TON_USDT_TESTNET_SLUG: .TON_USDT_TESTNET,
        TRON_USDT_SLUG: .TRON_USDT,
        TRON_USDT_TESTNET_SLUG: .TRON_USDT_TESTNET,
        SOLANA_USDT_MAINNET_SLUG: .SOLANA_USDT_MAINNET,
        SOLANA_USDC_MAINNET_SLUG: .SOLANA_USDC_MAINNET,
        ETH_SLUG: .ETH,
        ETH_USDT_MAINNET_SLUG: .ETH_USDT_MAINNET,
        ETH_USDC_MAINNET_SLUG: .ETH_USDC_MAINNET,
        BASE_SLUG: .BASE,
        BASE_USDT_MAINNET_SLUG: .BASE_USDT_MAINNET,
        BASE_USDC_MAINNET_SLUG: .BASE_USDC_MAINNET,
        BNB_SLUG: .BNB,
        BSC_USDT_MAINNET_SLUG: .BSC_USDT_MAINNET,
        POLYGON_SLUG: .POLYGON,
        ARBITRUM_SLUG: .ARBITRUM,
        MONAD_SLUG: .MONAD,
        AVALANCHE_SLUG: .AVALANCHE,
        AVALANCHE_USDT_MAINNET_SLUG: .AVALANCHE_USDT_MAINNET,
        HYPERLIQUID_SLUG: .HYPERLIQUID,
        HYPERLIQUID_USDC_MAINNET_SLUG: .HYPERLIQUID_USDC_MAINNET,
        ROBINHOOD_SLUG: .ROBINHOOD,
        ARC_SLUG: .ARC,
    ]

    // MARK: - Cached history data
    
    public struct HistoryData: Equatable, Hashable, Codable, Sendable {
        public var lastUpdated: Date
        public var data: [ApiPriceHistoryPeriod : [[Double]]?]
    }
    
    private let _historyData: UnfairLock<[String: HistoryData]> = .init(initialState: [:])
    public func historyData(tokenSlug: String) -> HistoryData? {
        if let data = _historyData.withLock({ $0[tokenSlug] }), abs(data.lastUpdated.timeIntervalSinceNow) < HISTORY_DATA_STALENESS {
            return data
        }
        return nil
    }
    public func setHistoryData(tokenSlug: String, data: [ApiPriceHistoryPeriod : [[Double]]?]) {
        let historyData = HistoryData(lastUpdated: .now, data: data)
        _historyData.withLock {
            $0[tokenSlug] = historyData
        }
    }
    private func clearHistoryData() {
        _historyData.withLock { $0 = [:] }
    }

    // MARK: - Cached token details

    public func cachedTokenDetails(tokenSlug: String) -> TokenDetailsCacheEntry? {
        let language = LocalizationSupport.shared.langCode
        let now = Date()
        return _tokenDetails.withLock {
            $0.cachedEntry(
                language: language,
                slug: tokenSlug,
                now: now,
                validity: TOKEN_DETAILS_CACHE_VALIDITY
            )
        }
    }

    public func setCachedTokenDetails(tokenSlug: String, details: ApiTokenDetails?) {
        storeCachedTokenDetails(
            accountId: AccountStore.currentAccountId,
            tokenSlug: tokenSlug,
            details: details
        )
    }

    public func refreshTokenDetails(accountId: String, token: ApiToken) async throws -> ApiTokenDetails? {
        let language = LocalizationSupport.shared.langCode
        rememberTokenDetails(accountId: accountId, slugs: [token.slug], promoteExisting: true)
        return try await requestTokenDetails(language: language, token: token)
    }

    private func storeCachedTokenDetails(accountId: String, tokenSlug: String, details: ApiTokenDetails?) {
        let language = LocalizationSupport.shared.langCode
        rememberTokenDetails(accountId: accountId, slugs: [tokenSlug], promoteExisting: true)
        updateTokenDetailsCache {
            $0.storing(
                language: language,
                slug: tokenSlug,
                details: details,
                fetchedAt: .now
            )
        }
    }

    private func loadTokenDetailsFromCache() {
        guard let loadedCache = AppStorageHelper.tokenDetailsCache() else { return }
        let sanitizedCache = loadedCache.sanitized(
            validAccountIds: Set(AccountStore.accountsById.keys),
            limit: TOKEN_DETAILS_CACHE_LIMIT_PER_ACCOUNT,
            now: .now,
            validity: TOKEN_DETAILS_CACHE_VALIDITY
        )
        _tokenDetails.withLock { $0 = sanitizedCache }
        if sanitizedCache != loadedCache {
            scheduleTokenDetailsPersistence()
        }
    }

    private func rememberTokenDetails(accountId: String, slugs: [String], promoteExisting: Bool) {
        updateTokenDetailsCache {
            $0.remembering(
                accountId: accountId,
                slugs: slugs,
                limit: TOKEN_DETAILS_CACHE_LIMIT_PER_ACCOUNT,
                promoteExisting: promoteExisting
            ).removingExpired(now: .now, validity: TOKEN_DETAILS_CACHE_VALIDITY)
        }
    }

    private func requestTokenDetails(language: String, token: ApiToken) async throws -> ApiTokenDetails? {
        let requestKey = "\(language):\(token.slug)"
        let request = tokenDetailsRequests.withLock { requests in
            if let existingRequest = requests[requestKey] {
                return existingRequest
            }
            let request = TokenDetailsRequest(
                id: UUID(),
                task: Task.detached(priority: .utility) {
                    try await Api.fetchTokenDetails(asset: token.swapIdentifier, slug: token.slug)
                }
            )
            requests[requestKey] = request
            return request
        }

        do {
            let details = try await request.task.value
            if finishTokenDetailsRequest(key: requestKey, id: request.id) {
                updateTokenDetailsCache {
                    $0.storing(
                        language: language,
                        slug: token.slug,
                        details: details,
                        fetchedAt: .now
                    )
                }
            }
            return details
        } catch {
            _ = finishTokenDetailsRequest(key: requestKey, id: request.id)
            throw error
        }
    }

    private func finishTokenDetailsRequest(key: String, id: UUID) -> Bool {
        tokenDetailsRequests.withLock { requests in
            guard requests[key]?.id == id else { return false }
            requests[key] = nil
            return true
        }
    }

    private func updateTokenDetailsCache(
        _ transform: @Sendable (TokenDetailsCache) -> TokenDetailsCache
    ) {
        let didUpdate = _tokenDetails.withLock { cache in
            let updatedCache = transform(cache)
            if updatedCache != cache {
                cache = updatedCache
                return true
            }
            return false
        }
        if didUpdate {
            scheduleTokenDetailsPersistence()
        }
    }

    private func scheduleTokenDetailsPreload() {
        guard DebugTokenInfoMock.preset == .disabled,
              isAppForeground.withLock({ $0 })
        else { return }
        tokenDetailsPreloadState.withLock { state in
            state.isPending = true
            guard state.request == nil else { return }
            let id = UUID()
            let task = Task { [weak self] in
                guard let self else { return }
                await self.runTokenDetailsPreloadWorker(id: id)
            }
            state.request = TokenDetailsPreloadRequest(id: id, task: task)
        }
    }

    private func runTokenDetailsPreloadWorker(id: UUID) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(0.3))
            } catch {
                break
            }
            let shouldRun = tokenDetailsPreloadState.withLock { state in
                guard state.request?.id == id else { return false }
                state.isPending = false
                return true
            }
            guard shouldRun else { return }

            await preloadTokenDetails()

            let shouldRunAgain = tokenDetailsPreloadState.withLock { state in
                guard state.request?.id == id else { return false }
                if state.isPending {
                    return true
                }
                state.request = nil
                return false
            }
            if !shouldRunAgain { return }
        }
        tokenDetailsPreloadState.withLock { state in
            guard state.request?.id == id else { return }
            state = TokenDetailsPreloadState()
        }
    }

    private func cancelTokenDetailsPreload() {
        tokenDetailsPreloadState.withLock { state in
            state.request?.task.cancel()
            state = TokenDetailsPreloadState()
        }
    }

    private func preloadTokenDetails() async {
        guard !Task.isCancelled,
              DebugTokenInfoMock.preset == .disabled,
              isAppForeground.withLock({ $0 }),
              let snapshot = await tokenDetailsPreloadSnapshot()
        else { return }

        rememberTokenDetails(
            accountId: snapshot.accountId,
            slugs: snapshot.tokens.map(\.slug),
            promoteExisting: false
        )
        for token in snapshot.tokens {
            guard !Task.isCancelled,
                  isAppForeground.withLock({ $0 }),
                  AccountStore.accountId == snapshot.accountId
            else { return }
            guard cachedTokenDetails(tokenSlug: token.slug) == nil else { continue }
            do {
                _ = try await requestTokenDetails(
                    language: LocalizationSupport.shared.langCode,
                    token: token
                )
            } catch is CancellationError {
                if Task.isCancelled { return }
            } catch {}
        }
    }

    @MainActor
    private func tokenDetailsPreloadSnapshot() -> TokenDetailsPreloadSnapshot? {
        guard let accountId = AccountStore.accountId,
              let tokenBalances = BalanceDataStore.walletTokensData(accountId: accountId)?.allTokenBalances
        else { return nil }

        var seenSlugs = Set<String>()
        let tokens = tokenBalances.compactMap { tokenBalance -> ApiToken? in
            guard !tokenBalance.isStaking,
                  seenSlugs.insert(tokenBalance.tokenSlug).inserted
            else { return nil }
            return self.tokens[tokenBalance.tokenSlug]
        }.prefix(TOKEN_DETAILS_PRELOAD_LIMIT)
        return TokenDetailsPreloadSnapshot(accountId: accountId, tokens: Array(tokens))
    }

    private func startTokenDetailsMaintenance() {
        tokenDetailsMaintenanceTask.withLock { task in
            guard task == nil else { return }
            task = Task.detached(priority: .background) { [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        return
                    }
                    guard let self, self.isAppForeground.withLock({ $0 }) else { continue }
                    self.scheduleTokenDetailsPreload()
                }
            }
        }
    }

    private func scheduleTokenDetailsPersistence() {
        guard isAppForeground.withLock({ $0 }) else {
            flushTokenDetailsPersistence()
            return
        }
        tokenDetailsPersistenceRequest.withLock { request in
            request?.task.cancel()
            let id = UUID()
            let task = Task.detached(priority: .background) { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(0.2))
                    try Task.checkCancellation()
                    guard let self else { return }
                    self.persistTokenDetails(id: id)
                } catch {}
            }
            request = TokenDetailsPersistenceRequest(id: id, task: task)
        }
    }

    private func persistTokenDetails(id: UUID) {
        guard !Task.isCancelled else { return }
        let cache = _tokenDetails.withLock { $0 }
        guard !Task.isCancelled else { return }
        tokenDetailsDiskAccess.withLock { _ in
            guard !Task.isCancelled,
                  tokenDetailsPersistenceRequest.withLock({ $0?.id == id })
            else { return }
            AppStorageHelper.save(tokenDetailsCache: cache)
        }
        tokenDetailsPersistenceRequest.withLock { request in
            if request?.id == id {
                request = nil
            }
        }
    }

    private func flushTokenDetailsPersistence() {
        tokenDetailsPersistenceRequest.withLock { request in
            request?.task.cancel()
            request = nil
        }
        tokenDetailsDiskAccess.withLock { _ in
            let cache = _tokenDetails.withLock { $0 }
            AppStorageHelper.save(tokenDetailsCache: cache)
        }
    }

    private func clearTokenDetailsCache() {
        cancelTokenDetailsPreload()
        tokenDetailsMaintenanceTask.withLock {
            $0?.cancel()
            $0 = nil
        }
        tokenDetailsRequests.withLock { requests in
            requests.values.forEach { $0.task.cancel() }
            requests.removeAll()
        }
        _tokenDetails.withLock { $0 = TokenDetailsCache() }
        flushTokenDetailsPersistence()
    }

    // MARK: - Shared Cache

    private func scheduleSharedCacheUpdate(
        tokens: [String: ApiToken]? = nil,
        baseCurrency: MBaseCurrency? = nil,
        rates: [String: MDouble]? = nil
    ) {
        guard tokens != nil || baseCurrency != nil || rates != nil else { return }
        Task.detached(priority: .background) { [sharedCache] in
            await sharedCache.update(
                tokens: tokens,
                baseCurrency: baseCurrency,
                rates: rates
            )
        }
    }
}


extension _TokenStore: WalletCoreData.EventsObserver {
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .updateCurrencyRates(let update):
            let oldBaseCurrencyRate = self.baseCurrencyRate
            self.currencyRates = update.rates
            if self.baseCurrencyRate != oldBaseCurrencyRate {
                WalletCoreData.notify(event: .tokensChanged)
            }
            scheduleSharedCacheUpdate(rates: update.rates)

        case .updateTokens(let dict):
            guard
                let kindString = dict["kind"] as? String,
                let kind = ApiUpdate.UpdateTokens.Kind(rawValue: kindString)
            else {
                log.fault("updateTokens missing or invalid kind")
                return
            }
            let removedSlugs = dict["removedSlugs"] as? [String] ?? []
            let isIncomplete = dict["isIncomplete"] as? Bool == true
            let unpricedSlugs = Set(dict["unpricedSlugs"] as? [String] ?? [])
            nonisolated(unsafe) let dict = dict
            self.updateTokensTask.withLock {
                let previousTask = $0
                $0 = Task.detached(priority: .low) {
                    await previousTask?.value
                    do {
                        let tokens = try (dict["tokens"] as? [String: Any]).orThrow().mapValues { try ApiToken(any: $0) }
                        await Task.yield()
                        try Task.checkCancellation()

                        self.process(
                            newTokens: tokens,
                            kind: kind,
                            removedSlugs: removedSlugs,
                            isIncomplete: isIncomplete,
                            unpricedSlugs: unpricedSlugs
                        )

                    } catch is CancellationError {
                    } catch {
                        log.fault("failed to decode updateTokens \(error, .public)")
                    }
                }
            }
        
        case .baseCurrencyChanged(to: let currency):
            if self.baseCurrency != currency {
                self.baseCurrency = currency
                clearHistoryData()
                WalletCoreData.notify(event: .tokensChanged)
                scheduleSharedCacheUpdate(tokens: self.tokens, baseCurrency: currency, rates: self.currencyRates)
            }
            scheduleTokenDetailsPreload()

        case .updateSwapTokens(let update):
            updateTokensTask.withLock {
                let previousTask = $0
                $0 = Task.detached(priority: .background) {
                    await previousTask?.value
                    let tokens: [ApiToken] = update.tokens.values.sorted {
                        $0.displayName(strippingLabelWhenShown: false) < $1.displayName(strippingLabelWhenShown: false)
                    }
                    AppStorageHelper.save(swapAssetsArray: tokens)
                    self.swapAssets = tokens
                    WalletCoreData.notify(event: .swapTokensChanged)
                }
            }

        case .tokensChanged, .assetsAndActivityDataUpdated:
            scheduleTokenDetailsPreload()

        case .balanceChanged(let accountId):
            if accountId == AccountStore.accountId {
                scheduleTokenDetailsPreload()
            }

        case .accountChanged:
            scheduleTokenDetailsPreload()

        case .accountDeleted(let accountId):
            updateTokenDetailsCache { $0.removingAccount(accountId) }

        case .applicationWillEnterForeground:
            isAppForeground.withLock { $0 = true }
            scheduleTokenDetailsPreload()

        case .applicationDidEnterBackground:
            isAppForeground.withLock { $0 = false }
            cancelTokenDetailsPreload()
            flushTokenDetailsPersistence()

        case .accountsReset:
            clearTokenDetailsCache()

        default:
            break
        }
    }
}

extension _TokenStore: DependencyKey {
    public static var liveValue: _TokenStore { shared }
}

extension DependencyValues {
    public var tokenStore: _TokenStore {
        self[_TokenStore.self]
    }
}



extension AppStorageHelper {
    // MARK: - Tokens dict
    private static let tokensCurrencyKey = "cache.tokens.currency"
    private static let tokensKey = "cache.tokens"
    private static let currencyRatesKey = "cache.currencyRates"
    private static let tokenDetailsCacheURL = URL.cachesDirectory
        .appending(components: "air", "token-details-cache.json")
    
    fileprivate static func save(baseCurrency: MBaseCurrency, tokens: [String: ApiToken], currencyRates: [String: MDouble]) {
        UserDefaults.standard.set(baseCurrency.rawValue, forKey: tokensCurrencyKey)
        if let data = try? JSONEncoder().encode(tokens) {
            UserDefaults.standard.set(data, forKey: AppStorageHelper.tokensKey)
        }
        if let data = try? JSONEncoder().encode(currencyRates) {
            UserDefaults.standard.set(data, forKey: AppStorageHelper.currencyRatesKey)
        }
    }
    
    fileprivate static func tokensCurrency() -> MBaseCurrency? {
        if let data = UserDefaults.standard.string(forKey: tokensCurrencyKey) {
            return MBaseCurrency(rawValue: data)
        }
        return nil
    }
    
    fileprivate static func tokensDict() -> [String: ApiToken]? {
        if let data = UserDefaults.standard.data(forKey: AppStorageHelper.tokensKey),
           let tokens = try? JSONDecoder().decode([String:ApiToken].self, from: data) {
            return tokens
        }
        return nil
    }
    
    fileprivate static func currencyRatesDict() -> [String: MDouble]? {
        if let data = UserDefaults.standard.data(forKey: AppStorageHelper.currencyRatesKey),
           let currencyRates = try? JSONDecoder().decode([String: MDouble].self, from: data) {
            return currencyRates
        }
        return nil
    }

    fileprivate static func save(tokenDetailsCache: TokenDetailsCache) {
        guard !tokenDetailsCache.recentSlugsByAccountId.isEmpty else {
            try? FileManager.default.removeItem(at: tokenDetailsCacheURL)
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: tokenDetailsCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(tokenDetailsCache)
            try data.write(to: tokenDetailsCacheURL, options: .atomic)
        } catch {
            log.error("failed to save token details cache \(error, .public)")
        }
    }

    fileprivate static func tokenDetailsCache() -> TokenDetailsCache? {
        guard FileManager.default.fileExists(atPath: tokenDetailsCacheURL.path()) else { return nil }
        do {
            let data = try Data(contentsOf: tokenDetailsCacheURL)
            return try JSONDecoder().decode(TokenDetailsCache.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: tokenDetailsCacheURL)
            log.error("failed to decode token details cache \(error, .public)")
            return nil
        }
    }
    
    // MARK: - SwapAssets dict
    private static let swapAssetsArrayKey = "cache.swapAssets"

    fileprivate static func clearTokenCaches() {
        for key in [tokensKey, currencyRatesKey, swapAssetsArrayKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    public static func save(swapAssetsArray: [ApiToken]) {
        if let data = try? JSONSerialization.encode(swapAssetsArray) {
            UserDefaults.standard.set(data, forKey: AppStorageHelper.swapAssetsArrayKey)
        }
    }
    public static func swapAssetsArray() -> [[String: Any]]? {
        return UserDefaults.standard.value(forKey: AppStorageHelper.swapAssetsArrayKey) as? [[String: Any]]
    }
}
