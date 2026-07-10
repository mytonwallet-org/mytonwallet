package org.mytonwallet.app_air.uiswap.screens.swap.helpers

import org.mytonwallet.app_air.uiswap.screens.swap.DEFAULT_OUR_SWAP_FEE
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapEstimateResponse
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFee
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFeePrecision
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFeeTerms
import org.mytonwallet.app_air.walletcore.models.SwapType
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.ExplainedSwapFee
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus
import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode

class SwapHelpers {
    companion object {
        fun swapType(
            tokenToSend: IApiToken,
            tokenToReceive: IApiToken?,
            walletAddressByChain: Map<String, String>
        ): SwapType {
            return if (tokenToReceive == null) SwapType.ON_CHAIN else SwapType.from(
                tokenToSend,
                tokenToReceive,
                walletAddressByChain = walletAddressByChain
            )
        }

        fun isCex(
            tokenToSend: IApiToken?,
            tokenToReceive: IApiToken?
        ): Boolean {
            val token1 = tokenToSend ?: return false
            val token2 = tokenToReceive ?: return false

            val isOnchainSwap = token1.mBlockchain != null &&
                token1.mBlockchain == token2.mBlockchain &&
                token1.mBlockchain?.isOnchainSwapSupported == true
            return !isOnchainSwap
        }

        fun calcSwapMaxBalance(
            tokenToSend: IApiToken?,
            tokenToReceive: IApiToken?,
            addressByChain: Map<String, String>?,
            balances: Map<String, BigInteger>?,
            lastSwapEstimateResponse: SwapEstimateResponse?,
            fallbackToMax: Boolean = false
        ): BigInteger {
            val tokenToSend = tokenToSend ?: return BigInteger.ZERO
            val tokenBalance = balances?.get(tokenToSend.slug) ?: BigInteger.ZERO

            val swapType = swapType(
                tokenToSend,
                tokenToReceive,
                addressByChain ?: emptyMap()
            )

            val maxAmountFromBackend = if (lastSwapEstimateResponse?.request?.isFromAmountMax == true) {
                CoinUtils.fromDecimal(lastSwapEstimateResponse.dex?.fromAmount, tokenToSend.decimals)
            } else {
                null
            }
            if (maxAmountFromBackend != null) {
                return maxAmountFromBackend
            }

            if (swapType == SwapType.CROSS_CHAIN_TO_WALLET) {
                return if (fallbackToMax) tokenBalance else BigInteger.ZERO
            }

            var maxAmount = tokenBalance

            val networkTerms = lastSwapEstimateResponse?.explainedFee?.fullFee?.networkTerms
            networkTerms?.let {
                maxAmount -= it.token ?: BigInteger.ZERO

                if (tokenToSend.isBlockchainNative) {
                    maxAmount -= it.native ?: BigInteger.ZERO
                }
            }

            val shouldUseCexNativeFee = lastSwapEstimateResponse?.request?.isCex == true &&
                tokenToSend.isBlockchainNative &&
                networkTerms == null
            if (shouldUseCexNativeFee) {
                maxAmount -= lastSwapEstimateResponse?.fee ?: BigInteger.ZERO
            }

            val ourFeePercent = lastSwapEstimateResponse?.dex?.ourFeePercent
                ?: if (swapType == SwapType.ON_CHAIN) DEFAULT_OUR_SWAP_FEE else 0.0
            maxAmount = maxAmount.multiply(BigInteger.TEN.pow(9))
                .divide((1 + (ourFeePercent / 100)).toBigInteger(9))

            if (maxAmount <= BigInteger.ZERO) {
                return if (fallbackToMax && !shouldUseCexNativeFee) tokenBalance else BigInteger.ZERO
            }

            return maxAmount
        }

        fun explainApiSwapFee(
            swapEstimateResponse: SwapEstimateResponse
        ): ExplainedSwapFee {
            return if (swapEstimateResponse.request.isDiesel) {
                explainGaslessSwapFee(swapEstimateResponse)
            } else {
                explainGasfullSwapFee(swapEstimateResponse)
            }
        }

        private fun explainGaslessSwapFee(
            swapEstimateResponse: SwapEstimateResponse
        ): ExplainedSwapFee {
            val dex = swapEstimateResponse.dex ?: return ExplainedSwapFee(
                isGasless = true,
                shouldShowOurFee = swapEstimateResponse.request.tokenToSendIsSupported
            )

            val nativeBalance =
                swapEstimateResponse.request.nativeTokenToSendBalance.toBigDecimalOrNull()
                    ?: return ExplainedSwapFee(isGasless = true, shouldShowOurFee = true)
            val nativeBalanceBigInt = CoinUtils.fromDecimal(
                nativeBalance,
                swapEstimateResponse.request.nativeTokenToSend.decimals
            )

            val dieselFeeBigDecimal = dex.dieselFee?.toBigDecimalOrNull()
                ?: return ExplainedSwapFee(isGasless = true, shouldShowOurFee = true)
            val dieselFeeBigInt = CoinUtils.fromDecimal(
                dieselFeeBigDecimal,
                swapEstimateResponse.request.tokenToSend.decimals
            )

            val isExact = dex.realNetworkFee?.let {
                BigDecimal(dex.networkFee).subtract(it.toBigDecimal())
                    .compareTo(BigDecimal.ZERO) == 0
            } ?: false

            val dieselKey = if (dex.dieselStatus == MDieselStatus.STARS_FEE) "stars" else "token"
            val starsFee = if (dieselKey == "stars") dieselFeeBigInt else null
            val tokenFee = if (dieselKey == "token") dieselFeeBigInt else null

            val fullNetworkTerms = MFeeTerms(
                token = tokenFee,
                native = nativeBalanceBigInt,
                stars = starsFee
            )

            val fullFee = MFee(
                precision = if (isExact) MFeePrecision.EXACT else MFeePrecision.LESS_THAN,
                terms = fullNetworkTerms,
                nativeSum = fullNetworkTerms.native,
                networkTerms = fullNetworkTerms
            )

            val realFee = dex.realNetworkFee?.let { realNetFee ->
                val feeCoveredByDiesel = BigDecimal(dex.networkFee) - nativeBalance
                val realFeeInDiesel =
                    dieselFeeBigDecimal.divide(feeCoveredByDiesel, 18, RoundingMode.HALF_UP)
                        .multiply(realNetFee.toBigDecimal())
                val dieselRealFee = dieselFeeBigDecimal.min(realFeeInDiesel)
                val nativeRealFee =
                    (realNetFee.toBigDecimal() - feeCoveredByDiesel).coerceAtLeast(BigDecimal.ZERO)

                val nativeRealBigInt = CoinUtils.fromDecimal(
                    nativeRealFee,
                    swapEstimateResponse.request.nativeTokenToSend.decimals
                )
                val dieselRealBigInt = CoinUtils.fromDecimal(
                    dieselRealFee,
                    swapEstimateResponse.request.tokenToSend.decimals
                )

                val realNetworkTerms = MFeeTerms(
                    token = if (dieselKey == "token") dieselRealBigInt else null,
                    stars = if (dieselKey == "stars") dieselRealBigInt else null,
                    native = nativeRealBigInt
                )

                MFee(
                    precision = if (isExact) MFeePrecision.EXACT else MFeePrecision.APPROXIMATE,
                    terms = realNetworkTerms,
                    nativeSum = nativeRealBigInt,
                    networkTerms = realNetworkTerms
                )
            }

            return ExplainedSwapFee(
                isGasless = true,
                excessFee = dex.realNetworkFee?.let {
                    CoinUtils.fromDecimal(
                        BigDecimal(dex.networkFee) - it.toBigDecimal(),
                        swapEstimateResponse.request.nativeTokenToSend.decimals
                    )
                } ?: BigInteger.ZERO,
                fullFee = fullFee,
                realFee = realFee,
                shouldShowOurFee = swapEstimateResponse.request.tokenToSendIsSupported
            )
        }

        private fun explainGasfullSwapFee(
            swapEstimateResponse: SwapEstimateResponse
        ): ExplainedSwapFee {
            val dex = swapEstimateResponse.dex ?: return ExplainedSwapFee(
                isGasless = false,
                shouldShowOurFee = swapEstimateResponse.request.tokenToSendIsSupported
            )

            val networkFee = BigDecimal(dex.networkFee)
            val realNetworkFee =
                if (dex.realNetworkFee != null) BigDecimal(dex.realNetworkFee!!) else null
            val isExact =
                realNetworkFee?.let { networkFee.subtract(it).compareTo(BigDecimal.ZERO) == 0 }
                    ?: false
            val precision = if (isExact) MFeePrecision.EXACT else MFeePrecision.LESS_THAN

            val nativeFeeBigInt = CoinUtils.fromDecimal(
                networkFee,
                swapEstimateResponse.request.nativeTokenToSend.decimals
            ) ?: BigInteger.ZERO

            val realNativeFeeBigInt = realNetworkFee?.let {
                CoinUtils.fromDecimal(it, swapEstimateResponse.request.nativeTokenToSend.decimals)
            }

            val isNative = swapEstimateResponse.request.tokenToSend.isBlockchainNative

            val networkTerms = MFeeTerms(
                token = null,
                native = nativeFeeBigInt,
                stars = null
            )

            val fullTerms = MFeeTerms(
                token = if (!isNative) dex.ourFee?.toBigDecimalOrNull()?.let {
                    CoinUtils.fromDecimal(it, swapEstimateResponse.request.tokenToSend.decimals)
                } else null,
                native = if (isNative) dex.ourFee?.toBigDecimalOrNull()?.let {
                    nativeFeeBigInt + (CoinUtils.fromDecimal(
                        it,
                        swapEstimateResponse.request.nativeTokenToSend.decimals
                    ) ?: BigInteger.ZERO)
                } ?: nativeFeeBigInt else nativeFeeBigInt,
                stars = null
            )

            val fullFee = MFee(
                precision = precision,
                terms = fullTerms,
                nativeSum = fullTerms.native,
                networkTerms = networkTerms
            )

            val realTerms = realNativeFeeBigInt?.let {
                MFeeTerms(
                    token = fullTerms.token,
                    native = fullTerms.native?.minus(nativeFeeBigInt - it),
                    stars = null
                )
            }

            val realNetworkTerms = realNativeFeeBigInt?.let {
                MFeeTerms(
                    token = null,
                    native = it,
                    stars = null
                )
            }

            val realFee = realTerms?.let {
                MFee(
                    precision = if (isExact) MFeePrecision.EXACT else MFeePrecision.APPROXIMATE,
                    terms = it,
                    nativeSum = it.native,
                    networkTerms = realNetworkTerms
                )
            }

            return ExplainedSwapFee(
                isGasless = false,
                excessFee = realNativeFeeBigInt?.let { (nativeFeeBigInt - it) } ?: BigInteger.ZERO,
                fullFee = fullFee,
                realFee = realFee,
                shouldShowOurFee = swapEstimateResponse.request.tokenToSendIsSupported
            )
        }
    }
}
