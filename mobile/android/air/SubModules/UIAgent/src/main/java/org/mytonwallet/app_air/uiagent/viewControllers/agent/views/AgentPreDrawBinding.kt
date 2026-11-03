package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.view.View
import android.view.ViewTreeObserver

/**
 * Runs [listener] on the window's pre-draw pass while [view] is in the window. A screen's view leaves the window
 * before the screen is destroyed, so the listener goes with the window it was added to, not with the view's
 * observer of the moment.
 */
internal class AgentPreDrawBinding(
    private val view: View,
    private val listener: ViewTreeObserver.OnPreDrawListener
) : View.OnAttachStateChangeListener {
    private var observer: ViewTreeObserver? = null

    init {
        view.addOnAttachStateChangeListener(this)
        if (view.isAttachedToWindow) onViewAttachedToWindow(view)
    }

    override fun onViewAttachedToWindow(v: View) {
        if (observer?.isAlive == true) return
        observer = v.viewTreeObserver.also { it.addOnPreDrawListener(listener) }
    }

    override fun onViewDetachedFromWindow(v: View) {
        observer?.takeIf { it.isAlive }?.removeOnPreDrawListener(listener)
        observer = null
    }

    fun release() {
        view.removeOnAttachStateChangeListener(this)
        onViewDetachedFromWindow(view)
    }
}
