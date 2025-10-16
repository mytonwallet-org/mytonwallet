package org.mytonwallet.app_air.uibrowser.viewControllers.search

import androidx.core.net.toUri
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.moshi.IDapp
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.DappsStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore

class SearchVM() {

    var sites = emptyArray<MExploreSite>()

    fun exactMatch(keyword: String): MExploreHistory.VisitedSite? {
        if (keyword.isEmpty())
            return null
        val exactMatchItem = ExploreHistoryStore.exploreHistory?.visitedSites?.firstOrNull {
            it.url.toUri().host?.startsWith(keyword) == true ||
                it.url.startsWith(keyword)
        }
        return exactMatchItem?.copy(favicon = sites.find { site ->
            site.url?.toUri()?.host == exactMatchItem.url.toUri().host
        }?.iconUrl ?: exactMatchItem.favicon)
    }

    fun recentSearches(keyword: String): List<MExploreHistory.HistoryItem>? {
        return ExploreHistoryStore.exploreHistory?.searchHistory
            ?.filter { it.title.lowercase().contains(keyword) }
            ?.sortedWith(
                compareByDescending {
                    it.title.lowercase().startsWith(keyword)
                }
            )
            ?.take(10)
    }

    fun visitedSites(keyword: String): List<MExploreHistory.VisitedSite>? {
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
                    favicon = sites.find { site ->
                        site.url?.toUri()?.host == visitedSite.url.toUri().host
                    }?.iconUrl ?: visitedSite.favicon
                )
            }
    }

    fun filterDapps(query: String): List<IDapp> {
        val query = query.lowercase()
        val connectedSites = DappsStore.dApps[AccountStore.activeAccountId]?.filter { dapp ->
            sites.find { site -> site.url?.toUri()?.host == dapp.url?.toUri()?.host } == null
        } ?: emptyList()

        val allSites: List<IDapp> = sites.toList() + connectedSites

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
