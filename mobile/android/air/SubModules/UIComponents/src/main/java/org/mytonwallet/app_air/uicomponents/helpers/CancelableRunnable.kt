package org.mytonwallet.app_air.uicomponents.helpers

import java.util.concurrent.atomic.AtomicBoolean

class CancelableRunnable(private val block: () -> Unit) : Runnable {
    private val canceled = AtomicBoolean(false)

    fun cancel() {
        canceled.set(true)
    }

    override fun run() {
        if (!canceled.get()) {
            block.invoke()
        }
    }
}
