package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass

typealias ApiHistoryList = List<List<Double?>>

/** Daily USD closes of the underlying stock, all earlier than the first point of the token's own history */
@JsonClass(generateAdapter = true)
data class ApiPriceHistoryBackfill(val symbol: String, val points: List<List<Double>>)

@JsonClass(generateAdapter = true)
data class ApiPriceHistory(val points: List<List<Double>>, val backfill: ApiPriceHistoryBackfill?)

@JsonClass(generateAdapter = true)
data class ApiPortfolioHistoryResponse(
    val status: String,
    val points: ApiHistoryList?,
    val datasets: List<ApiPortfolioHistoryDataset>?,
    val base: String,
    val density: String,
    val historyScanCursor: Double?,
    val isAssetLimitExceeded: Boolean?
)

@JsonClass(generateAdapter = true)
data class ApiPortfolioHistoryDataset(
    val assetId: Int,
    val symbol: String,
    val contractAddress: String,
    val color: String?,
    val points: ApiHistoryList,
    val impact: Double?
)

fun ApiPortfolioHistoryResponse.normalizedForPortfolioDisplay(
    minimumValue: Double = 0.01
): ApiPortfolioHistoryResponse = copy(
    datasets = datasets?.map { it.normalizedForPortfolioDisplay(minimumValue) }
)

private fun ApiPortfolioHistoryDataset.normalizedForPortfolioDisplay(
    minimumValue: Double
): ApiPortfolioHistoryDataset = copy(
    points = points.map { point ->
        val value = point.getOrNull(1)
        if (point.size < 2 || value == null || value >= minimumValue) {
            point
        } else {
            point.toMutableList().apply { this[1] = 0.0 }
        }
    }
)
