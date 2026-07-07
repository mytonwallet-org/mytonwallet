package org.mytonwallet.app_air.uibrowser.viewControllers.explore

import android.os.Handler
import android.os.Looper
import androidx.core.net.toUri
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.loadExploreSites
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MExploreCategory
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.IDapp
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.DappsStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import java.lang.ref.WeakReference

class ExploreVM(delegate: Delegate) : WalletCore.EventObserver {
    interface Delegate {
        fun updateEmptyView()
        fun sitesUpdated()
        fun accountChanged()
    }

    private val delegate: WeakReference<Delegate> = WeakReference(delegate)

    private var waitingForNetwork = false
    internal var connectedSites: Array<ApiDapp>? =
        DappsStore.dApps[AccountStore.activeAccountId]?.toTypedArray()
    var allSites: List<MExploreSite>? = null
        private set
    private var allExploreCategories: List<MExploreCategory>? = null

    internal var showingExploreCategories: List<MExploreCategory>? = null
    internal var showingTrendingSites = listOf<MExploreSite>()

    fun delegateIsReady() {
        WalletCore.registerObserver(this)
        if (!WalletCore.isConnected()) {
            waitingForNetwork = true
        }
        refresh()
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

            else -> {}
        }
    }

    // A match against one of the user's own added wallet accounts.
    data class MyWalletMatch(
        val account: MAccount,
        val chain: MBlockchain?,
        val address: String?,
        val isFullMatch: Boolean,
    )

    // A well-known address/domain resolved through the API for an unknown wallet.
    data class WalletInfoMatch(
        val network: MBlockchainNetwork,
        val chain: MBlockchain,
        val inputAddressOrDomain: String,
        val address: String,
        val name: String?,
        val domain: String?,
    )

    data class SearchResult(
        val keyword: String,
        val matchedVisitedSite: MExploreHistory.VisitedSite? = null,
        val recentSearches: List<MExploreHistory.HistoryItem>? = null,
        val recentVisitedSites: List<MExploreHistory.VisitedSite>? = null,
        val dapps: List<IDapp>? = null,
        val myWallets: List<MyWalletMatch>? = null,
        val walletInfo: WalletInfoMatch? = null,
        val noResultsFound: Boolean = false,
    )

    fun search(keyword: String): SearchResult {
        val matchedVisitedSite = exactMatch(keyword)
        val recentSearches = recentSearches(keyword)
        val recentVisitedSites = visitedSites(keyword)
        val dapps = filterDapps(keyword)
        val myWallets = matchOwnWallets(keyword)
        val noResultsFound = !keyword.isEmpty() &&
            matchedVisitedSite == null &&
            recentSearches.isNullOrEmpty() &&
            recentVisitedSites.isNullOrEmpty() &&
            recentVisitedSites.isNullOrEmpty() &&
            myWallets.isEmpty() &&
            dapps.isEmpty()
        return SearchResult(
            keyword,
            matchedVisitedSite,
            if (noResultsFound) listOf(
                MExploreHistory.HistoryItem(keyword, null)
            ) else recentSearches,
            recentVisitedSites,
            dapps,
            myWallets,
            null,
            noResultsFound
        )
    }

    private fun matchOwnWallets(query: String): List<MyWalletMatch> {
        val keyword = query.lowercase()
        if (keyword.isEmpty())
            return emptyList()

        val minimalAcceptableAddressMatchCount = 4
        val minimalAcceptableDomainMatchCount = 1

        val items = mutableListOf<MyWalletMatch>()
        WGlobalStorage.accountIds().forEach { accountId ->
            val account = AccountStore.accountById(accountId) ?: return@forEach
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

            if (!isPartial)
                return@forEach

            // Matched only by name: fall back to the account's primary chain for display.
            val chain = matchedChain ?: account.firstChain
            val address = matchedAddress ?: account.firstAddress
            items.add(MyWalletMatch(account, chain, address, isFull))
        }

        // Full matches first (preserving account order) so the composer promotes one to the top match.
        return items.filter { it.isFullMatch } + items.filter { !it.isFullMatch }
    }

    var currentSearchKeyword: String? = null
        private set

    fun searchWalletInfo(result: SearchResult, onResult: (SearchResult) -> Unit) {
        val keyword = result.keyword
        currentSearchKeyword = keyword

        if (keyword.isEmpty() || result.myWallets?.any { it.isFullMatch } == true)
            return

        val account = AccountStore.activeAccount ?: return
        val network = account.network
        val compatibleChains = MBlockchain.supportedChains.filter {
            it.isValidAddress(keyword) || it.isValidDNS(keyword)
        }
        if (compatibleChains.isEmpty())
            return

        var didEmit = false
        compatibleChains.forEach { chain ->
            WalletCore.call(
                ApiMethod.WalletData.GetAddressInfo(chain, network, keyword)
            ) { info, err ->
                if (currentSearchKeyword != keyword || didEmit)
                    return@call
                if (info == null || err != null || info.error != null)
                    return@call

                val isDomain = chain.isValidDNS(keyword)
                val resolved = info.resolvedAddress?.takeIf { it.isNotEmpty() }
                val address = when {
                    resolved != null -> resolved
                    !isDomain -> keyword
                    else -> return@call
                }

                didEmit = true
                onResult(
                    result.copy(
                        recentSearches = if (result.noResultsFound) emptyList() else result.recentSearches,
                        noResultsFound = false,
                        walletInfo = WalletInfoMatch(
                            network = network,
                            chain = chain,
                            inputAddressOrDomain = keyword,
                            address = address,
                            name = info.addressName?.takeIf { it.isNotEmpty() },
                            domain = if (isDomain) keyword else null,
                        )
                    )
                )
            }
        }
    }

    private fun exactMatch(keyword: String): MExploreHistory.VisitedSite? {
        if (keyword.isEmpty())
            return null
        val exactMatchItem = ExploreHistoryStore.exploreHistory?.visitedSites?.firstOrNull {
            it.url.toUri().host?.startsWith(keyword) == true ||
                it.url.startsWith(keyword)
        }
        return exactMatchItem?.copy(favicon = allSites?.find { site ->
            site.url?.toUri()?.host == exactMatchItem.url.toUri().host
        }?.iconUrl ?: exactMatchItem.favicon)
    }

    private fun recentSearches(keyword: String): List<MExploreHistory.HistoryItem>? {
        return ExploreHistoryStore.exploreHistory?.searchHistory
            ?.filter { it.title.lowercase().contains(keyword) }
            ?.sortedWith(
                compareByDescending {
                    it.title.lowercase().startsWith(keyword)
                }
            )
            ?.take(10)
    }

    private fun visitedSites(keyword: String): List<MExploreHistory.VisitedSite>? {
        return ExploreHistoryStore.exploreHistory?.visitedSites
            ?.filter {
                it.title.lowercase().contains(keyword) ||
                    it.url.lowercase().contains(keyword)
            }
            ?.sortedWith(
                compareByDescending {
                    it.title.lowercase().startsWith(keyword) ||
                        it.url.lowercase().startsWith(keyword)
                }
            )
            ?.take(5)
            ?.map { visitedSite ->
                visitedSite.copy(
                    favicon = allSites?.find { site ->
                        site.url?.toUri()?.host == visitedSite.url.toUri().host
                    }?.iconUrl ?: visitedSite.favicon
                )
            }
    }

    private fun filterDapps(query: String): List<IDapp> {
        val query = query.lowercase()
        val connectedSites = DappsStore.dApps[AccountStore.activeAccountId]?.filter { dapp ->
            allSites?.find { site -> site.url?.toUri()?.host == dapp.url?.toUri()?.host } == null
        } ?: emptyList()

        val allSites: List<IDapp> = (allSites?.toList() ?: emptyList()) + connectedSites

        return allSites
            .filter {
                (ConfigStore.isLimited != true || (it is MExploreSite && !it.canBeRestricted) || it is ApiDapp) &&
                    (
                        it.name?.lowercase()?.contains(query) == true ||
                            (it is MExploreSite && it.description?.lowercase()
                                ?.contains(query) == true) ||
                            it.url?.lowercase()?.contains(query) == true
                        )
            }
            .sortedWith(
                compareByDescending {
                    it.name?.lowercase()?.startsWith(query) == true ||
                        (it is MExploreSite && it.description?.lowercase()
                            ?.startsWith(query) == true) ||
                        it.url?.lowercase()?.startsWith(query) == true
                }
            )
            .take(5)
    }
}
