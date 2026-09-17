package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = false)
enum class MApiMarketSectionLayout {
    @Json(name = "largeHorizontal")
    LARGE_HORIZONTAL,

    @Json(name = "grid")
    GRID,

    @Json(name = "rows")
    ROWS
}

@JsonClass(generateAdapter = true)
data class MApiMarketAsset(
    val newBackendId: String,
    override val slug: String,
    override val name: String,
    override val symbol: String,
    override val chain: String? = null,
    override val image: String? = null,
    override val tokenAddress: String? = null,
    override val label: String? = null,
    override val keywords: List<String>? = null,
    override val decimals: Int = 9,
    override val isPopular: Boolean? = null,
    val price: Double? = null,
    val percentChange24h: Double? = null,
    val sparkline: List<Double>? = null,
    val tintColor: String? = null
) : IApiToken

@JsonClass(generateAdapter = true)
data class MApiMarketSection(
    val id: String,
    val title: String,
    val layout: MApiMarketSectionLayout? = null,
    val limit: Int? = null,
    val desktopLimit: Int? = null,
    val mobileLimit: Int? = null,
    val hasMore: Boolean = false,
    val assets: List<MApiMarketAsset> = emptyList()
)

@JsonClass(generateAdapter = true)
data class MApiMarketAssetsResponse(val sections: List<MApiMarketSection> = emptyList())
