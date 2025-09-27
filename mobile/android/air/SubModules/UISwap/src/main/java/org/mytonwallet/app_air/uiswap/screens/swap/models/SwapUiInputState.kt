package org.mytonwallet.app_air.uiswap.screens.swap.models

import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import java.math.BigInteger

enum class SwapDetailsVisibility { VISIBLE, CEX, GONE }

data class SwapUiInputState(
    val wallet: SwapWalletState,
    private val input: SwapInputState,
) {
    val tokenToSend: IApiToken? = input.tokenToSend
    val tokenToSendMaxAmount: String
        get() {
            return input.tokenToSendMaxAmount ?: maxAmountFmt ?: ""
        }
    val nativeTokenToSend: MApiSwapAsset? =
        wallet.assetsMap[tokenToSend?.mBlockchain?.nativeSlug]
    val tokenToReceive: IApiToken? = input.tokenToReceive

    val tokenToSendIsSupported = wallet.isSupportedChain(tokenToSend?.mBlockchain)
    val tokenToReceiveIsSupported = wallet.isSupportedChain(tokenToReceive?.mBlockchain)

    val slippage = input.slippage
    val selectedDex = input.selectedDex

    val isCex = input.isCex
    val reverse = input.reverse && !isCex
    val swapDetailsVisibility = if (wallet.isSupportedChain(tokenToSend?.mBlockchain)) {
        if (isCex) SwapDetailsVisibility.CEX else SwapDetailsVisibility.VISIBLE
    } else {
        SwapDetailsVisibility.GONE
    }

    val amountInput = if (input.reverse && isCex) null else input.amount
    private val tokenToInput = if (reverse) tokenToReceive else tokenToSend
    val amount = tokenToInput?.let {
        CoinUtils.fromDecimal(amountInput, it.decimals)
    }

    val key =
        tokenToSend?.slug + "_" + tokenToReceive?.slug + "_" + amountInput + "_" + (reverse.toString())

    internal val tokenToSendBalance: BigInteger =
        tokenToSend?.let { token -> wallet.balances[token.slug] } ?: BigInteger.ZERO
    internal val nativeTokenToSendBalance: BigInteger =
        nativeTokenToSend?.let { wallet.balances[it.slug] } ?: BigInteger.ZERO

    private val maxAmountFmt: String?
        get() {
            val token = tokenToSend ?: return null
            if (!tokenToSendIsSupported) return null

            return tokenToSendBalance.toString(
                decimals = token.decimals,
                currency = token.symbol ?: "",
                currencyDecimals = tokenToSendBalance.smartDecimalsCount(token.decimals),
                showPositiveSign = false
            )
        }

    val isFromAmountMax: Boolean
        get() {
            return input.isFromAmountMax
        }

    init {
        if (reverse && isCex) {
            throw IllegalStateException()
        }
    }
}
