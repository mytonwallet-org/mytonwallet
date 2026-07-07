package org.mytonwallet.app_air.walletcore.models

import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType

data class MCardInfo(
    val all: Int,
    val notMinted: Int,
    val price: Double,
) {
    val isAvailable: Boolean
        get() = notMinted > 0
}

class MCardsInfo(private val byType: Map<ApiMtwCardType, MCardInfo>) {

    operator fun get(type: ApiMtwCardType): MCardInfo? = byType[type]

    companion object {
        private val typeByKey = mapOf(
            "black" to ApiMtwCardType.BLACK,
            "platinum" to ApiMtwCardType.PLATINUM,
            "gold" to ApiMtwCardType.GOLD,
            "silver" to ApiMtwCardType.SILVER,
            "standard" to ApiMtwCardType.STANDARD,
        )

        fun fromJson(json: JSONObject?): MCardsInfo? {
            if (json == null) return null
            val byType = HashMap<ApiMtwCardType, MCardInfo>()
            for ((key, type) in typeByKey) {
                val cardJson = json.optJSONObject(key) ?: continue
                byType[type] = MCardInfo(
                    all = cardJson.optInt("all"),
                    notMinted = cardJson.optInt("notMinted"),
                    price = cardJson.optDouble("price", 0.0),
                )
            }
            if (byType.isEmpty()) return null
            return MCardsInfo(byType)
        }
    }
}
