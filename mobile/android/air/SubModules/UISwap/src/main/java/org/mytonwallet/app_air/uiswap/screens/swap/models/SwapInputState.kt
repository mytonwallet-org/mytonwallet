package org.mytonwallet.app_air.uiswap.screens.swap.models

import org.mytonwallet.app_air.uiswap.screens.swap.helpers.SwapHelpers
import org.mytonwallet.app_air.walletcore.DEFAULT_SWAP_VERSION
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapDexLabel
import org.mytonwallet.app_air.walletcore.stores.ConfigStore

data class SwapInputState(
    val tokenToSend: IApiToken? = null,
    val tokenToSendMaxAmount: String? = null,
    val tokenToReceive: IApiToken? = null,
    val amount: String? = null,
    val reverse: Boolean = false,
    val isFromAmountMax: Boolean = false,
    val slippage: Float = 0f,
    val selectedDex: MApiSwapDexLabel? = null
) {
    val isCex = SwapHelpers.isCex(tokenToSend, tokenToReceive)

    val isSameChainSwap: Boolean
        get() {
            val sendChain = tokenToSend?.mBlockchain ?: MBlockchain.ton
            val receiveChain = tokenToReceive?.mBlockchain ?: MBlockchain.ton
            return sendChain == receiveChain && sendChain.isOnchainSwapSupported
        }

    val canSwapByBuyAmount: Boolean
        get() = (tokenToSend?.mBlockchain ?: MBlockchain.ton).canSwapByBuyAmount

    private val isSwapV3: Boolean
        get() {
            return (ConfigStore.swapVersion ?: DEFAULT_SWAP_VERSION) == 3
        }

    val shouldShowAllPairs: Boolean
        get() {
            return isSwapV3 && isSameChainSwap
        }

    val shouldShowAllPairsToBuy: Boolean
        get() {
            return isSwapV3 && (tokenToSend?.mBlockchain
                ?: MBlockchain.ton).isOnchainSwapSupported
        }
}
