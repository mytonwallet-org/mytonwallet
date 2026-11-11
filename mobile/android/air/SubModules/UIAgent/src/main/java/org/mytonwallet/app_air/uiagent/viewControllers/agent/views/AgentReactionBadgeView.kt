package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.Animator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.view.MotionEvent
import android.view.View
import androidx.core.animation.doOnEnd
import com.airbnb.lottie.LottieDrawable
import kotlin.math.hypot
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentAnswerFeedback
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentReactionAnimation
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentReactionEmojiSwap
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y

/**
 * An answer's reaction, as Telegram shows one on a message: the emoji alone, Telegram's center icon at rest, on the
 * bubble's bottom trailing corner, centred [emojiCenterX] from the view's left and [emojiCenterY] from its top. Only
 * the emoji takes touches. It is not an accessibility element of its own: the bubble says which reaction it carries.
 */
@SuppressLint("ViewConstructor")
internal class AgentReactionBadgeView(context: Context) : View(context) {
    /** The reaction the corner shows, or will show once the reaction on its way from the cloud lands */
    var feedback: AgentAnswerFeedback? = null
        private set

    private var landingFeedback: AgentAnswerFeedback? = null

    // The emoji: Telegram's center icon, which rests on its last frame
    private var icon: LottieDrawable? = null
    private var iconAlpha = 1f

    // The emoji giving way to the next one, or to none: it shrinks as it fades
    private var leaving: LottieDrawable? = null
    private var leavingScale = 1f
    private var leavingAlpha = 1f

    private val animators = mutableListOf<Animator>()
    private val size = agentReactionBadgeSize(resources.displayMetrics.density)

    // The emoji drawn over the dim of the answer's open menu, in step with this view
    private var lifted: LiftedEmoji? = null

    val emojiCenterX: Float get() = size / 2f
    val emojiCenterY: Float get() = size / 2f

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        updateVisibility()
    }

    /** Shows [feedback] at rest at once, or nothing */
    fun show(feedback: AgentAnswerFeedback?) {
        cancelAnimations()
        this.feedback = feedback
        landingFeedback = null
        leaving = null
        setIcon(feedback, progress = 1f)
        iconAlpha = 1f
        updateVisibility()
    }

    /** Without motion, the shown emoji fades out as [feedback]'s fades in, at rest */
    fun fade(feedback: AgentAnswerFeedback?) {
        cancelAnimations()
        val from = icon
        this.feedback = feedback
        landingFeedback = null
        leaving = from
        leavingScale = 1f
        setIcon(feedback, progress = 1f)
        runAnimation(AgentReactionMotion.FADE_MS) { progress ->
            leavingAlpha = 1f - progress
            iconAlpha = progress
        }
    }

    /** [feedback] is on its way from the cloud: the corner keeps what it shows until it lands */
    fun awaitLanding(feedback: AgentAnswerFeedback) {
        finishAnimations()
        this.feedback = feedback
        landingFeedback = feedback
    }

    /**
     * [feedback] lands on the corner, where its flight goes on as the emoji, playing Telegram's center icon: the shown
     * emoji gives way to it, shrinking as it fades, as Telegram's does, and the corner shows [feedback] once [show]
     * takes it back at rest
     */
    fun makeWay(feedback: AgentAnswerFeedback) {
        finishAnimations()
        this.feedback = feedback
        landingFeedback = feedback
        startLeaving()
        setIcon(null, progress = 1f)
    }

    /** [feedback] comes without the cloud: the shown emoji gives way to it as it plays Telegram's center icon */
    fun swap(feedback: AgentAnswerFeedback) {
        cancelAnimations()
        this.feedback = feedback
        landingFeedback = null
        startLeaving()
        setIcon(feedback, progress = 0f)
        iconAlpha = 1f
        icon?.playAnimation()
        updateVisibility()
    }

    /** The reaction went: the emoji shrinks as it fades */
    fun withdraw() {
        cancelAnimations()
        feedback = null
        landingFeedback = null
        startLeaving()
        setIcon(null, progress = 1f)
    }

    /** Ends what is moving, at its end */
    fun finishAnimations() {
        animators.toList().forEach { it.end() }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(size, size)
    }

    // Touches beside the emoji go to the bubble under it, and to its links
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(event: MotionEvent): Boolean {
        val isOnEmoji = hypot(event.x - emojiCenterX, event.y - emojiCenterY) <=
            AgentReactionGeometry.BADGE_ICON_SIZE.dp / 2
        if (event.actionMasked == MotionEvent.ACTION_DOWN && !isOnEmoji) return false
        return super.onTouchEvent(event)
    }

    /**
     * The emoji as it shows on this view, drawn in step with it at its place in the window, within the window's [rows]:
     * the menu, which dims the chat around the answer it lifts, draws it over its dim, so that only the emoji's own
     * pixels show undimmed
     */
    fun liftEmoji(rows: IntRange): Drawable = LiftedEmoji(rows).also { lifted = it }

    override fun onDraw(canvas: Canvas) {
        drawEmoji(canvas)
    }

    override fun verifyDrawable(who: Drawable): Boolean =
        who === icon || who === leaving || super.verifyDrawable(who)

    override fun invalidateDrawable(drawable: Drawable) {
        super.invalidateDrawable(drawable)
        lifted?.invalidateSelf()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        finishAnimations()
        icon?.cancelAnimation()
        icon?.progress = 1f
    }

    // The emoji shown now shrinks from the frame it is on to Telegram's 0.2 as it fades
    private fun startLeaving() {
        val from = icon ?: return
        from.cancelAnimation()
        leaving = from
        val easing = CubicBezierInterpolator.EASE_BOTH
        runAnimation(AgentReactionEmojiSwap.DURATION_MS, easing) { progress ->
            val (scale, alpha) = AgentReactionEmojiSwap.leaving(progress)
            leavingScale = scale
            leavingAlpha = alpha
        }
    }

    private fun runAnimation(
        durationMs: Long,
        easing: CubicBezierInterpolator? = null,
        onUpdate: (Float) -> Unit
    ) {
        onUpdate(0f)
        updateVisibility()
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = durationMs
            easing?.let { interpolator = it }
            addUpdateListener {
                onUpdate(it.animatedValue as Float)
                redraw()
            }
            doOnEnd {
                animators.remove(this)
                leaving = null
                updateVisibility()
            }
            animators += this
            start()
        }
    }

    private fun cancelAnimations() {
        animators.toList().forEach { it.cancel() }
        animators.clear()
    }

    private fun setIcon(feedback: AgentAnswerFeedback?, progress: Float) {
        if (icon !== leaving) icon?.cancelAnimation()
        icon = feedback?.let {
            AgentReactionAnimations.drawable(context, it, AgentReactionAnimation.CENTER)?.apply {
                callback = this@AgentReactionBadgeView
                this.progress = progress
            }
        }
        updateVisibility()
    }

    // Only a view with an emoji to draw takes touches
    private fun updateVisibility() {
        visibility = if (icon != null || leaving != null) VISIBLE else INVISIBLE
        redraw()
    }

    private fun redraw() {
        invalidate()
        lifted?.invalidateSelf()
    }

    private fun drawEmoji(canvas: Canvas) {
        leaving?.drawAt(canvas, leavingScale, leavingAlpha)
        icon?.drawAt(canvas, 1f, iconAlpha)
    }

    private fun LottieDrawable.drawAt(canvas: Canvas, scale: Float, alpha: Float) {
        if (alpha <= 0f || scale <= 0f) return
        val half = AgentReactionGeometry.BADGE_ANIMATION_SIZE.dp / 2
        setBounds(
            (emojiCenterX - half).roundToInt(),
            (emojiCenterY - half).roundToInt(),
            (emojiCenterX + half).roundToInt(),
            (emojiCenterY + half).roundToInt()
        )
        applyAlpha(alpha)
        canvas.save()
        canvas.scale(scale, scale, emojiCenterX, emojiCenterY)
        draw(canvas)
        canvas.restore()
    }

    // Draws the emoji where this view shows it in the window, clipped to the window's [rows]
    private inner class LiftedEmoji(private val rows: IntRange) : Drawable() {
        override fun draw(canvas: Canvas) {
            if (!isAttachedToWindow || !isShown) return
            val location = getLocationInWindow()
            canvas.save()
            canvas.clipRect(bounds.left, rows.first, bounds.right, rows.last + 1)
            canvas.translate(location.x.toFloat(), location.y.toFloat())
            drawEmoji(canvas)
            canvas.restore()
        }

        override fun setAlpha(alpha: Int) = Unit

        override fun setColorFilter(colorFilter: ColorFilter?) = Unit

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }
}
