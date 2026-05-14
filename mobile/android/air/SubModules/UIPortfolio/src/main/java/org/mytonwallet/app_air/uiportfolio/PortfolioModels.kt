package org.mytonwallet.app_air.uiportfolio

import org.mytonwallet.app_air.uicomponents.widgets.chart.extended.StackLinearChartData
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency

data class PortfolioHistoryRequest(
    val wallets: List<String>,
    val baseCurrency: MBaseCurrency,
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
