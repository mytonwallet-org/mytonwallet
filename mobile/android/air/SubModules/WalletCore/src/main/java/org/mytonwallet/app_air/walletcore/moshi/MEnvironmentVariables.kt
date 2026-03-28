package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class MEnvironmentVariables(
    val appEnv: String,
    val appVersion: String,
    val isAndroidDirect: Boolean
)
