package org.mytonwallet.app_air.walletcore.moshi.explainedFee

import java.math.BigInteger

data class ExplainedSwapFee(
    override val isGasless: Boolean,
    override val fullFee: MFee? = null,
    override val realFee: MFee? = null,
    override val excessFee: BigInteger = BigInteger.ZERO
) : IExplainedFee {
    val networkFeeDetails: MExplainedTransferFee?
        get() {
            if (fullFee == null && realFee == null) return null

            return MExplainedTransferFee(
                isGasless = isGasless,
                fullFee = fullFee,
                realFee = realFee,
                excessFee = excessFee,
                canTransferFullBalance = false
            )
        }
}
