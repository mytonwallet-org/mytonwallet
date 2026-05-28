package org.mytonwallet.app_air.walletcore.stores

import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import java.util.concurrent.Executors

object ExploreHistoryStore : IStore {

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
            0, MExploreHistory.HistoryItem(text, System.currentTimeMillis())
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

    fun clearAccountHistory() {
        exploreHistory = MExploreHistory()
        saveBrowserHistory(accountId, exploreHistory)
    }

    private fun saveBrowserHistory(accountId: String?, browserHistory: MExploreHistory?) {
        if (AccountStore.activeAccountId != accountId)
            return
        accountId?.let {
            WCacheStorage.setExploreHistory(accountId, adapter.toJson(browserHistory))
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
