package org.mytonwallet.app_air.uiswap.screens.swap.models

import java.math.BigDecimal
import java.math.BigInteger
import org.mytonwallet.app_air.uiswap.screens.swap.helpers.SwapHelpers
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.helpers.FeeEstimationHelpers
import org.mytonwallet.app_air.walletcore.models.DIESEL_TOKENS
import org.mytonwallet.app_air.walletcore.models.SwapType
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapEstimateRequest
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus

@ConsistentCopyVisibility
data class SwapEstimateRequest private constructor(
    val key: String,
    val wallet: SwapWalletState,
    val tokenToSend: IApiToken,
    val tokenToReceive: IApiToken,
    val nativeTokenToSend: IApiToken,
    val nativeTokenToSendBalance: String,
    val amount: BigInteger,
    val slippage: Float,
    val reverse: Boolean,
    val isFromAmountMax: Boolean,
    val prevEst: SwapEstimateResponse?
) {
    val tokenToSendChain: MBlockchain = requireNotNull(tokenToSend.mBlockchain)
    val tokenToSendIsSupported = wallet.isSupportedChain(tokenToSend.mBlockchain)
    val tokenToReceiveIsSupported = wallet.isSupportedChain(tokenToReceive.mBlockchain)
    val isCex = SwapHelpers.isCex(tokenToSend, tokenToReceive)

    val shouldTryDiesel: Boolean
    val isDiesel: Boolean

    init {
        val swapType = SwapType.from(tokenToSend, tokenToReceive, wallet.addressByChain)
        val networkFeeData =
            FeeEstimationHelpers.networkFeeData(
                tokenToSend,
                wallet.isSupportedChain(tokenToSend.mBlockchain),
                swapType,
                prevEst?.dex?.networkFee
            )
        val totalNativeAmount = (networkFeeData?.fee ?: BigDecimal.ZERO) +
            (
                if (networkFeeData?.isNativeIn == true) {
                    CoinUtils.toBigDecimal(
                        amount,
                        nativeTokenToSend.decimals
                    )
                } else {
                    BigDecimal.ZERO
                }
                )
        val nativeBalance = CoinUtils.toBigDecimal(
            wallet.balances[tokenToSendChain.nativeSlug] ?: BigInteger.ZERO,
            nativeTokenToSend.decimals
        )
        val isEnoughNative = nativeBalance >= totalNativeAmount
        shouldTryDiesel =
            !isEnoughNative && !tokenToSend.isBlockchainNative &&
            prevEst?.dex?.dieselStatus != MDieselStatus.NOT_AVAILABLE
        isDiesel = swapType == SwapType.ON_CHAIN && shouldTryDiesel && DIESEL_TOKENS.contains(
            tokenToSend.tokenAddress
        )
    }

    val estimateRequestDex: MApiSwapEstimateRequest
        get() = MApiSwapEstimateRequest(
            from = tokenToSend.swapSlug,
            to = tokenToReceive.swapSlug,
            fromAddress = tokenToSend.mBlockchain?.name?.let { wallet.addressByChain[it] }
                ?: wallet.tonAddress,
            fromAmount = if (!reverse) {
                CoinUtils.toBigDecimal(
                    amount,
                    tokenToSend.decimals
                )
            } else {
                null
            },
            toAmount = if (reverse) {
                CoinUtils.toBigDecimal(
                    amount,
                    tokenToReceive.decimals
                )
            } else {
                null
            },
            slippage = slippage,
            shouldTryDiesel = shouldTryDiesel,
            walletVersion = null,
            isFromAmountMax = isFromAmountMax,
            toncoinBalance = nativeTokenToSendBalance
        )

    val estimateRequestCex: MApiSwapEstimateRequest
        get() {
            if (reverse && isCex) {
                throw IllegalStateException()
            }

            return MApiSwapEstimateRequest(
                from = tokenToSend.swapSlug,
                to = tokenToReceive.swapSlug,
                slippage = null,
                fromAmount = CoinUtils.toBigDecimal(amount, tokenToSend.decimals),
                toAmount = null,
                fromAddress = wallet.addressByChain[tokenToSend.mBlockchain?.name],
                toAddress = wallet.addressByChain[tokenToReceive.mBlockchain?.name],
                cexLabel = null,
                shouldTryDiesel = null,
                walletVersion = null,
                isFromAmountMax = isFromAmountMax,
                toncoinBalance = nativeTokenToSendBalance
            )
        }

    companion object {
        fun create(
            key: String,
            wallet: SwapWalletState,
            tokenToSend: IApiToken,
            tokenToReceive: IApiToken,
            nativeTokenToSend: IApiToken?,
            nativeTokenToSendBalance: String,
            amount: BigInteger,
            slippage: Float,
            reverse: Boolean,
            isFromAmountMax: Boolean,
            prevEst: SwapEstimateResponse?
        ): SwapEstimateRequest? {
            if (nativeTokenToSend == null || tokenToSend.mBlockchain == null) {
                return null
            }
            return SwapEstimateRequest(
                key = key,
                wallet = wallet,
                tokenToSend = tokenToSend,
                tokenToReceive = tokenToReceive,
                nativeTokenToSend = nativeTokenToSend,
                nativeTokenToSendBalance = nativeTokenToSendBalance,
                amount = amount,
                slippage = slippage,
                reverse = reverse,
                isFromAmountMax = isFromAmountMax,
                prevEst = prevEst
            )
        }
    }
}
