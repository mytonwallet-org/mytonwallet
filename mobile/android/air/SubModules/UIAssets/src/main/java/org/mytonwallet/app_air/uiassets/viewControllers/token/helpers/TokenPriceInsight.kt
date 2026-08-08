package org.mytonwallet.app_air.uiassets.viewControllers.token.helpers

import kotlin.math.abs
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.MHistoryTimePeriod

data class TokenPriceInsight(
    val direction: Direction,
    val timeframe: Timeframe,
    val expiresAtTimestampSeconds: Double
) {
    enum class Direction(val word: String) {
        UP("up"),
        DOWN("down")
    }

    enum class Timeframe(val phrase: String) {
        TODAY("today"),
        THIS_WEEK("this week"),
        THIS_MONTH("this month")
    }

    fun title(tokenName: String) = LocaleController.getStringWithKeyValues(
        "Why is %tokenName% %direction% %timeframe%?",
        listOf(
            "%tokenName%" to tokenName,
            "%direction%" to LocaleController.getString(direction.word),
            "%timeframe%" to LocaleController.getString(timeframe.phrase)
        )
    )

    fun prompt(tokenName: String) =
        "Why is $tokenName token price ${direction.word} ${timeframe.phrase}?"

    companion object {
        private const val DAY_THRESHOLD_PERCENT = 1.0
        private const val LONGER_THRESHOLD_PERCENT = 5.0
        private const val DAY_MAX_AGE_SECONDS = 30 * 60.0
        private const val WEEK_MAX_AGE_SECONDS = 3 * 60 * 60.0
        private const val LONGER_MAX_AGE_SECONDS = 2 * 24 * 60 * 60.0

        fun calculate(
            period: MHistoryTimePeriod,
            historyData: Array<Array<Double>>?,
            currentPrice: Double?,
            nowTimestampSeconds: Double = System.currentTimeMillis() / 1000.0
        ): TokenPriceInsight? {
            if (
                currentPrice == null || !currentPrice.isFinite() || currentPrice <= 0.0 ||
                !nowTimestampSeconds.isFinite()
            ) {
                return null
            }

            val points = historyData
                ?.mapNotNull { pair ->
                    if (pair.size < 2) return@mapNotNull null
                    val timestamp = pair[0]
                    val price = pair[1]
                    if (!timestamp.isFinite() || !price.isFinite() || price <= 0.0) {
                        null
                    } else {
                        PricePoint(timestamp, price)
                    }
                }
                ?.sortedBy { it.timestamp }
                .orEmpty()
            if (points.isEmpty()) return null

            val maxAgeSeconds = when (period) {
                MHistoryTimePeriod.DAY -> DAY_MAX_AGE_SECONDS

                MHistoryTimePeriod.WEEK -> WEEK_MAX_AGE_SECONDS

                MHistoryTimePeriod.MONTH -> LONGER_MAX_AGE_SECONDS

                MHistoryTimePeriod.THREE_MONTHS,
                MHistoryTimePeriod.YEAR,
                MHistoryTimePeriod.ALL -> return null
            }
            val latestPointAge = nowTimestampSeconds - points.last().timestamp
            if (latestPointAge > maxAgeSeconds) return null

            val baselinePrice = points.first().price

            val percentChange = (currentPrice - baselinePrice) / baselinePrice * 100.0
            val threshold = if (period == MHistoryTimePeriod.DAY) {
                DAY_THRESHOLD_PERCENT
            } else {
                LONGER_THRESHOLD_PERCENT
            }
            val meetsThreshold = if (period == MHistoryTimePeriod.DAY) {
                abs(percentChange) > threshold
            } else {
                abs(percentChange) >= threshold
            }
            if (!meetsThreshold) return null

            return TokenPriceInsight(
                direction = if (percentChange > 0.0) Direction.UP else Direction.DOWN,
                timeframe = when (period) {
                    MHistoryTimePeriod.DAY -> Timeframe.TODAY

                    MHistoryTimePeriod.WEEK -> Timeframe.THIS_WEEK

                    MHistoryTimePeriod.MONTH -> Timeframe.THIS_MONTH

                    MHistoryTimePeriod.THREE_MONTHS,
                    MHistoryTimePeriod.YEAR,
                    MHistoryTimePeriod.ALL -> return null
                },
                expiresAtTimestampSeconds = points.last().timestamp + maxAgeSeconds
            )
        }

        private data class PricePoint(val timestamp: Double, val price: Double)
    }
}
