package org.mytonwallet.app_air.walletcore.moshi.explainedFee

import com.squareup.moshi.JsonClass
import java.math.BigInteger

@JsonClass(generateAdapter = true)
data class MExplainedTransferFee(
    override val isGasless: Boolean,
    override val fullFee: MFee?,
    override val realFee: MFee?,
    override val excessFee: BigInteger = BigInteger.ZERO,
    /** Whether the entire token balance can be transferred despite the fee */
    val canTransferFullBalance: Boolean,
) : IExplainedFee {

    val supportsLegacyDetailsView: Boolean
        get() = realFee?.precision != MFeePrecision.EXACT
            && fullFee?.isNativeOnly == true
            && realFee?.isNativeOnly == true
}
