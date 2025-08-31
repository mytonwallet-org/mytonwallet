package org.mytonwallet.app_air.walletcore.api

import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBaseCurrency
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.stores.TokenStore

fun WalletCore.setBaseCurrency(
    newBaseCurrency: String,
    callback: (Boolean, MBridgeError?) -> Unit
) {
    TokenStore.clearQuotes()
    WGlobalStorage.clearPriceHistory()
    bridge?.callApi(
        "setBaseCurrency",
        "[${JSONObject.quote(newBaseCurrency)}]"
    ) { result, error ->
        if (error != null || result == null) {
            callback(false, error)
        } else {
            baseCurrency = MBaseCurrency.valueOf(newBaseCurrency)
            WGlobalStorage.setBaseCurrency(newBaseCurrency)
            WalletCore.tryUpdatePrices()
            notifyEvent(WalletEvent.BaseCurrencyChanged)
            callback(true, null)
        }
    }
}
