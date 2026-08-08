package org.mytonwallet.app_air.uiswap.screens.swap.models

import java.math.BigInteger
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset

data class SwapWalletState(
    var accountId: String,
    val addressByChain: Map<String, String>,
    val balances: Map<String, BigInteger>,
    val assets: List<MApiSwapAsset>
) {
    val assetsMap: Map<String, MApiSwapAsset> = assets.associateBy { it.slug }

    val tonAddress get() = addressByChain[MBlockchain.ton.name]

    fun isSupportedChain(chain: MBlockchain?): Boolean = addressByChain[chain?.name] != null
}
