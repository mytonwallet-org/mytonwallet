package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod

enum class PortfolioAgentChart(val chartId: String) {
    NET_WORTH("net-worth"),
    TOTAL_PNL("pnl-cumulative"),
    DAILY_PNL("pnl"),
    PORTFOLIO_SHARE("portfolio-share");

    val analysisTitle: String
        get() = when (this) {
            NET_WORTH -> LocaleController.getString("Compare with last month")
            TOTAL_PNL -> LocaleController.getString("Best & worst performers")
            DAILY_PNL -> LocaleController.getString("Biggest profit today")
            PORTFOLIO_SHARE -> LocaleController.getString("Check allocation")
        }

    fun analysisPrompt(period: MHistoryTimePeriod): String = when (this) {
        NET_WORTH -> LocaleController.getString("\$agent_prompt_portfolio_compare")

        TOTAL_PNL -> LocaleController.getStringWithKeyValues(
            "\$agent_prompt_portfolio_performers",
            listOf("%period%" to period.localizedLong)
        )

        DAILY_PNL -> LocaleController.getStringWithKeyValues(
            "\$agent_prompt_portfolio_best_day",
            listOf("%period%" to period.localizedLong)
        )

        PORTFOLIO_SHARE -> LocaleController.getString("\$agent_prompt_portfolio_share")
    }
}
