package org.mytonwallet.app_air.uiassets.viewControllers.token.helpers

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod

class TokenChartPercentChangeTest {

    @Test
    fun `default full-range 1D uses finite token percent change`() {
        val result = resolveTokenChartPercentChange(
            activePeriod = MHistoryTimePeriod.DAY,
            startPercentage = 0f,
            endPercentage = 1f,
            tokenPercentChange = 4.3,
            price = 101.68,
            firstPrice = 100.0
        )

        assertEquals(4.3, result!!, 0.0)
    }

    @Test
    fun `missing token percent change falls back to chart percent change`() {
        val result = resolveTokenChartPercentChange(
            activePeriod = MHistoryTimePeriod.DAY,
            startPercentage = 0f,
            endPercentage = 1f,
            tokenPercentChange = null,
            price = 101.68,
            firstPrice = 100.0
        )

        assertEquals(1.68, result!!, 0.0)
    }

    @Test
    fun `non-finite token percent change falls back to chart percent change`() {
        for (tokenPercentChange in listOf(
            Double.NaN,
            Double.POSITIVE_INFINITY,
            Double.NEGATIVE_INFINITY
        )) {
            val result = resolveTokenChartPercentChange(
                activePeriod = MHistoryTimePeriod.DAY,
                startPercentage = 0f,
                endPercentage = 1f,
                tokenPercentChange = tokenPercentChange,
                price = 101.68,
                firstPrice = 100.0
            )

            assertEquals(1.68, result!!, 0.0)
        }
    }

    @Test
    fun `non-1D period uses chart percent change`() {
        val result = resolveTokenChartPercentChange(
            activePeriod = MHistoryTimePeriod.WEEK,
            startPercentage = 0f,
            endPercentage = 1f,
            tokenPercentChange = 4.3,
            price = 101.68,
            firstPrice = 100.0
        )

        assertEquals(1.68, result!!, 0.0)
    }

    @Test
    fun `zoomed range uses chart percent change`() {
        val result = resolveTokenChartPercentChange(
            activePeriod = MHistoryTimePeriod.DAY,
            startPercentage = 0.2f,
            endPercentage = 0.8f,
            tokenPercentChange = 4.3,
            price = 110.0,
            firstPrice = 100.0
        )

        assertEquals(10.0, result!!, 0.0)
    }
}
