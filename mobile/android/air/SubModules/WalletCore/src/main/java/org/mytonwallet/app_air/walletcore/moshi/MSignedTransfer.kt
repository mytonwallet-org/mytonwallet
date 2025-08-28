package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class MApiSignedTransfer(
    val base64: String,
    val seqno: Int,
    val localActivity: MApiLocalTransactionParams
)
