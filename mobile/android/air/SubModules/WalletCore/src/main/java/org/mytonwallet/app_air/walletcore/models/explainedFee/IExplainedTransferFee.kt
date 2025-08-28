package org.mytonwallet.app_air.walletcore.models.explainedFee

import org.mytonwallet.app_air.walletcore.models.MFee
import java.math.BigInteger

interface IExplainedFee {
    /** Whether the result implies paying the fee with a diesel */
    val isGasless: Boolean

    /** The total fee required to execute the transfer (may be undefined) */
    val fullFee: MFee?

    /** The actual fee after deducting any excess (may be undefined) */
    val realFee: MFee?

    /** The excess part of the fee, in native token units (always approximate) */
    val excessFee: BigInteger
}
