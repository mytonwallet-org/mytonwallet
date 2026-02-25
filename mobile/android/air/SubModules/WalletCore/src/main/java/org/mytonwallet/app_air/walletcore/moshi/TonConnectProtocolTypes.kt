package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class TonConnectConnectRequest(
    val manifestUrl: String,
    val items: List<TonConnectConnectItem>
)

@JsonClass(generateAdapter = true)
data class TonConnectConnectItem(
    val name: String,
    val payload: String? = null
)

@JsonClass(generateAdapter = true)
data class TonConnectTransactionPayload(
    @Json(name = "valid_until") val validUntil: Long? = null,
    val network: String? = null,
    val from: String? = null,
    val messages: List<TonConnectTransactionMessage>
)

@JsonClass(generateAdapter = true)
data class TonConnectTransactionMessage(
    val address: String,
    val amount: String,
    val payload: String? = null,
    val stateInit: String? = null
)
