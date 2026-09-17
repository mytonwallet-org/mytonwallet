package org.mytonwallet.app_air.uimarket.viewControllers.market

import androidx.core.graphics.toColorInt
import java.math.BigDecimal
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletbasecontext.utils.withLocalizedNumbers
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.ApiTokenWithPrice
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiMarketAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiMarketSection
import org.mytonwallet.app_air.walletcore.moshi.MApiMarketSectionLayout

data class MarketToken(val token: IApiToken, val asset: MApiMarketAsset) {
    data class Chart(val tint: Int, val points: List<Float>)

    val id: String
        get() = token.slug

    val name: String
        get() = token.displayName?.takeIf { it.isNotBlank() }
            ?: token.symbol?.takeIf { it.isNotBlank() }
            ?: token.slug

    val symbol: String
        get() = token.symbol?.takeIf { it.isNotBlank() } ?: name

    val price: Double?
        get() = when (token) {
            is MToken -> token.price
            is ApiTokenWithPrice -> token.price
            else -> null
        } ?: asset.price

    val change: Double
        get() = when (token) {
            is MToken -> token.percentChange24h.takeIf { it.isFinite() }
            is ApiTokenWithPrice -> token.percentChange24h?.takeIf { it.isFinite() }
            else -> null
        } ?: asset.percentChange24h ?: 0.0

    val chart: Chart? by lazy { buildChart() }

    val isPositive: Boolean
        get() = change >= 0

    val changeText: String
        get() {
            val value = BigDecimal.valueOf(change).stripTrailingZeros().toPlainString()
            return "\u202D${if (change > 0) "+" else ""}${value.withLocalizedNumbers}%"
        }

    val priceText: String?
        get() = price?.toString(
            decimals = 9,
            currency = WalletCore.baseCurrency.sign,
            currencyDecimals = WalletCore.baseCurrency.decimalsCount,
            smartDecimals = true,
            forceCurrencyToRight = false,
            localizedDigits = false
        )

    fun matches(query: String): Boolean {
        val normalized = query.trim()
        return normalized.isEmpty() || token.matchesSearch(normalized)
    }

    private fun buildChart(): Chart? {
        val sparkline = asset.sparkline?.filter { it.isFinite() } ?: return null
        if (sparkline.size < 2) return null
        val tint = asset.tintColor?.let {
            try {
                it.toColorInt()
            } catch (_: IllegalArgumentException) {
                null
            }
        } ?: return null
        val min = sparkline.min()
        val range = sparkline.max() - min
        val points = sparkline.map { value ->
            if (range > 0) (1 - (value - min) / range).toFloat() else 0.5f
        }
        return Chart(tint, points)
    }
}

data class MarketSection(
    val section: MApiMarketSection,
    val tokens: List<MarketToken>,
    val visibleLimit: Int? = (section.mobileLimit ?: section.limit)?.takeIf { it > 0 }
) {
    val title: String
        get() = section.title

    val layout: MApiMarketSectionLayout?
        get() = section.layout

    val visibleTokens: List<MarketToken>
        get() = visibleLimit?.let(tokens::take) ?: tokens

    val showsSeeAll: Boolean
        get() = section.hasMore || tokens.size > visibleTokens.size
}
