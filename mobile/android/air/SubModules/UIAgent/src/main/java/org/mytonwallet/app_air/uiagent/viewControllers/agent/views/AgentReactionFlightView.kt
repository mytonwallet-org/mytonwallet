package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.graphics.Canvas
import android.graphics.PointF
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import androidx.core.animation.doOnEnd
import com.airbnb.lottie.LottieDrawable
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentAnswerFeedback
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentReactionAnimation
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentReactionFlight
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y

// Level with the reaction cloud's parts, over the cloud the reaction leaves; without a shadow
private const val AGENT_REACTION_FLIGHT_LEVEL = 2f

/** Where a reaction leaves the cloud: its icon's rect in the window, as the press left it, and the frame its still is on */
internal data class AgentReactionSource(val frame: RectF, val stillProgress: Float)

/**
 * A chosen reaction's flight, as Telegram's. The icon at [source] flies to the corner emoji, whose centre [target]
 * gives on each frame, along [AgentReactionFlight]'s parabola, shrinking to the emoji's size and fading from the
 * cloud's still into the emoji's first drawing; the burst around the corner starts on the way, above it. On the corner
 * a light tap plays, [onHit] follows, and the icon goes on as the corner emoji, playing Telegram's center icon from
 * that first drawing. It plays here in [host], the popup layer, as Telegram's flying icon goes on inside the message:
 * neither the closing menu's dim nor the chat's rows cover or cut it. [onLanded] follows as it ends, on the emoji's
 * resting drawing, or as the popup layer goes before that.
 */
@SuppressLint("ViewConstructor")
internal class AgentReactionFlightView(
    val feedback: AgentAnswerFeedback,
    private val host: FrameLayout,
    source: AgentReactionSource,
    private val target: () -> PointF?,
    private val onHit: () -> Unit,
    private val onLanded: () -> Unit
) : View(host.context) {
    private val density = resources.displayMetrics.density
    private val still =
        AgentReactionAnimations.drawable(context, feedback, AgentReactionAnimation.SELECT)?.also {
            it.callback = this
            it.progress = source.stillProgress
        }
    private val emoji =
        AgentReactionAnimations.drawable(context, feedback, AgentReactionAnimation.CENTER)?.also {
            it.callback = this
        }
    private val fromX = source.frame.centerX()
    private val fromY = source.frame.centerY()
    private val fromSize = source.frame.width()
    private val toSize = AgentReactionGeometry.BADGE_ICON_SIZE.dp
    private val viewSize = ceil(max(fromSize, toSize) * EMOJI_FRAME_SCALE).toInt()
    private val hostLocation = host.getLocationInWindow()
    private var to = target() ?: PointF(fromX, fromY)

    // The drawing's size, as the still's frame, and how far it has faded into the emoji
    private var size = fromSize
    private var emojiAlpha = 0f
    private var animator: ValueAnimator? = null
    private var hasBurst = false
    private var isEnded = false

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        outlineProvider = null
        elevation = AGENT_REACTION_FLIGHT_LEVEL.dp
        val params = FrameLayout.LayoutParams(viewSize, viewSize, Gravity.TOP or Gravity.LEFT)
        host.addView(this, params)
        place(fromX, fromY)
        // The still goes on from the frame the press left it on
        still?.takeIf { it.progress > 0f && it.progress < 1f }?.resumeAnimation()
        fly()
    }

    /** Takes the reaction on its way away at once */
    fun cancel() {
        end(notifies = false)
    }

    override fun verifyDrawable(who: Drawable): Boolean =
        who === still || who === emoji || super.verifyDrawable(who)

    override fun onDraw(canvas: Canvas) {
        still?.drawAt(canvas, size, 1f - emojiAlpha)
        emoji?.drawAt(canvas, size * EMOJI_FRAME_SCALE, emojiAlpha)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        end(notifies = true)
    }

    private fun fly() {
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AgentReactionFlight.DURATION_MS
            interpolator = LinearInterpolator()
            addUpdateListener {
                val progress = it.animatedValue as Float
                target()?.let { point -> to = point }
                val (x, y) = AgentReactionFlight.point(fromX, fromY, to.x, to.y, progress, density)
                size = AgentReactionFlight.size(fromSize, toSize, progress)
                emojiAlpha = progress
                place(x, y)
                val elapsedMs = (progress * AgentReactionFlight.DURATION_MS).roundToLong()
                if (!hasBurst && AgentReactionFlight.isBurstDue(elapsedMs)) burst()
            }
            doOnEnd { if (!isEnded) hit() }
            start()
        }
    }

    // The burst around the corner, above the flying icon, where Telegram plays its own
    private fun burst() {
        hasBurst = true
        val frame = agentReactionSquare(to.x, to.y, AgentReactionGeometry.BURST_SIZE, density)
        playAgentReactionBurst(
            host,
            feedback,
            AgentReactionAnimation.BURST,
            frame,
            level = AGENT_REACTION_FLIGHT_LEVEL.dp
        )
    }

    private fun hit() {
        if (!hasBurst) burst()
        size = toSize
        emojiAlpha = 1f
        place(to.x, to.y)
        still?.cancelAnimation()
        Haptics.play(this, HapticType.LIGHT_TAP)
        onHit()
        val emoji = emoji ?: return end(notifies = true)
        emoji.addAnimatorUpdateListener { target()?.let { point -> place(point.x, point.y) } }
        emoji.addAnimatorListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: Animator) {
                end(notifies = true)
            }
        })
        emoji.progress = 0f
        emoji.playAnimation()
    }

    // Takes the icon away; [notifies] tells the answer that the reaction is on its corner now
    private fun end(notifies: Boolean) {
        if (isEnded) return
        isEnded = true
        animator?.cancel()
        still?.cancelAnimation()
        emoji?.cancelAnimation()
        (parent as? ViewGroup)?.removeView(this)
        if (notifies) onLanded()
    }

    private fun place(x: Float, y: Float) {
        translationX = x - viewSize / 2f - hostLocation.x - host.paddingLeft
        translationY = y - viewSize / 2f - hostLocation.y - host.paddingTop
        invalidate()
    }

    private fun LottieDrawable.drawAt(canvas: Canvas, frame: Float, alpha: Float) {
        if (alpha <= 0f) return
        val center = viewSize / 2f
        val half = frame / 2
        setBounds(
            (center - half).roundToInt(),
            (center - half).roundToInt(),
            (center + half).roundToInt(),
            (center + half).roundToInt()
        )
        applyAlpha(alpha)
        draw(canvas)
    }

    private companion object {
        // The center icon fills about half of its frame, as the still fills its own
        const val EMOJI_FRAME_SCALE =
            AgentReactionGeometry.BADGE_ANIMATION_SIZE / AgentReactionGeometry.BADGE_ICON_SIZE
    }
}
