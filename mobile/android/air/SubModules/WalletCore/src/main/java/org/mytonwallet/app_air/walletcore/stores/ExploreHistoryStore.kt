package org.mytonwallet.app_air.walletcore.stores

import java.util.concurrent.Executors
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MExploreHistory

object ExploreHistoryStore : IStore {

    const val RECENT_TOKENS_LIMIT = 9

    private val adapter by lazy { WalletCore.moshi.adapter(MExploreHistory::class.java) }
    private var accountId = AccountStore.activeAccountId

    @Volatile
    var exploreHistory: MExploreHistory? = null
        private set
    private var cacheExecutor = Executors.newSingleThreadExecutor()

    fun loadBrowserHistory(accountId: String) {
        this.accountId = accountId
        exploreHistory = null
        cacheExecutor.execute {
            val exploreHistoryString = WCacheStorage.getExploreHistory(accountId)
            exploreHistory = exploreHistoryString?.let {
                val adapter = WalletCore.moshi.adapter(MExploreHistory::class.java)
                adapter.fromJson(exploreHistoryString)
            } ?: MExploreHistory()
        }
    }

    fun saveSearchHistory(text: String) {
        exploreHistory?.searchHistory?.removeAll {
            it.title.lowercase() == text.lowercase()
        }
        exploreHistory?.searchHistory?.add(
            0,
            MExploreHistory.HistoryItem(text, System.currentTimeMillis())
        )
        saveBrowserHistory(accountId, exploreHistory)
    }

    fun saveSiteVisit(visitedSite: MExploreHistory.VisitedSite) {
        exploreHistory?.visitedSites?.removeAll {
            it.url.lowercase() == visitedSite.url.lowercase()
        }
        exploreHistory?.visitedSites?.add(0, visitedSite)
        saveBrowserHistory(accountId, exploreHistory)
    }

    fun saveTokenVisit(accountId: String, tokenSlug: String) {
        if (this.accountId != accountId) return
        val history = exploreHistory ?: return
        if (!history.rememberOpenedToken(tokenSlug, RECENT_TOKENS_LIMIT)) return
        saveBrowserHistory(accountId, history)
    }

    fun clearSearchHistory() {
        val history = exploreHistory ?: return
        if (history.searchHistory.isEmpty()) return
        history.searchHistory.clear()
        saveBrowserHistory(accountId, history)
    }

    private fun saveBrowserHistory(accountId: String?, browserHistory: MExploreHistory?) {
        if (accountId == null) return
        val historySnapshot = browserHistory?.copy(
            searchHistory = browserHistory.searchHistory.toMutableList(),
            visitedSites = browserHistory.visitedSites.toMutableList(),
            mutableRecentTokenSlugs = browserHistory.recentTokenSlugs().toMutableList()
        )
        cacheExecutor.execute {
            WCacheStorage.setExploreHistory(accountId, adapter.toJson(historySnapshot))
        }
    }

    override fun wipeData() {
        clearCache()
    }

    override fun clearCache() {
        accountId = null
        exploreHistory = null
        cacheExecutor.shutdownNow()
        cacheExecutor = Executors.newSingleThreadExecutor()
    }
}
