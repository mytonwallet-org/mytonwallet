package org.mytonwallet.app_air.uiswap.screens.swap.helpers

import org.mytonwallet.app_air.uiswap.screens.swap.DEFAULT_OUR_SWAP_FEE
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapEstimateResponse
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.helpers.FeeEstimationHelpers
import org.mytonwallet.app_air.walletcore.models.MFee
import org.mytonwallet.app_air.walletcore.models.SwapType
import org.mytonwallet.app_air.walletcore.models.explainedFee.ExplainedSwapFee
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

            return !token1.isTonOrJetton || !token2.isTonOrJetton
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
            val tokenToReceive = tokenToReceive
            var balance = balances?.get(tokenToSend.slug) ?: BigInteger.ZERO

            val swapType = swapType(
                tokenToSend,
                tokenToReceive,
                addressByChain ?: emptyMap()
            )
            if (tokenToSend.mBlockchain?.nativeSlug == tokenToSend.slug) {
                val networkFeeData =
                    FeeEstimationHelpers.networkFeeData(
                        tokenToSend,
                        lastSwapEstimateResponse?.request?.wallet?.isSupportedChain(tokenToSend.mBlockchain) == true,
                        swapType,
                        lastSwapEstimateResponse?.dex?.networkFee
                            ?: lastSwapEstimateResponse?.fee?.doubleAbsRepresentation(tokenToSend.nativeToken?.decimals)
                    )
                balance -= CoinUtils.fromDecimal(networkFeeData?.fee, tokenToSend.decimals)
                    ?: BigInteger.ZERO
            }

            tokenToReceive?.let {
                if (swapType == SwapType.ON_CHAIN) {
                    lastSwapEstimateResponse?.dex?.dieselFee?.toDouble()?.let {
                        balance -= it.toBigInteger(tokenToSend.decimals)!!
                    }

                    val ourFeePercent =
                        lastSwapEstimateResponse?.dex?.ourFeePercent ?: DEFAULT_OUR_SWAP_FEE
                    balance = balance.multiply(BigInteger.TEN.pow(9))
                        .divide((1 + (ourFeePercent / 100)).toBigInteger(9))
                }
            }

            if (balance <= BigInteger.ZERO) {
                return if (fallbackToMax) balances?.get(tokenToSend.slug)
                    ?: BigInteger.ZERO else BigInteger.ZERO
            }

            return balance
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

            val fullNetworkTerms = MFee.FeeTerms(
                token = tokenFee,
                native = nativeBalanceBigInt,
                stars = starsFee
            )

            val fullFee = MFee(
                precision = if (isExact) MFee.FeePrecision.EXACT else MFee.FeePrecision.LESS_THAN,
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

                val realNetworkTerms = MFee.FeeTerms(
                    token = if (dieselKey == "token") dieselRealBigInt else null,
                    stars = if (dieselKey == "stars") dieselRealBigInt else null,
                    native = nativeRealBigInt
                )

                MFee(
                    precision = if (isExact) MFee.FeePrecision.EXACT else MFee.FeePrecision.APPROXIMATE,
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
            val precision = if (isExact) MFee.FeePrecision.EXACT else MFee.FeePrecision.LESS_THAN

            val nativeFeeBigInt = CoinUtils.fromDecimal(
                networkFee,
                swapEstimateResponse.request.nativeTokenToSend.decimals
            ) ?: BigInteger.ZERO

            val realNativeFeeBigInt = realNetworkFee?.let {
                CoinUtils.fromDecimal(it, swapEstimateResponse.request.nativeTokenToSend.decimals)
            }

            val isNative = swapEstimateResponse.request.tokenToSend.isBlockchainNative

            val networkTerms = MFee.FeeTerms(
                token = null,
                native = nativeFeeBigInt,
                stars = null
            )

            val fullTerms = MFee.FeeTerms(
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
                MFee.FeeTerms(
                    token = fullTerms.token,
                    native = fullTerms.native?.minus(nativeFeeBigInt - it),
                    stars = null
                )
            }

            val realNetworkTerms = realNativeFeeBigInt?.let {
                MFee.FeeTerms(
                    token = null,
                    native = it,
                    stars = null
                )
            }

            val realFee = realTerms?.let {
                MFee(
                    precision = if (isExact) MFee.FeePrecision.EXACT else MFee.FeePrecision.APPROXIMATE,
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
