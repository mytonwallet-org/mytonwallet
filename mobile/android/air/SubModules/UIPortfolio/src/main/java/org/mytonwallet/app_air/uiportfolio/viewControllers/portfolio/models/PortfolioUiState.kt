package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models

import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartData
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.SignedBarChartData
import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.StackLinearChartData

enum class PortfolioChartKind { NET_WORTH, TOTAL_PNL, DAILY_PNL }

sealed class PortfolioUiState {
    data object Idle : PortfolioUiState()
    data class Loading(
        val request: PortfolioHistoryRequest,
        val animated: Boolean = false,
    ) : PortfolioUiState()
    data class Loaded(
        val request: PortfolioHistoryRequest,
        val chartData: StackLinearChartData?,
        val totalPnlChartData: ChartData?,
        val dailyPnlChartData: SignedBarChartData?,
        val overview: PortfolioOverview?,
        val assetBreakdown: List<PortfolioBreakdownSlice>,
        val chainBreakdown: List<PortfolioBreakdownSlice>,
        // Per-chart fetch failures. A failed chart shows an inline error + Try Again,
        // independently of the others (e.g. a 503 on Daily PnL leaves the rest intact).
        val netWorthFailed: Boolean = false,
        val totalPnlFailed: Boolean = false,
        val dailyPnlFailed: Boolean = false,
        val silent: Boolean = false,
    ) : PortfolioUiState()
}
