package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletcore.moshi.adapter.factory.JsonSealed
import org.mytonwallet.app_air.walletcore.moshi.adapter.factory.JsonSealedSubtype

@JsonSealed("type")
sealed class MSignDataPayload {

    @JsonSealedSubtype("text")
    @JsonClass(generateAdapter = true)
    data class SignDataPayloadText(
        val text: String
    ) : MSignDataPayload()

    @JsonSealedSubtype("binary")
    @JsonClass(generateAdapter = true)
    data class SignDataPayloadBinary(
        val bytes: String
    ) : MSignDataPayload()

    @JsonSealedSubtype("cell")
    @JsonClass(generateAdapter = true)
    data class SignDataPayloadCell(
        val schema: String,
        val cell: String
    ) : MSignDataPayload()
}
