package org.mytonwallet.app_air.walletcore.models.explainedFee

import org.mytonwallet.app_air.walletcore.models.MFee
import java.math.BigInteger

data class ExplainedSwapFee(
    override val isGasless: Boolean,
    override val fullFee: MFee? = null,
    override val realFee: MFee? = null,
    override val excessFee: BigInteger = BigInteger.ZERO,
    val shouldShowOurFee: Boolean
) : IExplainedFee
