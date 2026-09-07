package org.mytonwallet.app_air.uibrowser.viewControllers.explore

import android.os.Handler
import android.os.Looper
import androidx.annotation.MainThread
import androidx.core.net.toUri
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.coroutines.CoroutineContext
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.yield
import org.mytonwallet.app_air.uiagent.processors.AgentHint
import org.mytonwallet.app_air.uiagent.search.AgentSearchSuggestions
import org.mytonwallet.app_air.uibrowser.search.AppSearchEntries
import org.mytonwallet.app_air.uibrowser.search.AppSearchEntry
import org.mytonwallet.app_air.uibrowser.search.TokenSearchMatching
import org.mytonwallet.app_air.uibrowser.search.UniversalSearchQuery
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.ALL_DEFAULT_TOKENS
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.loadExploreSites
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MCollectionTabToShow
import org.mytonwallet.app_air.walletcore.models.MExploreCategory
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.IDapp
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.DappsStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class ExploreVM(delegate: Delegate) : WalletCore.EventObserver {
    companion object {
        private const val SEARCH_SECTION_ITEMS_LIMIT = 9
        private const val SEARCH_REFRESH_DEBOUNCE_MS = 400L
        private val WORK_PARALLELISM =
            Runtime.getRuntime().availableProcessors().coerceIn(2, 8)
        private val TRENDING_TOKEN_SLUGS = mapOf(
            MBlockchainNetwork.MAINNET to
                (
                    listOf(MYCOIN_SLUG) +
                        ALL_DEFAULT_TOKENS[MBlockchainNetwork.MAINNET].orEmpty()
                    ).distinct(),
            MBlockchainNetwork.TESTNET to
                ALL_DEFAULT_TOKENS[MBlockchainNetwork.TESTNET].orEmpty()
        )
    }

    interface Delegate {
        fun updateEmptyView()
        fun sitesUpdated()
        fun accountChanged()
    }

    private val delegate: WeakReference<Delegate> = WeakReference(delegate)
    private val searchScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // Read from warm-up workers on the Default pool as well as the main thread.
    @Volatile
    private var searchJob: Job? = null

    private var waitingForNetwork = false
    internal var connectedSites: Array<ApiDapp>? =
        DappsStore.dApps[AccountStore.activeAccountId]?.toTypedArray()
    var allSites: List<MExploreSite>? = null
        private set
    private var allExploreCategories: List<MExploreCategory>? = null

    internal var showingExploreCategories: List<MExploreCategory>? = null
    internal var showingTrendingSites = listOf<MExploreSite>()

    private data class ExploreHistorySnapshot(
        val searchHistory: List<MExploreHistory.HistoryItem>,
        val visitedSites: List<MExploreHistory.VisitedSite>,
        val recentTokenSlugs: List<String>
    )

    private data class ActiveSearchRequest(
        val keyword: String,
        val enhancedSearchEnabled: Boolean,
        val onResult: (SearchResult) -> Unit
    )

    private data class WalletInfoSearchRequest(val pendingChains: MutableSet<MBlockchain>)

    private var activeSearchRequest: ActiveSearchRequest? = null
    private var searchRefreshJob: Job? = null
    private var walletInfoSearchRequest: WalletInfoSearchRequest? = null

    fun delegateIsReady() {
        WalletCore.registerObserver(this)
        if (!WalletCore.isConnected()) {
            waitingForNetwork = true
        }
        warmUpTokenSearch()
        refresh()
    }

    @Volatile
    private var warmUpJob: Job? = null

    @Volatile
    private var tokenCatalogFingerprint: Long = 0L

    /**
     * Order-independent digest of every token's searchable fields and popularity, which gates
     * matching on unsupported chains. Prices are excluded on purpose: they arrive with most
     * TokensChanged events and do not affect matching.
     */
    private fun computeTokenCatalogFingerprint(): Long {
        var hash = 0L
        TokenStore.tokens.forEach { (slug, token) ->
            hash += slug.hashCode().toLong() * 31 +
                TokenSearchMatching.searchableFieldsHash(token) +
                (if (token.isPopular) 1 else 0)
        }
        hash += (TokenStore.swapAssets?.size ?: 0).toLong() * 1_000_003L
        return hash
    }

    /**
     * The first catalog-wide token match pays for normalizing every token's searchable fields, so
     * build those caches ahead of the first keystroke, spread over the Default pool. TokensChanged
     * fires in bursts during startup, and concurrent warm-ups duplicate the whole normalization
     * pass while competing with the search build for CPU — hence one run at a time.
     */
    @MainThread
    private fun warmUpTokenSearch(restartIfRunning: Boolean = false) {
        // Main-thread-only mutation keeps the check-and-replace race-free without a lock.
        val previous = warmUpJob?.takeIf { it.isActive }
        // A running warm-up normalizes the fields it read at launch; when the catalog really
        // changed underneath it, its output is stale and only a fresh pass helps.
        if (previous != null && !restartIfRunning) return
        warmUpJob = searchScope.launch(Dispatchers.Default) {
            previous?.cancelAndJoin()
            tokenCatalogFingerprint = computeTokenCatalogFingerprint()
            val tokens = TokenStore.tokens.values +
                TokenStore.swapAssets.orEmpty().mapNotNull { TokenStore.getToken(it.slug) }
            // Half the pool and a yield per batch keep warm-up from starving an interactive
            // search that lands while it runs.
            val workers = (WORK_PARALLELISM / 2).coerceAtLeast(1)
            val chunkSize = (tokens.size + workers - 1) / workers
            if (chunkSize > 0) {
                // The substring phase pays inline for any haystack that is not ready yet, so
                // those come first, at full speed; only then the far costlier fuzzy documents.
                coroutineScope {
                    tokens.chunked(chunkSize).map { chunk ->
                        async {
                            chunk.chunked(256).forEach { batch ->
                                TokenSearchMatching.warmUpHaystacks(batch)
                                yield()
                            }
                        }
                    }.awaitAll()
                }
                // The candidate list and joined index are what the instant substring phase
                // actually reads — build them here so the first keystroke never pays for them.
                substringIndex(currentCoroutineContext())
                coroutineScope {
                    tokens.chunked(chunkSize).map { chunk ->
                        async {
                            // Small batches so the pause engages within a few tokens' work.
                            chunk.chunked(16).forEach { batch ->
                                // Warm-up has no deadline: hand the whole pool to an active
                                // search build instead of making it queue behind these batches.
                                while (searchJob?.isActive == true) {
                                    delay(25.milliseconds)
                                }
                                TokenSearchMatching.warmUp(batch)
                                yield()
                            }
                        }
                    }.awaitAll()
                }
            }
        }
    }

    fun onDestroy() {
        cancelSearch()
        searchScope.cancel()
        WalletCore.unregisterObserver(this)
    }

    private fun refresh() {
        WalletCore.loadExploreSites { categories, sites, error ->
            if (error != null) {
                if (!waitingForNetwork) {
                    Handler(Looper.getMainLooper()).postDelayed({
                        refresh()
                    }, 3000)
                }
            } else {
                updateSites(categories, sites)
            }
        }
    }

    private fun updateSites(categories: List<MExploreCategory>?, sites: List<MExploreSite>?) {
        this.allSites = sites
        allExploreCategories = categories
        filterAndShowSites()
    }

    private fun filterAndShowSites() {
        showingExploreCategories = allExploreCategories?.filter {
            it.sites.any { it.canBeShown }
        }
        showingTrendingSites =
            allSites?.filter { it.isFeatured && it.canBeShown } ?: emptyList()
        delegate.get()?.updateEmptyView()
        delegate.get()?.sitesUpdated()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.NetworkConnected -> {
                refresh()
            }

            WalletEvent.NetworkDisconnected -> {
                waitingForNetwork = true
            }

            WalletEvent.DappsCountUpdated -> {
                connectedSites = DappsStore.dApps[AccountStore.activeAccountId]?.toTypedArray()
                delegate.get()?.updateEmptyView()
                delegate.get()?.sitesUpdated()
            }

            WalletEvent.ConfigReceived -> {
                delegate.get()?.updateEmptyView()
                delegate.get()?.sitesUpdated()
            }

            is WalletEvent.AccountChangedInApp -> {
                delegate.get()?.accountChanged()
            }

            WalletEvent.TokensChanged -> {
                // Mostly price updates: rebuild the match caches only when searchable fields
                // (localized names included) actually changed, not on every event.
                searchScope.launch {
                    val fingerprint = withContext(Dispatchers.Default) {
                        computeTokenCatalogFingerprint()
                    }
                    if (fingerprint != tokenCatalogFingerprint) {
                        tokenCatalogFingerprint = fingerprint
                        invalidateTokenMatchCache()
                        warmUpTokenSearch(restartIfRunning = true)
                    }
                }
                scheduleSearchRefresh()
            }

            WalletEvent.BalanceChanged,
            WalletEvent.NftsUpdated -> {
                scheduleSearchRefresh()
            }

            else -> {}
        }
    }

    // A match against one of the user's own added wallet accounts.
    data class MyWalletMatch(
        val account: MAccount,
        val chain: MBlockchain?,
        val address: String?,
        val isFullMatch: Boolean
    )

    // A well-known address/domain resolved through the API for an unknown wallet.
    data class WalletInfoMatch(
        val network: MBlockchainNetwork,
        val chain: MBlockchain,
        val inputAddressOrDomain: String,
        val address: String,
        val name: String?,
        val domain: String?
    )

    sealed interface CollectibleMatch {
        data class Nft(val nft: ApiNft) : CollectibleMatch
        data class Collection(val collection: MCollectionTabToShow) : CollectibleMatch
    }

    data class SearchResult(
        val keyword: String,
        val recentChats: List<AgentHint>? = null,
        val suggestedChats: List<AgentHint>? = null,
        val matchedVisitedSite: MExploreHistory.VisitedSite? = null,
        val recentSearches: List<MExploreHistory.HistoryItem>? = null,
        val recentVisitedSites: List<MExploreHistory.VisitedSite>? = null,
        val tokens: List<MTokenBalance>? = null,
        val recentTokens: List<MTokenBalance>? = null,
        val trendingTokens: List<MTokenBalance>? = null,
        val collectibles: List<CollectibleMatch>? = null,
        val dapps: List<IDapp>? = null,
        val recentDapps: List<IDapp>? = null,
        val trendingDapps: List<IDapp>? = null,
        val actions: List<AppSearchEntry>? = null,
        val settings: List<AppSearchEntry>? = null,
        val myWallets: List<MyWalletMatch>? = null,
        val walletInfo: WalletInfoMatch? = null,
        val isWalletInfoLookupPending: Boolean = false,
        val noResultsFound: Boolean = false
    )

    fun search(keyword: String, enhancedSearchEnabled: Boolean, onResult: (SearchResult) -> Unit) {
        searchRefreshJob?.cancel()
        searchRefreshJob = null
        searchJob?.cancel()
        walletInfoSearchRequest = null
        currentSearchKeyword = keyword
        activeSearchRequest = ActiveSearchRequest(keyword, enhancedSearchEnabled, onResult)

        val job = searchScope.launch(start = CoroutineStart.LAZY) {
            val currentJob = currentCoroutineContext()[Job]
            val history = ExploreHistoryStore.exploreHistory
            val historySnapshot = ExploreHistorySnapshot(
                searchHistory = history?.searchHistory?.toList().orEmpty(),
                visitedSites = history?.visitedSites?.toList().orEmpty(),
                recentTokenSlugs = history?.recentTokenSlugs().orEmpty()
            )
            val result = withContext(Dispatchers.Default) {
                buildSearchResult(keyword, enhancedSearchEnabled, historySnapshot)
            }
            if (searchJob !== currentJob) return@launch

            onResult(result)

            if (enhancedSearchEnabled && keyword.isEmpty()) {
                val suggestedChats = AgentSearchSuggestions.suggested()
                if (searchJob !== currentJob) return@launch
                if (suggestedChats != result.suggestedChats) {
                    onResult(result.copy(suggestedChats = suggestedChats))
                }
            }

            if (searchJob === currentJob) searchJob = null
        }
        searchJob = job
        job.start()
    }

    fun cancelSearch() {
        searchRefreshJob?.cancel()
        searchRefreshJob = null
        searchJob?.cancel()
        searchJob = null
        activeSearchRequest = null
        walletInfoSearchRequest = null
        currentSearchKeyword = null
    }

    /**
     * Wallet data updates arrive in bursts while polling runs, so collapse them into a single
     * rebuild instead of restarting the search (and its address lookups) on every event.
     */
    private fun scheduleSearchRefresh() {
        if (activeSearchRequest?.enhancedSearchEnabled != true) return
        if (searchRefreshJob?.isActive == true) return
        searchRefreshJob = searchScope.launch {
            delay(SEARCH_REFRESH_DEBOUNCE_MS.milliseconds)
            // Restarting cancels the running build, and with events arriving faster than a build
            // completes that starves the list of any result at all — so wait for the in-flight
            // search to deliver before rebuilding. A keystroke cancels this wait via search().
            while (searchJob?.isActive == true) {
                searchJob?.join()
            }
            val request = activeSearchRequest ?: return@launch
            if (!request.enhancedSearchEnabled) return@launch
            searchRefreshJob = null
            search(request.keyword, request.enhancedSearchEnabled, request.onResult)
        }
    }

    private suspend fun buildSearchResult(
        keyword: String,
        enhancedSearchEnabled: Boolean,
        historySnapshot: ExploreHistorySnapshot
    ): SearchResult {
        val searchContext = currentCoroutineContext()
        val recentChats = if (enhancedSearchEnabled && keyword.isEmpty()) {
            AgentSearchSuggestions.recent()
        } else {
            emptyList()
        }
        val matchedVisitedSite = exactMatch(keyword, historySnapshot.visitedSites, searchContext)
        val recentSearches = recentSearches(keyword, historySnapshot.searchHistory, searchContext)
        val sectionItemsLimit = if (enhancedSearchEnabled) SEARCH_SECTION_ITEMS_LIMIT else 5
        val recentVisitedSites = visitedSites(
            keyword,
            sectionItemsLimit,
            historySnapshot.visitedSites,
            searchContext
        )
        val tokens = if (enhancedSearchEnabled) {
            filterTokens(keyword, searchContext, includeFuzzyTokens = true)
        } else {
            emptyList()
        }
        val recentTokens = if (enhancedSearchEnabled && keyword.isEmpty()) {
            recentTokens(historySnapshot.recentTokenSlugs, searchContext)
        } else {
            emptyList()
        }
        val trendingTokens = if (enhancedSearchEnabled && keyword.isEmpty()) {
            trendingTokens(searchContext)
        } else {
            emptyList()
        }
        val collectibles = if (enhancedSearchEnabled) {
            filterCollectibles(keyword, searchContext)
        } else {
            emptyList()
        }
        val dapps = filterDapps(keyword, sectionItemsLimit, searchContext)
        val recentDapps = if (enhancedSearchEnabled && keyword.isEmpty()) {
            recentDapps(historySnapshot.visitedSites, searchContext)
        } else {
            emptyList()
        }
        val trendingDapps = if (enhancedSearchEnabled && keyword.isEmpty()) {
            trendingDapps(searchContext)
        } else {
            emptyList()
        }
        val actions = if (enhancedSearchEnabled) {
            filterAppEntries(AppSearchEntries.actions, keyword, searchContext)
        } else {
            emptyList()
        }
        val settings = if (enhancedSearchEnabled) {
            filterAppEntries(AppSearchEntries.settings, keyword, searchContext)
        } else {
            emptyList()
        }
        val myWallets = matchOwnWallets(keyword, searchContext)
        searchContext.ensureActive()
        val noResultsFound = !keyword.isEmpty() &&
            matchedVisitedSite == null &&
            recentSearches.isNullOrEmpty() &&
            recentVisitedSites.isNullOrEmpty() &&
            tokens.isEmpty() &&
            collectibles.isEmpty() &&
            myWallets.isEmpty() &&
            dapps.isEmpty() &&
            actions.isEmpty() &&
            settings.isEmpty()
        return SearchResult(
            keyword = keyword,
            recentChats = recentChats,
            suggestedChats = emptyList(),
            matchedVisitedSite = matchedVisitedSite,
            recentSearches = if (noResultsFound) {
                listOf(
                    MExploreHistory.HistoryItem(keyword, null)
                )
            } else {
                recentSearches
            },
            recentVisitedSites = recentVisitedSites,
            tokens = tokens,
            recentTokens = recentTokens,
            trendingTokens = trendingTokens,
            collectibles = collectibles,
            dapps = dapps,
            recentDapps = recentDapps,
            trendingDapps = trendingDapps,
            actions = actions,
            settings = settings,
            myWallets = myWallets,
            walletInfo = null,
            isWalletInfoLookupPending = shouldLookupWalletInfo(keyword, myWallets),
            noResultsFound = noResultsFound
        )
    }

    private fun matchOwnWallets(
        query: String,
        searchContext: CoroutineContext
    ): List<MyWalletMatch> {
        val keyword = query.lowercase()
        if (keyword.isEmpty()) return emptyList()

        val items = WGlobalStorage.accountIds().mapNotNull { accountId ->
            searchContext.ensureActive()
            val account = AccountStore.accountById(accountId) ?: return@mapNotNull null
            matchOwnWallet(account, keyword, searchContext)
        }

        // Full matches first (preserving account order) so the composer promotes one to the top match.
        return items.filter { it.isFullMatch } + items.filter { !it.isFullMatch }
    }

    private fun matchOwnWallet(
        account: MAccount,
        keyword: String,
        searchContext: CoroutineContext
    ): MyWalletMatch? {
        val minimalAcceptableAddressMatchCount = 4
        val minimalAcceptableDomainMatchCount = 1
        val nameLower = account.name.takeIf { it.isNotEmpty() }?.lowercase()

        var isPartial = false
        var isFull = false
        var matchedChain: MBlockchain? = null
        var matchedAddress: String? = null

        if (nameLower != null) {
            if (nameLower == keyword) {
                isFull = true
                isPartial = true
            } else if (nameLower.contains(keyword)) {
                isPartial = true
            }
        }

        run chains@{
            account.byChain.forEach { (chainName, info) ->
                searchContext.ensureActive()
                val addressLower = info.address.lowercase()
                val domainLower = info.domain?.lowercase()
                val chain = MBlockchain.valueOfOrNull(chainName)

                if (addressLower == keyword || domainLower == keyword) {
                    isFull = true
                    isPartial = true
                    matchedChain = chain
                    matchedAddress = info.address
                    return@chains
                }

                val addressMatched = addressLower.contains(keyword) &&
                    keyword.length >= minimalAcceptableAddressMatchCount
                val domainMatched = (domainLower?.contains(keyword) ?: false) &&
                    keyword.length >= minimalAcceptableDomainMatchCount
                if (addressMatched || domainMatched) {
                    isPartial = true
                    if (matchedChain == null) {
                        matchedChain = chain
                        matchedAddress = info.address
                    }
                }
            }
        }

        if (!isPartial) return null

        // Matched only by name: fall back to the account's primary chain for display.
        val chain = matchedChain ?: account.firstChain
        val address = matchedAddress ?: account.firstAddress
        return MyWalletMatch(account, chain, address, isFull)
    }

    @Volatile
    var currentSearchKeyword: String? = null
        private set

    fun searchWalletInfo(result: SearchResult, onResult: (SearchResult) -> Unit) {
        val keyword = result.keyword
        currentSearchKeyword = keyword
        walletInfoSearchRequest = null

        if (!result.isWalletInfoLookupPending) return

        val account = AccountStore.activeAccount
            ?: return onResult(result.copy(isWalletInfoLookupPending = false))
        val network = account.network
        val compatibleChains = compatibleWalletChains(keyword)
        if (compatibleChains.isEmpty()) {
            onResult(result.copy(isWalletInfoLookupPending = false))
            return
        }

        val request = WalletInfoSearchRequest(compatibleChains.toMutableSet())
        walletInfoSearchRequest = request
        compatibleChains.forEach { chain ->
            WalletCore.call(
                ApiMethod.WalletData.GetAddressInfo(chain, network, keyword)
            ) { info, err ->
                if (walletInfoSearchRequest !== request) return@call
                request.pendingChains.remove(chain)

                val isDomain = chain.isValidDNS(keyword)
                val resolved = info?.resolvedAddress?.takeIf { it.isNotEmpty() }
                val address = if (info != null && err == null && info.error == null) {
                    when {
                        resolved != null -> resolved
                        !isDomain -> keyword
                        else -> null
                    }
                } else {
                    null
                }

                if (address != null) {
                    walletInfoSearchRequest = null
                    onResult(
                        result.copy(
                            recentSearches = if (result.noResultsFound) {
                                emptyList()
                            } else {
                                result.recentSearches
                            },
                            noResultsFound = false,
                            walletInfo = WalletInfoMatch(
                                network = network,
                                chain = chain,
                                inputAddressOrDomain = keyword,
                                address = address,
                                name = info?.addressName?.takeIf { it.isNotEmpty() },
                                domain = if (isDomain) keyword else null
                            ),
                            isWalletInfoLookupPending = false
                        )
                    )
                } else if (request.pendingChains.isEmpty()) {
                    walletInfoSearchRequest = null
                    onResult(result.copy(isWalletInfoLookupPending = false))
                }
            }
        }
    }

    private fun shouldLookupWalletInfo(keyword: String, myWallets: List<MyWalletMatch>): Boolean =
        keyword.isNotEmpty() &&
            myWallets.none { it.isFullMatch } &&
            AccountStore.activeAccount != null &&
            compatibleWalletChains(keyword).isNotEmpty()

    private fun compatibleWalletChains(keyword: String): List<MBlockchain> =
        MBlockchain.supportedChains.filter {
            it.isValidAddress(keyword) || it.isValidDNS(keyword)
        }

    private fun exactMatch(
        query: String,
        visitedSites: List<MExploreHistory.VisitedSite>,
        searchContext: CoroutineContext
    ): MExploreHistory.VisitedSite? {
        val keyword = query.lowercase()
        if (keyword.isEmpty()) return null
        val exactMatchItem = visitedSites.firstOrNull {
            searchContext.ensureActive()
            it.url.toUri().host?.lowercase()?.startsWith(keyword) == true ||
                it.url.lowercase().startsWith(keyword)
        }
        return exactMatchItem?.copy(
            favicon = allSites?.find { site ->
                searchContext.ensureActive()
                site.url?.toUri()?.host == exactMatchItem.url.toUri().host
            }?.iconUrl ?: exactMatchItem.favicon
        )
    }

    private fun recentSearches(
        query: String,
        searchHistory: List<MExploreHistory.HistoryItem>,
        searchContext: CoroutineContext
    ): List<MExploreHistory.HistoryItem>? {
        val keyword = query.lowercase()
        return searchHistory
            .filter {
                searchContext.ensureActive()
                it.title.lowercase().contains(keyword)
            }
            .sortedWith(
                compareByDescending {
                    searchContext.ensureActive()
                    it.title.lowercase().startsWith(keyword)
                }
            )
            .take(10)
    }

    private fun visitedSites(
        query: String,
        itemsLimit: Int,
        visitedSites: List<MExploreHistory.VisitedSite>,
        searchContext: CoroutineContext
    ): List<MExploreHistory.VisitedSite>? {
        val keyword = query.lowercase()
        return visitedSites
            .filter {
                searchContext.ensureActive()
                it.title.lowercase().contains(keyword) ||
                    it.url.lowercase().contains(keyword)
            }
            .sortedWith(
                compareByDescending {
                    searchContext.ensureActive()
                    it.title.lowercase().startsWith(keyword) ||
                        it.url.lowercase().startsWith(keyword)
                }
            )
            .take(itemsLimit)
            .map { visitedSite ->
                searchContext.ensureActive()
                visitedSite.copy(
                    favicon = allSites?.find { site ->
                        searchContext.ensureActive()
                        site.url?.toUri()?.host == visitedSite.url.toUri().host
                    }?.iconUrl ?: visitedSite.favicon
                )
            }
    }

    /**
     * Matching scans the whole token catalog with fuzzy comparison — far too expensive to repeat
     * when the keyword has not changed (store-event refreshes re-run the same query). Balances are
     * intentionally left out: they change often and are re-applied on every call.
     */
    private class TokenMatchCache(
        val fingerprint: Long,
        val keyword: String,
        val accountId: String,
        val matched: List<MToken>,
        val exactSlugs: Set<String>,
        val includesFuzzy: Boolean
    )

    @Volatile
    private var tokenMatchCache: TokenMatchCache? = null

    /** The deduplicated catalog + swap-asset candidate list, rebuilt only when the catalog is. */
    private class TokenCandidatesCache(val fingerprint: Long, val candidates: List<MToken>)

    @Volatile
    private var tokenCandidatesCache: TokenCandidatesCache? = null

    /**
     * Every candidate haystack joined into one string, so a substring pass is a few native
     * `indexOf` scans instead of a per-token loop (whose per-element overhead dominates it).
     * NUL separators guarantee a keyword never matches across two tokens.
     *
     * Each cache above and this index carry the catalog fingerprint they were built from, and a
     * read rejects a mismatched entry: a build racing an invalidation can publish a stale value,
     * but the next read discards it instead of serving it for the rest of the session.
     */
    private class TokenSubstringIndex(
        val fingerprint: Long,
        val tokens: List<MToken>,
        private val joined: String,
        private val starts: IntArray
    ) {
        fun match(keywordLower: String): List<MToken> {
            val matched = ArrayList<MToken>()
            var position = joined.indexOf(keywordLower)
            while (position >= 0) {
                // The token whose segment contains this hit: the last start at or before it.
                var low = 0
                var high = starts.size - 1
                while (low < high) {
                    val middle = (low + high + 1) ushr 1
                    if (starts[middle] <= position) low = middle else high = middle - 1
                }
                matched.add(tokens[low])
                val nextSegment = if (low + 1 < starts.size) starts[low + 1] else joined.length
                position = joined.indexOf(keywordLower, nextSegment)
            }
            return matched
        }
    }

    @Volatile
    private var tokenSubstringIndex: TokenSubstringIndex? = null

    private fun substringIndex(searchContext: CoroutineContext): TokenSubstringIndex {
        val fingerprint = tokenCatalogFingerprint
        tokenSubstringIndex?.takeIf { it.fingerprint == fingerprint }?.let { return it }
        val tokens = tokenCandidates(searchContext)
        val starts = IntArray(tokens.size)
        val joined = buildString {
            tokens.forEachIndexed { index, token ->
                starts[index] = length
                append(TokenSearchMatching.haystackOf(token))
                append(Char(0))
            }
        }
        return TokenSubstringIndex(fingerprint, tokens, joined, starts)
            .also { tokenSubstringIndex = it }
    }

    internal fun invalidateTokenMatchCache() {
        tokenMatchCache = null
        tokenCandidatesCache = null
        tokenSubstringIndex = null
    }

    private fun tokenCandidates(searchContext: CoroutineContext): List<MToken> {
        val fingerprint = tokenCatalogFingerprint
        tokenCandidatesCache?.takeIf { it.fingerprint == fingerprint }?.let { return it.candidates }
        val candidates = LinkedHashMap(TokenStore.tokens)
        TokenStore.swapAssets.orEmpty().forEach { asset ->
            searchContext.ensureActive()
            TokenStore.getToken(asset.slug)?.let { token ->
                candidates.putIfAbsent(token.slug, token)
            }
        }
        return candidates.values.toList().also {
            tokenCandidatesCache = TokenCandidatesCache(fingerprint, it)
        }
    }

    /**
     * The fuzzy pass costs hundreds of milliseconds across the catalog on one core, so the scan
     * is split over the Default pool. Chunk order is preserved, so the outcome matches a
     * sequential filter.
     */
    private suspend fun matchTokens(
        account: MAccount,
        keywordLower: String,
        looseQuery: UniversalSearchQuery,
        includeFuzzy: Boolean
    ): List<MToken> {
        if (!includeFuzzy) {
            // The joined index turns the substring pass into a few native string scans, immune
            // to per-token overhead and to pool contention from warm-up batches.
            val searchContext = currentCoroutineContext()
            return substringIndex(searchContext).match(keywordLower).filter { token ->
                searchContext.ensureActive()
                isSearchable(account, token)
            }
        }
        return coroutineScope {
            val tokens = tokenCandidates(currentCoroutineContext())
            val chunkSize = (tokens.size + WORK_PARALLELISM - 1) / WORK_PARALLELISM
            if (chunkSize == 0) return@coroutineScope emptyList()
            tokens.chunked(chunkSize).map { chunk ->
                async(Dispatchers.Default) {
                    val chunkContext = currentCoroutineContext()
                    chunk.filter { token ->
                        chunkContext.ensureActive()
                        isSearchable(account, token) &&
                            (
                                TokenSearchMatching.matchesSubstring(token, keywordLower) ||
                                    // Substring matching alone misses typos and non-Latin
                                    // spellings, so give the ranker the fuzzy and transliterated
                                    // candidates too.
                                    TokenSearchMatching.matchesLoosely(token, looseQuery)
                                )
                    }
                }
            }.awaitAll().flatten()
        }
    }

    /** Popular tokens stay searchable on wallets without their chain. */
    private fun isSearchable(account: MAccount, token: MToken): Boolean =
        token.isPopular || account.isChainSupported(token.chain)

    private suspend fun filterTokens(
        query: String,
        searchContext: CoroutineContext,
        includeFuzzyTokens: Boolean
    ): List<MTokenBalance> {
        val keyword = query.trim()
        if (keyword.isEmpty()) return emptyList()

        val account = AccountStore.activeAccount ?: return emptyList()
        val balances = BalanceStore.getBalances(account.accountId)

        // A fuzzy-inclusive cache also serves a substring-only request: it is exactly what the
        // list already shows for this keyword, so reusing it avoids visibly dropping rows.
        val fingerprint = tokenCatalogFingerprint
        val cached = tokenMatchCache?.takeIf {
            it.fingerprint == fingerprint &&
                it.keyword == keyword &&
                it.accountId == account.accountId &&
                (it.includesFuzzy || !includeFuzzyTokens)
        }
        val matchedTokens: List<MToken>
        val exactSlugs: Set<String>
        if (cached != null) {
            matchedTokens = cached.matched
            exactSlugs = cached.exactSlugs
        } else {
            val keywordLower = keyword.lowercase()
            val looseQuery = UniversalSearchQuery(keyword)
            matchedTokens = matchTokens(
                account,
                keywordLower,
                looseQuery,
                includeFuzzyTokens
            )
            exactSlugs = matchedTokens
                .asSequence()
                .filter {
                    searchContext.ensureActive()
                    it.matchesSearchExactly(keyword)
                }
                .map { it.slug }
                .toSet()
            tokenMatchCache = TokenMatchCache(
                fingerprint,
                keyword,
                account.accountId,
                matchedTokens,
                exactSlugs,
                includesFuzzy = includeFuzzyTokens
            )
        }

        val popularSlugs = matchedTokens.mapNotNullTo(HashSet()) { token ->
            token.slug.takeIf { token.isPopular }
        }
        return matchedTokens
            .asSequence()
            .map { token ->
                searchContext.ensureActive()
                MTokenBalance.fromParameters(
                    token,
                    balances?.get(token.slug) ?: BigInteger.ZERO
                )
            }
            .sortedWith { left, right ->
                searchContext.ensureActive()
                val leftExact = left.token in exactSlugs
                val rightExact = right.token in exactSlugs
                val leftPopular = left.token in popularSlugs
                val rightPopular = right.token in popularSlugs
                if (leftExact != rightExact) {
                    if (leftExact) -1 else 1
                } else if (leftPopular != rightPopular) {
                    if (leftPopular) -1 else 1
                } else {
                    left.compareByDisplayOrder(right, ignorePriorities = !account.isNew)
                }
            }
            .take(SEARCH_SECTION_ITEMS_LIMIT)
            .toList()
    }

    private fun recentTokens(
        recentTokenSlugs: List<String>,
        searchContext: CoroutineContext
    ): List<MTokenBalance> = tokenBalances(recentTokenSlugs, searchContext)

    private fun trendingTokens(searchContext: CoroutineContext): List<MTokenBalance> {
        val account = AccountStore.activeAccount ?: return emptyList()
        return tokenBalances(
            TRENDING_TOKEN_SLUGS[account.network].orEmpty(),
            searchContext
        )
    }

    private fun tokenBalances(
        tokenSlugs: List<String>,
        searchContext: CoroutineContext
    ): List<MTokenBalance> {
        val account = AccountStore.activeAccount ?: return emptyList()
        val balances = BalanceStore.getBalances(account.accountId)
        return tokenSlugs
            .asSequence()
            .mapNotNull { tokenSlug ->
                searchContext.ensureActive()
                TokenStore.getToken(tokenSlug)
            }
            .filter { token ->
                searchContext.ensureActive()
                account.isChainSupported(token.chain)
            }
            .distinctBy { it.slug }
            .map { token ->
                searchContext.ensureActive()
                MTokenBalance.fromParameters(
                    token,
                    balances?.get(token.slug) ?: BigInteger.ZERO
                )
            }
            .take(SEARCH_SECTION_ITEMS_LIMIT)
            .toList()
    }

    private fun filterCollectibles(
        query: String,
        searchContext: CoroutineContext
    ): List<CollectibleMatch> {
        val keyword = query.lowercase()
        if (keyword.isEmpty()) return emptyList()

        val accountId = AccountStore.activeAccountId ?: return emptyList()
        val nfts = NftStore.nftData
            ?.takeIf { it.accountId == accountId }
            ?.cachedNfts
            ?.filterNot {
                searchContext.ensureActive()
                NftStore.shouldHide(accountId, it)
            }
            ?: emptyList()

        val matches = buildList {
            nfts.forEach { nft ->
                searchContext.ensureActive()
                if (nft.collectibleSearchRank(keyword) > 0) {
                    add(CollectibleMatch.Nft(nft))
                }
            }
            NftStore.getCollectionsFromNfts(nfts).forEach { collection ->
                searchContext.ensureActive()
                if (collection.collectibleSearchRank(keyword) > 0) {
                    add(CollectibleMatch.Collection(collection))
                }
            }
        }

        return matches
            .sortedByDescending {
                searchContext.ensureActive()
                it.collectibleSearchRank(keyword)
            }
            .take(SEARCH_SECTION_ITEMS_LIMIT)
    }

    private fun CollectibleMatch.collectibleSearchRank(keyword: String): Int = when (this) {
        is CollectibleMatch.Nft -> nft.collectibleSearchRank(keyword)
        is CollectibleMatch.Collection -> collection.collectibleSearchRank(keyword)
    }

    private fun ApiNft.collectibleSearchRank(keyword: String): Int = maxOf(
        name.textSearchRank(keyword, exactRank = 6, prefixRank = 5, containsRank = 4),
        if (address.equals(keyword, ignoreCase = true)) 6 else 0,
        collectionName.textSearchRank(keyword, exactRank = 3, prefixRank = 2, containsRank = 1),
        description.textSearchRank(keyword, exactRank = 3, prefixRank = 2, containsRank = 1)
    )

    private fun MCollectionTabToShow.collectibleSearchRank(keyword: String): Int = maxOf(
        name.textSearchRank(keyword, exactRank = 6, prefixRank = 5, containsRank = 4),
        if (address.equals(keyword, ignoreCase = true)) 6 else 0
    )

    private fun String?.textSearchRank(
        keyword: String,
        exactRank: Int,
        prefixRank: Int,
        containsRank: Int
    ): Int {
        val value = this?.lowercase() ?: return 0
        return when {
            value == keyword -> exactRank
            value.startsWith(keyword) -> prefixRank
            value.contains(keyword) -> containsRank
            else -> 0
        }
    }

    private fun filterAppEntries(
        entries: List<AppSearchEntry>,
        keyword: String,
        searchContext: CoroutineContext
    ): List<AppSearchEntry> {
        if (keyword.isEmpty()) return emptyList()
        return entries.filter {
            searchContext.ensureActive()
            it.isAvailable() && it.matches(keyword)
        }
    }

    private fun recentDapps(
        visitedSites: List<MExploreHistory.VisitedSite>,
        searchContext: CoroutineContext
    ): List<IDapp> {
        val connectedDapps = DappsStore.dApps[AccountStore.activeAccountId].orEmpty()
        val candidates: List<IDapp> =
            (allSites?.filter { it.canBeShown } ?: emptyList()) + connectedDapps
        if (candidates.isEmpty()) return emptyList()
        // visitedSites is ordered most-recent-first, so the first match per app wins.
        return visitedSites
            .asSequence()
            .mapNotNull { visitedSite ->
                searchContext.ensureActive()
                val host = visitedSite.url.toUri().host ?: return@mapNotNull null
                candidates.find { it.url?.toUri()?.host == host }
            }
            .distinctBy { it.url }
            .take(SEARCH_SECTION_ITEMS_LIMIT)
            .toList()
    }

    private fun trendingDapps(searchContext: CoroutineContext): List<IDapp> = allSites
        ?.filter {
            searchContext.ensureActive()
            it.isFeatured && it.canBeShown
        }
        ?.take(SEARCH_SECTION_ITEMS_LIMIT)
        ?: emptyList()

    private fun filterDapps(
        query: String,
        itemsLimit: Int,
        searchContext: CoroutineContext
    ): List<IDapp> {
        val query = query.lowercase()
        val connectedSites = DappsStore.dApps[AccountStore.activeAccountId]?.filter { dapp ->
            searchContext.ensureActive()
            allSites?.find { site ->
                searchContext.ensureActive()
                site.url?.toUri()?.host == dapp.url?.toUri()?.host
            } == null
        } ?: emptyList()

        val allSites: List<IDapp> = (allSites?.toList() ?: emptyList()) + connectedSites

        return allSites
            .filter {
                searchContext.ensureActive()
                (
                    ConfigStore.isLimited != true || (it is MExploreSite && !it.canBeRestricted) ||
                        it is ApiDapp
                    ) &&
                    (
                        it.name?.lowercase()?.contains(query) == true ||
                            (
                                it is MExploreSite && it.description?.lowercase()
                                    ?.contains(query) == true
                                ) ||
                            it.url?.lowercase()?.contains(query) == true
                        )
            }
            .sortedWith(
                compareByDescending {
                    searchContext.ensureActive()
                    it.name?.lowercase()?.startsWith(query) == true ||
                        (
                            it is MExploreSite && it.description?.lowercase()
                                ?.startsWith(query) == true
                            ) ||
                        it.url?.lowercase()?.startsWith(query) == true
                }
            )
            .take(itemsLimit)
    }
}
