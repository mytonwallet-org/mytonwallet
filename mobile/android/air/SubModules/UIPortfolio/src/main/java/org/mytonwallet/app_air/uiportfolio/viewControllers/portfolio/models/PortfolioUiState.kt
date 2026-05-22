package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models

import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.StackLinearChartData

sealed class PortfolioUiState {
    data object Idle : PortfolioUiState()
    data class Loading(val request: PortfolioHistoryRequest) : PortfolioUiState()
    data class Loaded(
        val request: PortfolioHistoryRequest,
        val chartData: StackLinearChartData?,
        val overview: PortfolioOverview?,
        val assetBreakdown: List<PortfolioBreakdownSlice>,
        val chainBreakdown: List<PortfolioBreakdownSlice>,
    ) : PortfolioUiState()

    data object Error : PortfolioUiState()
}
