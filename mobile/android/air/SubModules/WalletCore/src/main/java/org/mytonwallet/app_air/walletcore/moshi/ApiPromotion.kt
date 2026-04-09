package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.WalletCore

@JsonClass(generateAdapter = true)
data class ApiPromotion(
    val id: String,
    val kind: String,
    val cardOverlay: CardOverlay,
    val modal: Modal? = null
) {

    companion object {
        fun fromJson(jsonObject: JSONObject): ApiPromotion? {
            return try {
                val adapter = WalletCore.moshi.adapter(ApiPromotion::class.java)
                adapter.fromJson(jsonObject.toString())
            } catch (_: Exception) {
                null
            }
        }
    }

    @JsonClass(generateAdapter = true)
    data class CardOverlay(
        val mascotIcon: MascotIcon? = null,
        val onClickAction: String
    ) {
        @JsonClass(generateAdapter = true)
        data class MascotIcon(
            val url: String,
            val top: Double,
            val right: Double,
            val height: Double,
            val width: Double,
            val rotation: Double
        )
    }

    @JsonClass(generateAdapter = true)
    data class Modal(
        val backgroundImageUrl: String,
        val backgroundFallback: String,
        val heroImageUrl: String? = null,
        val title: String,
        val titleColor: String? = null,
        val description: String,
        val descriptionColor: String? = null,
        val availabilityIndicator: String? = null,
        val actionButton: ActionButton? = null
    ) {
        @JsonClass(generateAdapter = true)
        data class ActionButton(
            val title: String,
            val url: String
        )
    }
}
