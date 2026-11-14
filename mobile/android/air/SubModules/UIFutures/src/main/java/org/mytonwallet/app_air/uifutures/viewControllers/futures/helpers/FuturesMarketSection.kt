package org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers

import java.math.BigDecimal
import java.math.RoundingMode
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketSection
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketToken
import org.mytonwallet.app_air.walletcore.moshi.MApiMarketAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiMarketSection
import org.mytonwallet.app_air.walletcore.moshi.MApiMarketSectionLayout
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsListedAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsMarketSection
import org.mytonwallet.app_air.walletcore.moshi.PERPS_LAYOUT_GRID
import org.mytonwallet.app_air.walletcore.moshi.PERPS_LAYOUT_LARGE_HORIZONTAL
import org.mytonwallet.app_air.walletcore.stores.TokenStore

private const val MARKET_SLUG_PREFIX = "perps:"
private const val CHANGE_DECIMALS = 2

/** The section in the Market screen's format, for its card and grid layouts. */
internal val MApiPerpsMarketSection.marketSection: MarketSection
    get() {
        val marketAssets = assets.map { it.toMarketAsset() }
        return MarketSection(
            MApiMarketSection(
                id = id,
                title = title,
                layout = when (layout) {
                    PERPS_LAYOUT_LARGE_HORIZONTAL -> MApiMarketSectionLayout.LARGE_HORIZONTAL
                    PERPS_LAYOUT_GRID -> MApiMarketSectionLayout.GRID
                    else -> MApiMarketSectionLayout.ROWS
                },
                limit = displayLimit,
                hasMore = hasMore,
                assets = marketAssets
            ),
            marketAssets.map { MarketToken(it, it) }
        )
    }

/** The coin of a market shown as a Market screen token. */
internal val MarketToken.futuresCoin: String?
    get() = id.takeIf { it.startsWith(MARKET_SLUG_PREFIX) }?.removePrefix(MARKET_SLUG_PREFIX)

/** Priced in the base currency, as the Market screen shows its tokens. */
private fun MApiPerpsListedAsset.toMarketAsset() = MApiMarketAsset(
    newBackendId = id,
    slug = MARKET_SLUG_PREFIX + name,
    name = displayName ?: symbol,
    symbol = symbol,
    image = image,
    keywords = keywords,
    price = markPrice?.let { it * (TokenStore.baseCurrencyRate ?: 1.0) },
    percentChange24h = change24h?.let {
        BigDecimal.valueOf(it).setScale(CHANGE_DECIMALS, RoundingMode.HALF_UP).toDouble()
    },
    sparkline = sparkline?.takeIf { it.size > 1 },
    tintColor = tintColor
)
