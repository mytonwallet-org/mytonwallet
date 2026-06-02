package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class ApiSubmitTransferResult(
    val activityId: String? = null,
    val swapId: String? = null,
    val mfaRequestHash: String? = null,
    val error: String? = null,
)

@JsonClass(generateAdapter = true)
data class ApiSubmitTransfersResult(
    val activityIds: List<String>? = null,
    val mfaRequestHash: String? = null,
)
