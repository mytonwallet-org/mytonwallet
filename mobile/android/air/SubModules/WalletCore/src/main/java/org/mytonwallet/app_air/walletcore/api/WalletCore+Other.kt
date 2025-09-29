package org.mytonwallet.app_air.walletcore.api

import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.WalletCore


fun WalletCore.getMoonpayOnrampUrl(
    chain: String,
    address: String,
    activeTheme: String,
    currency: String,
    callback: (Map<String, String>?) -> Unit
) {
    val quotedChain = JSONObject.quote(chain)
    val quotedAddress = JSONObject.quote(address)
    val quotedTheme = JSONObject.quote(activeTheme)
    val quotedCurrency = JSONObject.quote(currency)

    val args = "[$quotedChain,$quotedAddress,$quotedTheme,$quotedCurrency]"
    bridge!!.callApi<Map<String, String>>(
        "getMoonpayOnrampUrl",
        args,
        Map::class.java,
        callback = { res, parsed, err ->
            callback(parsed)
        }
    )
}
