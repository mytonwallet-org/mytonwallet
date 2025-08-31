package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import java.math.BigInteger

@JsonClass(generateAdapter = true)
data class MSubmitStakeResponse(
    val amount: BigInteger,
    val seqno: Int,
    val toAddress: String,
    val msgHash: String,
    val txId: String
)
