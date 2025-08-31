package org.mytonwallet.app_air.uisend.send.helpers

import org.mytonwallet.app_air.walletcore.models.MFee
import org.mytonwallet.app_air.walletcore.models.explainedFee.ExplainedTransferFee
import org.mytonwallet.app_air.walletcore.moshi.IDiesel
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus
import java.math.BigInteger

class TransferHelpers private constructor() {

    companion object {
        private fun shouldUseDiesel(input: MApiCheckTransactionDraftResult): Boolean {
            return input.diesel != null && input.diesel?.status != MDieselStatus.NOT_AVAILABLE && input.diesel?.tokenAmount != null
        }

        fun explainApiTransferFee(
            chain: String,
            isNativeToken: Boolean,
            input: MApiCheckTransactionDraftResult
        ): ExplainedTransferFee {
            return if (shouldUseDiesel(input)) {
                explainGaslessTransferFee(input.diesel!!)
            } else {
                explainGasfullTransferFee(chain, isNativeToken, input)
            }
        }

        private fun explainGaslessTransferFee(diesel: IDiesel): ExplainedTransferFee {
            val isStarsDiesel = diesel.status == MDieselStatus.STARS_FEE
            val dieselAmount = if (isStarsDiesel) diesel.starsAmount!! else diesel.tokenAmount!!
            val realFeeInToken =
                convertFee(
                    diesel.realFee ?: BigInteger.ZERO,
                    diesel.nativeAmount!!,
                    dieselAmount
                )
            val tokenRealFee = minOf(dieselAmount, realFeeInToken)
            val nativeRealFee =
                convertFee(
                    realFeeInToken - tokenRealFee,
                    dieselAmount,
                    diesel.nativeAmount ?: BigInteger.ZERO
                )

            return ExplainedTransferFee(
                isGasless = true,
                fullFee = MFee(
                    precision = MFee.FeePrecision.LESS_THAN,
                    terms = MFee.FeeTerms(
                        token = diesel.tokenAmount,
                        native = diesel.remainingFee,
                        stars = diesel.starsAmount
                    ),
                    nativeSum = (diesel.nativeAmount ?: BigInteger.ZERO) +
                        (diesel.remainingFee ?: BigInteger.ZERO),
                ),
                realFee = MFee(
                    precision = MFee.FeePrecision.APPROXIMATE,
                    terms = MFee.FeeTerms(
                        token = if (isStarsDiesel) null else tokenRealFee,
                        native = nativeRealFee,
                        stars = if (isStarsDiesel) tokenRealFee else null
                    ),
                    nativeSum = diesel.realFee
                ),
                canTransferFullBalance = false,
                excessFee = (diesel.nativeAmount ?: BigInteger.ZERO) +
                    (diesel.remainingFee ?: BigInteger.ZERO) -
                    (diesel.realFee ?: BigInteger.ZERO)
            )
        }

        private fun explainGasfullTransferFee(
            chain: String,
            isNativeToken: Boolean,
            input: MApiCheckTransactionDraftResult
        ): ExplainedTransferFee {
            val fullFee = MFee(
                precision = if (input.realFee == input.fee) MFee.FeePrecision.EXACT else MFee.FeePrecision.LESS_THAN,
                terms = MFee.FeeTerms(
                    token = null,
                    native = input.fee,
                    stars = null
                ),
                nativeSum = input.fee
            )

            return ExplainedTransferFee(
                isGasless = false,
                fullFee = input.fee?.let { fullFee },
                realFee = input.realFee?.let {
                    MFee(
                        precision = if (input.realFee == input.fee) MFee.FeePrecision.EXACT else MFee.FeePrecision.APPROXIMATE,
                        terms = MFee.FeeTerms(
                            token = null,
                            native = input.realFee,
                            stars = null,
                        ),
                        nativeSum = input.realFee
                    )
                } ?: fullFee,
                canTransferFullBalance = chain == "ton" && isNativeToken,
                excessFee = (input.fee ?: BigInteger.ZERO) - (input.realFee ?: BigInteger.ZERO)
            )
        }

        private fun convertFee(
            amount: BigInteger,
            exampleFromAmount: BigInteger,
            exampleToAmount: BigInteger
        ): BigInteger {
            return amount * exampleToAmount / exampleFromAmount
        }

        fun getMaxTransferAmount(
            tokenBalance: BigInteger?,
            isNativeToken: Boolean,
            fullFee: MFee.FeeTerms?,
            canTransferFullBalance: Boolean
        ): BigInteger? {
            if (tokenBalance == null || tokenBalance <= BigInteger.ZERO) {
                return null
            }

            if (canTransferFullBalance || fullFee == null) {
                return null
            }

            var fee = fullFee.token ?: BigInteger.ZERO
            if (isNativeToken) {
                fee += fullFee.native ?: BigInteger.ZERO
            }
            return maxOf(tokenBalance - fee, BigInteger.ZERO)
        }
    }
}
