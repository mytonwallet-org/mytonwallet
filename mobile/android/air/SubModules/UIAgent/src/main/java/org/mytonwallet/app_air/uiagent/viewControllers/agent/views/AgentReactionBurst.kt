package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentAnswerFeedback
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentReactionAnimation
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y

/**
 * Plays [feedback]'s [animation] once at [frame], a window rect, in [host], the popup layer over the chat and the
 * menu, where nothing clips it, and takes it away as it ends. It goes at [level], an elevation without a shadow.
 */
internal fun playAgentReactionBurst(
    host: FrameLayout,
    feedback: AgentAnswerFeedback,
    animation: AgentReactionAnimation,
    frame: AgentReactionFrame,
    level: Float
) {
    val drawable = AgentReactionAnimations.drawable(host.context, feedback, animation) ?: return
    val view = ImageView(host.context).apply {
        setImageDrawable(drawable)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        outlineProvider = null
        elevation = level
    }
    val hostLocation = host.getLocationInWindow()
    val params = FrameLayout.LayoutParams(
        frame.right - frame.left,
        frame.bottom - frame.top,
        Gravity.TOP or Gravity.LEFT
    ).apply {
        leftMargin = frame.left - hostLocation.x - host.paddingLeft
        topMargin = frame.top - hostLocation.y - host.paddingTop
    }
    host.addView(view, params)
    drawable.addAnimatorListener(object : AnimatorListenerAdapter() {
        override fun onAnimationEnd(animation: Animator) {
            (view.parent as? ViewGroup)?.removeView(view)
        }

        override fun onAnimationCancel(animation: Animator) {
            (view.parent as? ViewGroup)?.removeView(view)
        }
    })
    drawable.playAnimation()
}
