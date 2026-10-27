package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

/** Keep the requested average cadence across 60/90/120 Hz display pulses. */
internal class CardFrameCadence {
    private var period = 0L
    private var deadline = 0L

    fun shouldTick(time: Long, rate: Int): Boolean {
        val nextPeriod = 1_000_000_000L / rate
        if (period != nextPeriod) {
            period = nextPeriod
            deadline = 0L
        }
        if (deadline != 0L && time < deadline) return false
        deadline = if (deadline == 0L) {
            time + period
        } else {
            deadline + ((time - deadline) / period + 1) * period
        }
        return true
    }

    fun reset() {
        deadline = 0L
    }
}
