package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models

import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency

data class PortfolioHistoryRequest(
    val wallets: List<String>,
    val baseCurrency: MBaseCurrency,
)
