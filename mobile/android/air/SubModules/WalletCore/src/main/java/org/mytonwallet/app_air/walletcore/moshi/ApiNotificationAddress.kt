package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain

@JsonClass(generateAdapter = true)
data class ApiNotificationAddress(
    val title: String?,
    val address: String,
    val chain: MBlockchain
)
