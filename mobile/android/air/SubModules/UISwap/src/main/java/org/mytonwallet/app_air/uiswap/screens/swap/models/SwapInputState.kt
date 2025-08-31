package org.mytonwallet.app_air.uiswap.screens.swap.models

import org.mytonwallet.app_air.uiswap.screens.swap.helpers.SwapHelpers
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapDexLabel

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
}
