package org.mytonwallet.app_air.walletcore.models

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class MExploreHistory(
    val searchHistory: MutableList<HistoryItem> = mutableListOf(),
    val visitedSites: MutableList<VisitedSite> = mutableListOf(),
) {
    @JsonClass(generateAdapter = true)
    data class HistoryItem(val title: String, val visitDate: Long?)

    @JsonClass(generateAdapter = true)
    data class VisitedSite(
        val favicon: String,
        val title: String,
        val url: String,
        val visitDate: Long
    )
}
