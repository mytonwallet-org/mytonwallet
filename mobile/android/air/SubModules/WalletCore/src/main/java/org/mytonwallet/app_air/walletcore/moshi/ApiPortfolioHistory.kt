package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass

typealias ApiHistoryList = List<List<Double>>

@JsonClass(generateAdapter = true)
data class ApiPortfolioHistoryResponse(
    val status: String,
    val points: ApiHistoryList?,
    val datasets: List<ApiPortfolioHistoryDataset>?,
    val base: String,
    val density: String,
    val historyScanCursor: Double?,
    val assetLimitExceeded: Boolean?,
)

@JsonClass(generateAdapter = true)
data class ApiPortfolioHistoryDataset(
    val assetId: Int,
    val symbol: String,
    val contractAddress: String,
    val color: String?,
    val points: ApiHistoryList,
    val impact: Double?,
)

fun ApiPortfolioHistoryResponse.normalizedForPortfolioDisplay(
    minimumValue: Double = 0.01,
): ApiPortfolioHistoryResponse {
    return copy(
        datasets = datasets?.map { it.normalizedForPortfolioDisplay(minimumValue) }
    )
}

private fun ApiPortfolioHistoryDataset.normalizedForPortfolioDisplay(
    minimumValue: Double,
): ApiPortfolioHistoryDataset {
    return copy(
        points = points.map { point ->
            if (point.size < 2 || point[1] >= minimumValue) {
                point
            } else {
                point.toMutableList().apply { this[1] = 0.0 }
            }
        }
    )
}
