package org.mytonwallet.app_air.walletcore.api

import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.stores.AccountStore


suspend fun WalletCore.getMoonpayOnrampUrl(
    tokenSymbol: String,
    activeTheme: String,
) = run {
    val address = AccountStore.activeAccount?.addressByChain?.get(tokenSymbol)
    val quotedTokenSymbol = JSONObject.quote(tokenSymbol)
    val quotedAddress = JSONObject.quote(address ?: "")
    val quotedTheme = JSONObject.quote(activeTheme)
    
    val args = "[$quotedTokenSymbol,$quotedAddress,$quotedTheme]"
    bridge!!.callApiAsync<Map<String, String>>(
        "getMoonpayOnrampUrl",
        args,
        Map::class.java
    )
}
