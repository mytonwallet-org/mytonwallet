package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models

import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod

data class PortfolioHistoryRequest(
    val accountId: String,
    val wallets: List<String>,
    val baseCurrency: MBaseCurrency,
    val period: MHistoryTimePeriod,
)