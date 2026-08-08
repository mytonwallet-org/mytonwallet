package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class MApiTokenDetails(val slug: String, val tokenInfo: TokenInfo? = null) {
    @JsonClass(generateAdapter = true)
    data class TokenInfo(
        val description: String? = null,
        val localizedDescription: String? = null,
        val marketCap: Double? = null,
        val supply: Supply? = null,
        val createdAt: String? = null,
        val volume24h: Volume? = null,
        val links: List<Link>? = null,
        val aggregatorLinks: List<AggregatorLink>? = null,
        val docsUrl: String? = null,
        val sourceCodeUrl: String? = null
    ) {
        val originalDescriptionText: String?
            get() = description.notBlankOrNull()

        val localizedDescriptionText: String?
            get() = localizedDescription.notBlankOrNull()

        val displayDescription: String?
            get() = localizedDescriptionText ?: originalDescriptionText

        val hasPublicInformation: Boolean
            get() = displayDescription != null ||
                links?.any { it.url.isNotBlank() } == true ||
                marketCap != null ||
                supply?.circulating != null ||
                supply?.total != null ||
                createdAt != null ||
                volume24h != null
    }

    @JsonClass(generateAdapter = true)
    data class Supply(val circulating: Double? = null, val total: Double? = null)

    @JsonClass(generateAdapter = true)
    data class Volume(val sell: Double, val buy: Double, val percentChange: Double? = null)

    @JsonClass(generateAdapter = true)
    data class Link(val url: String, val type: String? = null)

    @JsonClass(generateAdapter = true)
    data class AggregatorLink(val url: String, val name: String)
}

private fun String?.notBlankOrNull() = this?.trim()?.takeIf { it.isNotEmpty() }
