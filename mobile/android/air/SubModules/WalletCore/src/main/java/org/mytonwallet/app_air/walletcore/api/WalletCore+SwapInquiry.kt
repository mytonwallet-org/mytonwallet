package org.mytonwallet.app_air.walletcore.api

import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.stores.TokenStore

fun WalletCore.swapGetAssets(
    ifNotLoading: Boolean = false,
    callback: ((Boolean, MBridgeError?) -> Unit)? = null
) {
    if (ifNotLoading) {
        if (TokenStore.isLoadingSwapAssets) {
            return
        }
    }

    TokenStore.isLoadingSwapAssets = true
    bridge?.callApi(
        "swapGetAssets",
        "[]"
    ) { result, error ->
        if (error != null || result == null) {
            TokenStore.isLoadingSwapAssets = false
            callback?.invoke(false, error)
        } else {
            callback?.invoke(true, null)
        }
    }
}
