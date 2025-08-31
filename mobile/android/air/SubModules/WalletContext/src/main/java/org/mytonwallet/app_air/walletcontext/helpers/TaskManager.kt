package org.mytonwallet.app_air.walletcontext.helpers

import android.os.Handler
import android.os.Looper

class TaskManager {

    private val handler = Handler(Looper.getMainLooper())
    private var workRunnable: Runnable? = null

    fun startTaskIfEmpty(task: () -> Unit, delayMillis: Long) {
        if (workRunnable != null)
            return
        startTask(task, delayMillis)
    }

    fun startTask(task: () -> Unit, delayMillis: Long) {
        cancelWork()

        workRunnable = Runnable {
            task()
        }

        workRunnable?.let {
            handler.postDelayed(it, delayMillis)
        }
    }

    fun cancelWork() {
        workRunnable?.let {
            handler.removeCallbacks(it)
        }
        workRunnable = null
    }
}
