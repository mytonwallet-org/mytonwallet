package org.mytonwallet.app_air.uiswap.screens.swap.helpers

import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapEstimateResponse
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.models.SwapType
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.ExplainedSwapFee
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFee
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFeePrecision
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFeeTerms

internal data class SwapDefaultTokens(
    val tokenToSend: MApiSwapAsset?,
    val tokenToReceive: MApiSwapAsset?
)

class SwapHelpers {
    companion object {
        internal fun resolveDefaultTokens(
            assets: List<MApiSwapAsset>,
            defaultSendingToken: MApiSwapAsset?,
            defaultReceivingToken: MApiSwapAsset?
        ): SwapDefaultTokens {
            val tokenToSend = defaultSendingToken ?: run {
                val slug = if (defaultReceivingToken?.slug == TONCOIN_SLUG) {
                    TON_USDT_SLUG
                } else {
                    TONCOIN_SLUG
                }
                assets.firstOrNull { it.slug == slug }
            }
            val tokenToReceive = defaultReceivingToken ?: run {
                val slug = if (tokenToSend?.slug == TON_USDT_SLUG) {
                    TONCOIN_SLUG
                } else {
                    TON_USDT_SLUG
                }
                assets.firstOrNull { it.slug == slug }
            }

            return SwapDefaultTokens(tokenToSend, tokenToReceive)
        }

        fun swapType(
            tokenToSend: IApiToken,
            tokenToReceive: IApiToken?,
            walletAddressByChain: Map<String, String>
        ): SwapType = if (tokenToReceive == null) {
            SwapType.ON_CHAIN
        } else {
            SwapType.from(
                tokenToSend,
                tokenToReceive,
                walletAddressByChain = walletAddressByChain
            )
        }

        fun isCex(tokenToSend: IApiToken?, tokenToReceive: IApiToken?): Boolean {
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

            val maxAmountFromBackend = if (lastSwapEstimateResponse?.request?.isFromAmountMax ==
                true
            ) {
                CoinUtils.fromDecimal(
                    lastSwapEstimateResponse.dex?.fromAmount,
                    tokenToSend.decimals
                )
            } else {
                null
            }
            val networkTerms = lastSwapEstimateResponse?.explainedFee?.fullFee?.networkTerms

            return calcSwapMaxBalanceFromInputs(
                swapType = swapType,
                tokenBalance = tokenBalance,
                isNativeToken = tokenToSend.isBlockchainNative,
                networkTerms = networkTerms,
                isCex = lastSwapEstimateResponse?.request?.isCex == true,
                cexNativeFee = lastSwapEstimateResponse?.fee,
                maxAmountFromBackend = maxAmountFromBackend,
                fallbackToMax = fallbackToMax
            )
        }

        internal fun calcSwapMaxBalanceFromInputs(
            swapType: SwapType,
            tokenBalance: BigInteger,
            isNativeToken: Boolean,
            networkTerms: MFeeTerms?,
            isCex: Boolean,
            cexNativeFee: BigInteger?,
            maxAmountFromBackend: BigInteger?,
            fallbackToMax: Boolean = false
        ): BigInteger {
            if (maxAmountFromBackend != null) {
                return maxAmountFromBackend
            }

            if (swapType == SwapType.CROSS_CHAIN_TO_WALLET) {
                return if (fallbackToMax) tokenBalance else BigInteger.ZERO
            }

            var maxAmount = tokenBalance

            networkTerms?.let {
                if (swapType != SwapType.ON_CHAIN) {
                    maxAmount -= it.token ?: BigInteger.ZERO
                }

                if (isNativeToken) {
                    maxAmount -= it.native ?: BigInteger.ZERO
                }
            }

            val shouldUseCexNativeFee = isCex && isNativeToken && networkTerms == null
            if (shouldUseCexNativeFee) {
                maxAmount -= cexNativeFee ?: BigInteger.ZERO
            }

            if (maxAmount <= BigInteger.ZERO) {
                return if (fallbackToMax &&
                    !shouldUseCexNativeFee
                ) {
                    tokenBalance
                } else {
                    BigInteger.ZERO
                }
            }

            return maxAmount
        }

        fun explainApiSwapFee(swapEstimateResponse: SwapEstimateResponse): ExplainedSwapFee =
            if (swapEstimateResponse.request.isDiesel) {
                explainGaslessSwapFee(swapEstimateResponse)
            } else {
                explainGasfullSwapFee(swapEstimateResponse)
            }

        private fun explainGaslessSwapFee(
            swapEstimateResponse: SwapEstimateResponse
        ): ExplainedSwapFee {
            val dex = swapEstimateResponse.dex ?: return ExplainedSwapFee(isGasless = true)

            val nativeBalance =
                swapEstimateResponse.request.nativeTokenToSendBalance.toBigDecimalOrNull()
                    ?: return ExplainedSwapFee(isGasless = true)
            val nativeBalanceBigInt = CoinUtils.fromDecimal(
                nativeBalance,
                swapEstimateResponse.request.nativeTokenToSend.decimals
            )

            val dieselFeeBigDecimal = dex.dieselFee?.toBigDecimalOrNull()
                ?: return ExplainedSwapFee(isGasless = true)
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
                realFee = realFee
            )
        }

        private fun explainGasfullSwapFee(
            swapEstimateResponse: SwapEstimateResponse
        ): ExplainedSwapFee {
            val dex = swapEstimateResponse.dex ?: return ExplainedSwapFee(isGasless = false)

            val networkFee = BigDecimal(dex.networkFee)
            val realNetworkFee = dex.realNetworkFee?.let(::BigDecimal)
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

            val networkTerms = MFeeTerms(
                token = null,
                native = nativeFeeBigInt,
                stars = null
            )

            val fullTerms = MFeeTerms(
                token = null,
                native = nativeFeeBigInt,
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
                realFee = realFee
            )
        }
    }
}
