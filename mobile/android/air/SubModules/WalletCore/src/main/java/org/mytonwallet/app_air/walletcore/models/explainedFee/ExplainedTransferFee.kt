package org.mytonwallet.app_air.walletcore.models.explainedFee

import org.mytonwallet.app_air.walletcore.models.MFee
import java.math.BigInteger

data class ExplainedTransferFee(
    override val isGasless: Boolean,
    override val fullFee: MFee?,
    override val realFee: MFee?,
    override val excessFee: BigInteger,
    /** Whether the entire token balance can be transferred despite the fee */
    val canTransferFullBalance: Boolean,
) : IExplainedFee
