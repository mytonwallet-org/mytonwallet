package org.mytonwallet.app_air.walletcore.moshi.explainedFee

import com.squareup.moshi.JsonClass
import java.math.BigInteger

@JsonClass(generateAdapter = true)
data class MFeeTerms(
    /** The fee part paid in the transferred token */
    val token: BigInteger?,

    /** The fee part paid in the chain's native token */
    val native: BigInteger?,

    /**
     * The fee part paid in stars.
     * The BigInteger assumes the same number of decimal places as the transferred token.
     */
    val stars: BigInteger?
)
