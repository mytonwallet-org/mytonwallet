package org.mytonwallet.app_air.walletcore.moshi

import android.net.Uri
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import java.math.BigInteger

@JsonClass(generateAdapter = true)
data class DeviceInfo(
    val platform: String,
    val appName: String,
    val appVersion: String,
    val maxProtocolVersion: Int,
    val features: List<Any>
) {
    object Feature {
        @JsonClass(generateAdapter = true)
        data class SendTransaction(
            val name: String = "SendTransaction",
            val maxMessages: Int
        )
    }
}

@JsonClass(generateAdapter = true)
data class ApiDapp(
    val url: String?,
    val name: String?,
    val iconUrl: String?,
    val manifestUrl: String?,
    val connectedAt: Long?,
    val isUrlEnsured: Boolean?,
    val sse: ApiSseOptions? = null
) {
    val host: String? = try {
        Uri.parse(url).host
    } catch (_: Throwable) {
        null
    }
}

@JsonClass(generateAdapter = true)
data class ApiSseOptions(
    val clientId: String,
    val appClientId: String,
    val secretKey: String,
    val lastOutputId: Long
)

@JsonClass(generateAdapter = true)
data class ApiTransferToSign(
    val toAddress: String,
    val amount: BigInteger,
    val rawPayload: String? = null,
    val payload: ApiParsedPayload? = null,
    val stateInit: String? = null,
)

@JsonClass(generateAdapter = true)
data class ApiDappTransfer(
    val toAddress: String,
    val amount: BigInteger,
    val rawPayload: String? = null,
    val payload: ApiParsedPayload? = null,
    val stateInit: String? = null,
    val isScam: Boolean? = null,
    val isDangerous: Boolean = false,
    val normalizedAddress: String,
    val displayedToAddress: String,
    val networkFee: BigInteger
)

@JsonClass(generateAdapter = true)
data class ApiTonConnectProof(
    val timestamp: Long,
    val domain: String,
    val payload: String
)

@JsonClass(generateAdapter = false)
enum class ApiConnectionType {
    @Json(name = "connect")
    CONNECT,

    @Json(name = "sendTransaction")
    SEND_TRANSACTION
}

sealed class ReturnStrategy {
    object None : ReturnStrategy()
    object Back : ReturnStrategy()
    data class Url(val url: String) : ReturnStrategy()
}



