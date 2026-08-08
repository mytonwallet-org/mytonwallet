package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class MApiGetAddressInfoResult(
    val resolvedAddress: String? = null,
    val addressName: String? = null,
    val isMemoRequired: Boolean? = null,
    val isScam: Boolean? = null,
    val isBounceable: Boolean? = null,
    val error: MApiAnyDisplayError? = null
)
