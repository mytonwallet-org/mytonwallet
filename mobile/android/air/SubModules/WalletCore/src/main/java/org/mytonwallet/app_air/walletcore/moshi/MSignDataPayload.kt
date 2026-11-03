package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass

sealed class MSignDataPayload {

    @JsonClass(generateAdapter = true)
    data class SignDataPayloadText(val text: String) : MSignDataPayload()

    @JsonClass(generateAdapter = true)
    data class SignDataPayloadBinary(val bytes: String) : MSignDataPayload()

    @JsonClass(generateAdapter = true)
    data class SignDataPayloadCell(val schema: String, val cell: String) : MSignDataPayload()

    @JsonClass(generateAdapter = true)
    data class SignDataPayloadEip712(
        val domain: Map<String, Any?>,
        val types: Map<String, List<TypeField>>,
        val primaryType: String,
        val message: Map<String, Any?>,
        // Network whose chain id `domain.chainId` must match; the SDK checks it again when signing
        val network: String? = null
    ) : MSignDataPayload() {
        @JsonClass(generateAdapter = true)
        data class TypeField(val name: String, val type: String)
    }
}
