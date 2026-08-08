package org.mytonwallet.app_air.uiassets.viewControllers.token.helpers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod

class TokenPriceInsightTest {

    @Test
    fun `day requires a move greater than one percent`() {
        assertNull(calculate(MHistoryTimePeriod.DAY, 100.0, 101.0))

        val up = calculate(MHistoryTimePeriod.DAY, 100.0, 101.01)
        val down = calculate(MHistoryTimePeriod.DAY, 100.0, 98.99)

        assertEquals(TokenPriceInsight.Direction.UP, up?.direction)
        assertEquals(TokenPriceInsight.Direction.DOWN, down?.direction)
        assertEquals(TokenPriceInsight.Timeframe.TODAY, up?.timeframe)
    }

    @Test
    fun `week includes moves of exactly five percent`() {
        val up = calculate(MHistoryTimePeriod.WEEK, 100.0, 105.0)
        val down = calculate(MHistoryTimePeriod.WEEK, 100.0, 95.0)

        assertEquals(TokenPriceInsight.Direction.UP, up?.direction)
        assertEquals(TokenPriceInsight.Direction.DOWN, down?.direction)
        assertEquals(TokenPriceInsight.Timeframe.THIS_WEEK, up?.timeframe)
    }

    @Test
    fun `month includes moves of exactly five percent`() {
        val insight = calculate(MHistoryTimePeriod.MONTH, 100.0, 105.0)

        assertEquals(TokenPriceInsight.Timeframe.THIS_MONTH, insight?.timeframe)
    }

    @Test
    fun `periods of three months or longer do not produce an insight`() {
        val history = arrayOf(
            arrayOf(0.0, 100.0),
            arrayOf(1.0, 106.0)
        )

        listOf(
            MHistoryTimePeriod.THREE_MONTHS,
            MHistoryTimePeriod.YEAR,
            MHistoryTimePeriod.ALL
        ).forEach { period ->
            assertNull(
                TokenPriceInsight.calculate(
                    period,
                    history,
                    106.0,
                    nowTimestampSeconds = 1.0
                )
            )
        }
    }

    @Test
    fun `day insight requires history no older than thirty minutes`() {
        val now = 10_000.0

        assertEquals(
            TokenPriceInsight.Direction.UP,
            calculate(
                period = MHistoryTimePeriod.DAY,
                baselinePrice = 100.0,
                currentPrice = 102.0,
                timestamp = now - 30 * 60,
                now = now
            )?.direction
        )
        assertNull(
            calculate(
                period = MHistoryTimePeriod.DAY,
                baselinePrice = 100.0,
                currentPrice = 102.0,
                timestamp = now - 30 * 60 - 1,
                now = now
            )
        )
    }

    @Test
    fun `future history timestamp caused by clock skew produces an insight`() {
        val now = 10_000.0

        val insight = calculate(
            period = MHistoryTimePeriod.WEEK,
            baselinePrice = 100.0,
            currentPrice = 94.0,
            timestamp = now + 1.0,
            now = now
        )

        assertEquals(TokenPriceInsight.Direction.DOWN, insight?.direction)
    }

    @Test
    fun `week insight requires history no older than three hours`() {
        val now = 20_000.0

        assertEquals(
            TokenPriceInsight.Direction.UP,
            calculate(
                period = MHistoryTimePeriod.WEEK,
                baselinePrice = 100.0,
                currentPrice = 105.0,
                timestamp = now - 3 * 60 * 60,
                now = now
            )?.direction
        )
        assertNull(
            calculate(
                period = MHistoryTimePeriod.WEEK,
                baselinePrice = 100.0,
                currentPrice = 105.0,
                timestamp = now - 3 * 60 * 60 - 1,
                now = now
            )
        )
    }

    @Test
    fun `month insight requires history no older than two days`() {
        val now = 5 * 24 * 60 * 60.0

        assertEquals(
            TokenPriceInsight.Direction.UP,
            calculate(
                period = MHistoryTimePeriod.MONTH,
                baselinePrice = 100.0,
                currentPrice = 105.0,
                timestamp = now - 2 * 24 * 60 * 60,
                now = now
            )?.direction
        )
        assertNull(
            calculate(
                period = MHistoryTimePeriod.MONTH,
                baselinePrice = 100.0,
                currentPrice = 105.0,
                timestamp = now - 2 * 24 * 60 * 60 - 1,
                now = now
            )
        )
    }

    @Test
    fun `invalid prices do not produce an insight`() {
        val history = arrayOf(arrayOf(0.0, 100.0))

        assertNull(
            TokenPriceInsight.calculate(
                MHistoryTimePeriod.DAY,
                history,
                null,
                nowTimestampSeconds = 0.0
            )
        )
        assertNull(
            TokenPriceInsight.calculate(
                MHistoryTimePeriod.DAY,
                history,
                Double.NaN,
                nowTimestampSeconds = 0.0
            )
        )
        assertNull(
            TokenPriceInsight.calculate(
                MHistoryTimePeriod.DAY,
                history,
                0.0,
                nowTimestampSeconds = 0.0
            )
        )
    }

    @Test
    fun `copy includes token name direction and timeframe`() {
        val insight = TokenPriceInsight(
            TokenPriceInsight.Direction.DOWN,
            TokenPriceInsight.Timeframe.THIS_WEEK,
            expiresAtTimestampSeconds = 0.0
        )

        assertEquals("Why is Gram down this week?", insight.title("Gram"))
        assertEquals("Why is Gram token price down this week?", insight.prompt("Gram"))
    }

    private fun calculate(
        period: MHistoryTimePeriod,
        baselinePrice: Double,
        currentPrice: Double,
        timestamp: Double = 0.0,
        now: Double = timestamp
    ): TokenPriceInsight? = TokenPriceInsight.calculate(
        period,
        arrayOf(arrayOf(timestamp, baselinePrice)),
        currentPrice,
        nowTimestampSeconds = now
    )
}
