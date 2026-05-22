package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models

data class PortfolioOverview(
    val totalValue: Double,
    val netChangeAbs: Double,
    val netChangePct: Double?,
    val startTimestampMs: Long,
    val endTimestampMs: Long,
)
