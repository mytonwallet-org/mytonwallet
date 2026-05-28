package org.mytonwallet.app_air.walletcontext.helpers

import android.util.Log

object MeasureTimeHelpers {

    private const val ENABLED = true
    private const val THRESHOLD_NS = 500_000L

    fun measure(tag: String, block: () -> Unit) {
        if (!ENABLED) {
            block()
            return
        }

        val timeMs = kotlin.system.measureNanoTime {
            block()
        }

        if (timeMs > THRESHOLD_NS) {
            Log.d("MeasureTime", "${timeMs / 1_000_000f} ms *** $tag")
        }
    }
}
