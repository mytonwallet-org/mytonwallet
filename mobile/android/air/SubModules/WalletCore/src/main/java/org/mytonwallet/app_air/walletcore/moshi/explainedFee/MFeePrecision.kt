package org.mytonwallet.app_air.walletcore.moshi.explainedFee

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = false)
enum class MFeePrecision(val prefix: String) {
    @Json(name = "exact")
    EXACT(""),

    @Json(name = "approximate")
    APPROXIMATE("~"),

    @Json(name = "lessThan")
    LESS_THAN("<");
}
