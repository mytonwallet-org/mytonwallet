package org.mytonwallet.app_air.uiportfolio

import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.StackLinearChartData
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency

data class PortfolioHistoryPoint(
    val timestamp: Long,
    val value: Double,
)

data class PortfolioDataset(
    val assetId: Int?,
    val symbol: String,
    val contractAddress: String?,
    val color: String?,
    val points: List<PortfolioHistoryPoint>,
    val impact: Double?,
)

sealed class PortfolioChartData {
    data class Aggregated(
        val points: List<PortfolioHistoryPoint>,
    ) : PortfolioChartData()

    data class ByAsset(
        val datasets: List<PortfolioDataset>,
    ) : PortfolioChartData()
}

data class PortfolioHistoryRequest(
    val addresses: String,
    val baseCurrency: MBaseCurrency,
    val fromIso: String,
    val toIso: String,
    val density: String = "1d",
)

sealed class PortfolioUiState {
    data object Idle : PortfolioUiState()
    data class Loading(val request: PortfolioHistoryRequest) : PortfolioUiState()
    data class Loaded(
        val request: PortfolioHistoryRequest,
        val chartData: StackLinearChartData?,
    ) : PortfolioUiState()

    data object Error : PortfolioUiState()
}
