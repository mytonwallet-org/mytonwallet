package org.mytonwallet.app_air.uiswap.screens.swap.models

import org.mytonwallet.app_air.uicomponents.helpers.Rate
import org.mytonwallet.app_air.uiswap.screens.swap.helpers.SwapHelpers
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletbasecontext.utils.max
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.MAX_PRICE_IMPACT_VALUE
import org.mytonwallet.app_air.walletcore.helpers.FeeEstimationHelpers
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.SwapType
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexEstimateResponse
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapEstimateResponse
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus
import java.math.BigDecimal
import java.math.BigInteger

data class SwapEstimateResponse(
    val request: SwapEstimateRequest,
    val dex: MApiSwapEstimateResponse?,
    val cex: MApiSwapCexEstimateResponse?,
    val fee: BigInteger?,
    val error: MBridgeError?
) {
    private val fromAmountDec = cex?.fromAmount ?: dex?.fromAmount
    private val toAmountDec = cex?.toAmount ?: dex?.toAmount
    val explainedFee = SwapHelpers.explainApiSwapFee(this)

    val fromAmount = CoinUtils.fromDecimal(fromAmountDec, request.tokenToSend.decimals)
    val toAmount = CoinUtils.fromDecimal(toAmountDec, request.tokenToReceive.decimals)

    val fromAmountDecimalStr =
        fromAmount?.let {
            CoinUtils.toDecimalString(
                max(BigInteger.ZERO, it),
                request.tokenToSend.decimals
            )
        }
    val toAmountDecimalStr =
        toAmount?.let {
            if (it > BigInteger.ZERO)
                CoinUtils.toDecimalString(
                    it,
                    request.tokenToReceive.decimals
                )
            else
                null
        }

    private val toAmountMin =
        CoinUtils.fromDecimal(dex?.toMinAmount ?: toAmountDec, request.tokenToReceive.decimals)
            ?: BigInteger.ZERO

    internal val fromAmountMin =
        cex?.fromMin?.let { fromMin ->
            CoinUtils.fromDecimal(
                fromMin,
                request.tokenToSend.decimals
            )
        }
    val fromAmountMax = CoinUtils.fromDecimal(cex?.fromMax, request.tokenToSend.decimals)

    val rate = Rate.build(
        sendAmount = fromAmountDec ?: BigDecimal.ZERO,
        receiveAmount = toAmountDec ?: BigDecimal.ZERO
    )
    val rateSendFmt = rate.fmtSend(
        request.tokenToSend.symbol,
        decimals = rate.sendAmount.smartDecimalsCount(),
        round = false
    )
    val rateReceiveFmt = rate.fmtReceive(
        request.tokenToReceive.symbol,
        decimals = rate.receiveAmount.smartDecimalsCount(),
        round = false
    )

    /*val confirmSubtitleFmt = LocaleController.getString(
        "%1$@ to %2$@", listOf(
            fromAmountDecimalStr + " " + request.tokenToSend.symbol,
            toAmountDecimalStr + " " + request.tokenToReceive.symbol
        )
    )*/

    val priceImpactFmt = (dex?.impact ?: 0.0).toString(
        decimals = 2,
        currency = "",
        currencyDecimals = 2,
        smartDecimals = true
    ) + "%"

    val minReceivedFmt = toAmountMin.toString(
        decimals = request.tokenToReceive.decimals,
        currency = request.tokenToReceive.symbol ?: "",
        currencyDecimals = toAmountMin.smartDecimalsCount(request.tokenToReceive.decimals),
        showPositiveSign = false,
        roundUp = false
    )

    val swapType: SwapType
        get() {
            return SwapHelpers.swapType(
                tokenToSend = request.tokenToSend,
                tokenToReceive = request.tokenToReceive,
                walletAddressByChain = request.wallet.addressByChain
            )
        }

    val isEnoughBalance: Boolean
        get() {
            if (swapType == SwapType.CROSS_CHAIN_TO_WALLET)
                return true

            val maxAmount = SwapHelpers.calcSwapMaxBalance(
                request.tokenToSend,
                request.tokenToReceive,
                request.wallet.addressByChain,
                request.wallet.balances,
                this
            )
            if (fromAmount == null)
                return false
            val nativeBalance = request.wallet.balances[request.tokenToSend.nativeToken?.slug]
            if (nativeBalance == null)
                return false

            return fromAmount <= maxAmount &&
                (explainedFee.fullFee?.networkTerms?.native ?: BigInteger.ZERO) <= nativeBalance
        }

    val isAmountGreaterThanBalance: Boolean
        get() {
            val fromAmount = fromAmount ?: return false
            val balanceIn = request.wallet.balances[request.tokenToSend.slug] ?: return false
            return fromAmount > balanceIn
        }

    val hasInsufficientFeeError: Boolean
        get() {
            return !isEnoughBalance &&
                !isAmountGreaterThanBalance &&
                dex?.dieselStatus != MDieselStatus.NOT_AUTHORIZED &&
                dex?.dieselStatus != MDieselStatus.PENDING_PREVIOUS
        }

    val transactionFeeFmt2: String?
        get() {
            if (request.isCex) {
                val nativeToken = request.nativeTokenToSend

                val fee = fee ?: FeeEstimationHelpers.networkFeeData(
                    request.tokenToSend,
                    request.wallet.isSupportedChain(request.tokenToSend.mBlockchain),
                    swapType,
                    dex?.networkFee
                )?.fee?.toBigInteger()
                return fee?.toString(
                    decimals = nativeToken.decimals,
                    currency = nativeToken.symbol ?: "",
                    currencyDecimals = fee.smartDecimalsCount(nativeToken.decimals),
                    showPositiveSign = false
                ) ?: ""
            } else {
                val shouldShowFullFee = hasInsufficientFeeError
                return (if (shouldShowFullFee) explainedFee.fullFee else explainedFee.realFee)?.toString(
                    request.tokenToSend,
                    appendNonNative = explainedFee.isGasless
                )
            }
        }

    val aggregatorFee: String?
        get() {
            return dex?.ourFee?.toDoubleOrNull()?.let {
                val tokenToSend = request.tokenToSend
                it.toString(
                    decimals = tokenToSend.decimals,
                    currency = tokenToSend.symbol ?: "",
                    currencyDecimals = tokenToSend.decimals,
                    smartDecimals = true,
                    showPositiveSign = false
                )
            }
        }

    val shouldShowPriceImpactWarning: Boolean
        get() {
            dex?.impact?.let { impact ->
                return impact > MAX_PRICE_IMPACT_VALUE
            }
            return false
        }
}
