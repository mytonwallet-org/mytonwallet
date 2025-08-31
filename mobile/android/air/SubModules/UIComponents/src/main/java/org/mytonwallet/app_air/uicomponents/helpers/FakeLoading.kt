package org.mytonwallet.app_air.uicomponents.helpers

import android.os.SystemClock
import kotlinx.coroutines.delay

object FakeLoading {
    fun init(): Long = SystemClock.uptimeMillis()
    suspend fun start(delayMs: Long, start: Long) {
        val d = delayMs - (SystemClock.uptimeMillis() - start)
        if (d > 0) {
            delay(d)
        }
    }
}
