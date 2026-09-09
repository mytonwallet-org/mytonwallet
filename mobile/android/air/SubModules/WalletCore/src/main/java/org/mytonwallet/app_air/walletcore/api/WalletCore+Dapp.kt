@file:Suppress("ktlint:standard:filename")

package org.mytonwallet.app_air.walletcore.api

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MExploreCategory
import org.mytonwallet.app_air.walletcore.models.MExploreSite

fun WalletCore.loadExploreSites(
    callback: (List<MExploreCategory>?, sites: List<MExploreSite>?, MBridgeError?) -> Unit
) {
    bridge?.callApi(
        "loadExploreSites",
        "[{\"langCode\": \"${WGlobalStorage.getLangCode()}\", \"isLandscape\": false}]"
    ) { result, error ->
        if (error != null || result == null) {
            callback(null, null, error)
        } else {
            scope.launch {
                try {
                    val exploreSitesJSONObject = JSONObject(result)
                    val exploreSites = ArrayList<MExploreSite>()
                    val exploreSitesJSONArray = exploreSitesJSONObject.getJSONArray("sites")
                    for (index in 0..<exploreSitesJSONArray.length()) {
                        val exploreSiteObj = exploreSitesJSONArray.getJSONObject(index)
                        val exploreSite = MExploreSite(exploreSiteObj)
                        exploreSites.add(exploreSite)
                    }
                    val categories = ArrayList<MExploreCategory>()
                    val categoriesJSONArray = exploreSitesJSONObject.getJSONArray("categories")
                    for (index in 0..<categoriesJSONArray.length()) {
                        val categoryObj = categoriesJSONArray.getJSONObject(index)
                        val exploreCategory = MExploreCategory(categoryObj, exploreSites)
                        categories.add(exploreCategory)
                    }
                    withContext(Dispatchers.Main) {
                        callback(categories, exploreSites, null)
                    }
                } catch (_: Throwable) {
                    withContext(Dispatchers.Main) {
                        callback(null, null, null)
                    }
                }
            }
        }
    }
}
