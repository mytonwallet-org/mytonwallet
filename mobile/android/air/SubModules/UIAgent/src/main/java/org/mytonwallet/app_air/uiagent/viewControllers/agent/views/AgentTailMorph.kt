package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.view.View
import androidx.core.animation.doOnEnd
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentHintsCell
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

// How a bubble's tail grows back out of its corner as the suggestions under it go
private const val TAIL_BACK_DURATION_MS = 400L
private const val TAIL_BACK_DELAY_MS = 50L
private const val TAIL_BACK_DAMPING = 0.75f

/**
 * Moves the tail of a bubble in [host] into its corner as the suggestions that take its place come in, with their
 * timing and curve, and back out of it on a spring as they go, as on iOS
 */
internal class AgentTailMorph(private val host: View) {
    private var animator: ValueAnimator? = null
    private var target = 1f

    /** Gives [bubble] its tail or takes it away, moving it there when [canAnimate], as for a message that stays */
    fun update(bubble: AgentBubbleDrawable, hasTail: Boolean, canAnimate: Boolean) {
        val next = if (hasTail) 1f else 0f
        val running = animator
        // Already on its way there, as when the cell is configured again midway
        if (running != null && target == next) return
        if (running == null && bubble.tailProgress == next) return
        cancel()
        target = next
        if (!canAnimate || !host.isAttachedToWindow || !WGlobalStorage.getAreAnimationsActive()) {
            bubble.tailProgress = next
            return
        }
        animator = ValueAnimator.ofFloat(bubble.tailProgress, next).apply {
            if (hasTail) {
                duration = TAIL_BACK_DURATION_MS
                startDelay = TAIL_BACK_DELAY_MS
                interpolator = WInterpolator.spring(dampingRatio = TAIL_BACK_DAMPING)
            } else {
                duration = AgentHintsCell.FOLLOWUP_REVEAL_MS
                interpolator = AGENT_EASE_OUT
            }
            addUpdateListener { bubble.tailProgress = it.animatedValue as Float }
            doOnEnd { if (animator === this) animator = null }
            start()
        }
    }

    fun cancel() {
        val running = animator ?: return
        animator = null
        running.cancel()
    }
}
