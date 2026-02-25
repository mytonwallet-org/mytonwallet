package org.mytonwallet.app_air.walletcore.helpers

import android.net.Uri
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.stores.AccountStore

object SubprojectHelpers {

    fun isSubproject(url: String): Boolean {
        val host = Uri.parse(url).host?.lowercase() ?: return false
        if (host.endsWith(".mytonwallet.io")) return true
        return host == "localhost" && (Uri.parse(url).port?.toString()?.startsWith("432") == true)
    }

    fun buildSubprojectHash(): String {
        val theme = WGlobalStorage.getActiveTheme()
        val lang = WGlobalStorage.getLangCode()
        val baseCurrency = WGlobalStorage.getBaseCurrency()

        val addresses = AccountStore.activeAccount?.byChain?.entries
            ?.joinToString(",") { "${it.key}:${it.value.address}" }

        val params = buildList {
            add("theme=$theme")
            add("lang=$lang")
            add("baseCurrency=$baseCurrency")
            if (!addresses.isNullOrEmpty()) {
                add("addresses=$addresses")
            }
        }

        return params.joinToString("&")
    }

    fun appendSubprojectContext(url: String): String {
        return "$url#${buildSubprojectHash()}"
    }
}
