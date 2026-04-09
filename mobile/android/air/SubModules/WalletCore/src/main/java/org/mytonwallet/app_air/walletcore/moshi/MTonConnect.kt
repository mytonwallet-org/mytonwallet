package org.mytonwallet.app_air.walletcore.moshi

import android.net.Uri
import androidx.core.net.toUri
import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletbasecontext.utils.toUriOrNull
import java.math.BigInteger
import org.mytonwallet.app_air.walletbasecontext.utils.decodeUrlOrNull

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

interface IDapp {
    val url: String?
    val name: String?
    val iconUrl: String?
}

@JsonClass(generateAdapter = true)
data class ApiDapp(
    override val url: String?,
    override val name: String?,
    override val iconUrl: String?,
    val manifestUrl: String?,
    val connectedAt: Long?,
    val isUrlEnsured: Boolean?,
    val sse: ApiSseOptions? = null
) : IDapp {
    val host: String? = try {
        url?.toUri()?.host
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
    SEND_TRANSACTION,

    @Json(name = "signData")
    SIGN_DATA
}

sealed class ReturnStrategy {
    object None : ReturnStrategy()
    object Back : ReturnStrategy()
    object Empty : ReturnStrategy()
    data class Url(val url: String) : ReturnStrategy() {

        val uri: Uri? by lazy {
            if (url.isBlank()) {
                return@lazy null
            }
            url.decodeUrlOrNull()?.toUriOrNull() ?: url.toUriOrNull()
        }
    }
}
