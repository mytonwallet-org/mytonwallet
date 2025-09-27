package org.mytonwallet.app_air.walletcore.api

import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBridgeError

fun WalletCore.setBaseCurrency(
    newBaseCurrency: String,
    callback: (Boolean, MBridgeError?) -> Unit
) {
    if (baseCurrency.currencyCode == newBaseCurrency) {
        callback(true, null)
        return
    }
    WGlobalStorage.clearPriceHistory()
    baseCurrency = MBaseCurrency.valueOf(newBaseCurrency)
    WGlobalStorage.setBaseCurrency(newBaseCurrency)
    WBaseStorage.setBaseCurrency(newBaseCurrency)
    notifyEvent(WalletEvent.BaseCurrencyChanged)
    callback(true, null)
}
