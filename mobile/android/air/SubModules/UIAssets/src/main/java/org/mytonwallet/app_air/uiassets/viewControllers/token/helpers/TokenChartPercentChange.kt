package org.mytonwallet.app_air.uiassets.viewControllers.token.helpers

import kotlin.math.round
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod

internal fun resolveTokenChartPercentChange(
    activePeriod: MHistoryTimePeriod,
    startPercentage: Float,
    endPercentage: Float,
    tokenPercentChange: Double?,
    price: Double?,
    firstPrice: Double?
): Double? {
    val finiteTokenPercentChange = tokenPercentChange?.takeIf { it.isFinite() }
    if (
        activePeriod == MHistoryTimePeriod.DAY &&
        startPercentage == 0f &&
        endPercentage == 1f &&
        finiteTokenPercentChange != null
    ) {
        return finiteTokenPercentChange
    }

    return firstPrice?.let { firstPriceInChart ->
        price?.let { (it - firstPriceInChart) / firstPriceInChart * 10000 }
    }?.let {
        round(it) / 100
    }
}
