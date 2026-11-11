package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.graphics.Rect
import android.view.View
import android.view.ViewTreeObserver

/**
 * Whether a view is on screen: shown, and not clipped away whole, as on a tab page laid out beside the selected one,
 * which still counts as visible. It is checked again each time the window draws, so a page paged into view lets the
 * view move again, and [onChange] runs whenever it changes.
 */
internal class AgentOnScreenTracker(private val view: View, private val onChange: () -> Unit) {
    var isOnScreen = false
        private set

    private var isVisibilityAggregated = false
    private val visibleRect = Rect()
    private var observer: ViewTreeObserver? = null

    // Changes found as the window draws are handled after it, as they may change the views
    private val notifyChange = Runnable { onChange() }
    private val preDrawListener = ViewTreeObserver.OnPreDrawListener {
        if (update()) view.post(notifyChange)
        true
    }

    fun setVisibilityAggregated(isVisible: Boolean) {
        isVisibilityAggregated = isVisible
        if (update()) onChange()
    }

    fun attach() {
        detachObserver()
        observer = view.viewTreeObserver.also { it.addOnPreDrawListener(preDrawListener) }
        if (update()) onChange()
    }

    fun detach() {
        detachObserver()
        view.removeCallbacks(notifyChange)
        if (update()) onChange()
    }

    private fun detachObserver() {
        observer?.takeIf { it.isAlive }?.removeOnPreDrawListener(preDrawListener)
        observer = null
    }

    // Whether it changed
    private fun update(): Boolean {
        val isShown =
            isVisibilityAggregated && view.isAttachedToWindow &&
                view.getGlobalVisibleRect(visibleRect)
        if (isShown == isOnScreen) return false
        isOnScreen = isShown
        return true
    }
}
