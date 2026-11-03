package org.mytonwallet.uihome.tabs

import android.content.ComponentCallbacks2
import android.content.res.Configuration
import android.view.View
import android.view.ViewTreeObserver

/**
 * Mounts the tab pages not shown yet one at a time while the app idles, as iOS's pager prepares its pages: each waits
 * [MOUNT_DELAY_MS] with nothing scrolling or touched. Memory pressure unmounts the pages not on screen, once nothing
 * moves, and holds the mounting back until the app comes to the front again.
 */
internal class TabPagePreloader(
    private val host: View,
    // Whether pages may mount at all: the selected one has appeared and the app is in front
    private val isActive: () -> Boolean,
    // Whether nothing moves or is touched now
    private val isIdle: () -> Boolean,
    // The next page to mount, or null once all are
    private val nextPage: () -> Int?,
    private val mount: (Int) -> Unit,
    private val unmountInactive: () -> Unit
) {
    private var isStopped = false
    private var isUnmountPending = false
    private val mountNext = Runnable { mountNextPage() }
    private val unmountNext = Runnable { unmountWhenIdle() }

    // A scroll anywhere puts the next page off for another wait
    private val scrollListener = ViewTreeObserver.OnScrollChangedListener { schedule() }
    private val attachListener = object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) {
            view.viewTreeObserver.addOnScrollChangedListener(scrollListener)
            // Held only while attached, so a recreated activity's old views are not kept by the application
            view.context.applicationContext.registerComponentCallbacks(memoryCallbacks)
            schedule()
            if (isUnmountPending) view.post(unmountNext)
        }

        override fun onViewDetachedFromWindow(view: View) {
            view.viewTreeObserver.removeOnScrollChangedListener(scrollListener)
            view.context.applicationContext.unregisterComponentCallbacks(memoryCallbacks)
            view.removeCallbacks(mountNext)
            view.removeCallbacks(unmountNext)
        }
    }
    private val memoryCallbacks = object : ComponentCallbacks2 {
        override fun onTrimMemory(level: Int) {
            if (isMemoryPressure(level)) release()
        }

        override fun onConfigurationChanged(newConfig: Configuration) {}

        @Deprecated("Deprecated in Java")
        override fun onLowMemory() = release()
    }

    fun start() {
        host.addOnAttachStateChangeListener(attachListener)
        if (host.isAttachedToWindow) attachListener.onViewAttachedToWindow(host)
    }

    fun destroy() {
        if (host.isAttachedToWindow) attachListener.onViewDetachedFromWindow(host)
        host.removeOnAttachStateChangeListener(attachListener)
    }

    /** Waits for the next idle turn to mount the next page */
    fun schedule() {
        host.removeCallbacks(mountNext)
        if (isStopped || !host.isAttachedToWindow || !isActive() || nextPage() == null) return
        host.postDelayed(mountNext, MOUNT_DELAY_MS)
    }

    private fun mountNextPage() {
        if (isStopped || !isActive()) return
        val index = nextPage() ?: return
        if (isIdle()) mount(index)
        schedule()
    }

    /** Lets the pages mount again after memory pressure held them back, as the app comes to the front */
    fun resume() {
        isStopped = false
        schedule()
    }

    private fun release() {
        isStopped = true
        isUnmountPending = true
        host.removeCallbacks(mountNext)
        unmountWhenIdle()
    }

    // A page paged or sprung into view stays until nothing moves, so the unmount never blanks it or ends a drag
    private fun unmountWhenIdle() {
        host.removeCallbacks(unmountNext)
        if (!isUnmountPending || !host.isAttachedToWindow) return
        if (!isIdle()) {
            host.postDelayed(unmountNext, MOUNT_DELAY_MS)
            return
        }
        isUnmountPending = false
        unmountInactive()
    }

    // The levels at which the system runs short of memory, not the app merely leaving the screen or joining the
    // background list
    @Suppress("DEPRECATION")
    private fun isMemoryPressure(level: Int): Boolean =
        level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL ||
            level >= ComponentCallbacks2.TRIM_MEMORY_MODERATE

    companion object {
        const val MOUNT_DELAY_MS = 100L
    }
}
