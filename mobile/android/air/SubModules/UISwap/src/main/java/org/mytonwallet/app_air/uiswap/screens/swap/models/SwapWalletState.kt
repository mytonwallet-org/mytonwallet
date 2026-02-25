package org.mytonwallet.app_air.uiswap.screens.swap.models

import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import java.math.BigInteger

data class SwapWalletState(
    var accountId: String,
    val addressByChain: Map<String, String>,
    val balances: Map<String, BigInteger>,
    val assets: List<MApiSwapAsset>
) {
    val assetsMap: Map<String, MApiSwapAsset> = assets.associateBy { it.slug }

    val tonAddress get() = addressByChain[MBlockchain.ton.name]!!

    fun isSupportedChain(chain: MBlockchain?): Boolean {
        return addressByChain[chain?.name] != null
    }
}
