package org.mytonwallet.app_air.uibrowser.viewControllers.explore

import android.os.Handler
import android.os.Looper
import androidx.core.net.toUri
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.loadExploreSites
import org.mytonwallet.app_air.walletcore.models.MExploreCategory
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.IDapp
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
    var allSites: Array<MExploreSite>? = null
        private set
    private var allExploreCategories: Array<MExploreCategory>? = null

    internal var showingExploreCategories: Array<MExploreCategory>? = null
    internal var showingTrendingSites = arrayOf<MExploreSite>()

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

    private fun updateSites(categories: Array<MExploreCategory>?, sites: Array<MExploreSite>?) {
        this.allSites = sites
        allExploreCategories = categories
        filterAndShowSites()
    }

    private fun filterAndShowSites() {
        showingExploreCategories = allExploreCategories?.filter {
            it.sites.any { it.canBeShown }
        }?.toTypedArray()
        showingTrendingSites =
            allSites?.filter { it.isFeatured && it.canBeShown }?.toTypedArray() ?: emptyArray()
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

    data class SearchResult(
        val keyword: String,
        val matchedVisitedSite: MExploreHistory.VisitedSite? = null,
        val recentSearches: List<MExploreHistory.HistoryItem>? = null,
        val recentVisitedSites: List<MExploreHistory.VisitedSite>? = null,
        val dapps: List<IDapp>? = null,
        val noResultsFound: Boolean = false,
    )

    fun search(keyword: String): SearchResult {
        val matchedVisitedSite = exactMatch(keyword)
        val recentSearches = recentSearches(keyword)
        val recentVisitedSites = visitedSites(keyword)
        val dapps = filterDapps(keyword)
        val noResultsFound = !keyword.isEmpty() &&
            matchedVisitedSite == null &&
            recentSearches.isNullOrEmpty() &&
            recentVisitedSites.isNullOrEmpty() &&
            recentVisitedSites.isNullOrEmpty() &&
            dapps.isEmpty()
        return SearchResult(
            keyword,
            matchedVisitedSite,
            if (noResultsFound) listOf(
                MExploreHistory.HistoryItem(keyword, null)
            ) else recentSearches,
            recentVisitedSites,
            dapps,
            noResultsFound
        )
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
