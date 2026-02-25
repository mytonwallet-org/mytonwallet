package org.mytonwallet.app_air.walletcore.moshi.inject

import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload
import org.mytonwallet.app_air.walletcore.moshi.TonConnectConnectRequest
import org.mytonwallet.app_air.walletcore.moshi.TonConnectTransactionPayload

@JsonClass(generateAdapter = true)
data class ApiDappPermissions(
    val isAddressRequired: Boolean? = null,
    val isPasswordRequired: Boolean? = null
)

@JsonClass(generateAdapter = true)
data class ApiDappRequestedChain(
    val chain: String,
    val network: String
)

@JsonClass(generateAdapter = true)
data class ApiDappConnectionRequest(
    val protocolType: String,
    val transport: String,
    val protocolData: TonConnectConnectRequest,
    val permissions: ApiDappPermissions,
    val requestedChains: List<ApiDappRequestedChain>
)

@JsonClass(generateAdapter = true)
data class ApiDappDisconnectRequest(
    val requestId: String
)

@JsonClass(generateAdapter = true)
data class ApiDappTransactionRequest(
    val id: String,
    val chain: String,
    val payload: TonConnectTransactionPayload
)

@JsonClass(generateAdapter = true)
data class ApiDappSignDataRequest(
    val id: String,
    val chain: String,
    val payload: MSignDataPayload
)

@JsonClass(generateAdapter = true)
data class ApiDappSessionChain(
    val chain: String,
    val address: String,
    val network: String,
    val publicKey: String? = null
)
