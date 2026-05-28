package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models

data class PortfolioOverview(
    val totalValue: Double,
    val netChangeAbs: Double,
    val netChangePct: Double?,
    val startTimestampMs: Long,
    val endTimestampMs: Long,
) {
    companion object {
        val EMPTY = PortfolioOverview(
            totalValue = 0.0,
            netChangeAbs = 0.0,
            netChangePct = null,
            startTimestampMs = 0L,
            endTimestampMs = 0L,
        )
    }
}
