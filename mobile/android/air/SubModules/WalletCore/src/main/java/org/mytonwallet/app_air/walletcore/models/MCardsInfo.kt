package org.mytonwallet.app_air.walletcore.models

import java.text.SimpleDateFormat
import java.util.Locale
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType

data class MCardInfo(
    val all: Int,
    val notMinted: Int,
    val price: Double,
    val startsAt: String? = null
) {
    val isAvailable: Boolean
        get() = notMinted > 0

    val mintStartsAtMillis: Long? by lazy {
        if (notMinted != 0 || startsAt == null) return@lazy null
        val match = ISO_DATE_TIME.matchEntire(startsAt) ?: return@lazy null
        val fraction = match.groupValues[2].padEnd(3, '0').take(3)
        val normalized = "${match.groupValues[1]}.$fraction${match.groupValues[3]}"
        runCatching {
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US).apply {
                isLenient = false
            }.parse(normalized)?.time
        }.getOrNull()
    }

    companion object {
        private val ISO_DATE_TIME =
            Regex(
                "^(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2})(?:\\.(\\d+))?(Z|[+-]\\d{2}:\\d{2})$"
            )
    }
}

class MCardsInfo(private val byType: Map<ApiMtwCardType, MCardInfo>) {

    operator fun get(type: ApiMtwCardType): MCardInfo? = byType[type]

    companion object {
        private val typeByKey = mapOf(
            "black" to ApiMtwCardType.BLACK,
            "platinum" to ApiMtwCardType.PLATINUM,
            "gold" to ApiMtwCardType.GOLD,
            "silver" to ApiMtwCardType.SILVER,
            "standard" to ApiMtwCardType.STANDARD
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
                    startsAt = cardJson.optString("startsAt").takeIf { it.isNotEmpty() }
                )
            }
            if (byType.isEmpty()) return null
            return MCardsInfo(byType)
        }
    }
}
