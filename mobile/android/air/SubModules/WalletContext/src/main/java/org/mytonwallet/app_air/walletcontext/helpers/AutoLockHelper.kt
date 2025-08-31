package org.mytonwallet.app_air.walletcontext.helpers

import android.os.Handler
import android.os.Looper
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import java.util.Timer
import java.util.TimerTask

class AutoLockHelper {
    companion object {
        private var timer: Timer? = null
        private var period: Int? = null
        private var timerStartAt: Long? = null

        fun start(period: Int?) {
            AutoLockHelper.period = period
            resetTimer()
        }

        fun resetTimer(remainingTimeMs: Long? = null) {
            timer?.cancel()

            period?.let { period ->
                timer = Timer()
                timerStartAt = System.currentTimeMillis()
                timer?.schedule(object : TimerTask() {
                    override fun run() {
                        Handler(Looper.getMainLooper()).post {
                            WalletContextManager.delegate?.lockScreen()
                        }
                    }
                }, remainingTimeMs ?: (period * 1000L))
            }
        }

        fun appResumed() {
            if (timerStartAt == null || period == null)
                return
            val passedTimeMs = System.currentTimeMillis() - timerStartAt!!
            val periodTime = period!! * 1000L
            if (passedTimeMs >= periodTime) {
                WalletContextManager.delegate?.lockScreen()
            } else {
                resetTimer(periodTime - passedTimeMs)
            }
        }

        fun stop() {
            timer?.cancel()
        }
    }
}
