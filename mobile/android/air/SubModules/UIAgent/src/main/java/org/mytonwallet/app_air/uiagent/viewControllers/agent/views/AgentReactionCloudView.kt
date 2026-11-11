package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.ViewTreeObserver
import android.view.animation.LinearInterpolator
import android.widget.Button
import android.widget.FrameLayout
import androidx.core.animation.doOnEnd
import androidx.core.animation.doOnStart
import com.airbnb.lottie.LottieDrawable
import kotlin.math.max
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentAnswerFeedback
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentReactionFillColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentReactionSelectionColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentReactionAnimation
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.agentReactionPressAnimation
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.agentReactionSlotAppearance
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp

private const val BUTTON_WIDTH_DP = 48f

// The tail's dot lies this far beyond its bump
private const val DOT_SHIFT_DP =
    AgentReactionGeometry.CLOUD_DOT_MENU_OUTSET - AgentReactionGeometry.CLOUD_BUMP_MENU_OUTSET

// The capsule shows once it has grown this far
private const val CAPSULE_FADE_PROGRESS = 0.15f

private val AgentAnswerFeedback.actionTitle: String
    get() = LocaleController.getString(
        when (this) {
            AgentAnswerFeedback.LIKE -> "Like"
            AgentAnswerFeedback.DISLIKE -> "Dislike"
        }
    )

/**
 * The heart and the broken heart over an answer's menu, in a capsule with a thought-bubble tail that hangs beside the
 * menu's top trailing corner. [bumpCenterX] places the tail from the cloud's left, as [placeAgentReactionCloud] gives
 * it. [onSelect] gets the reaction the user chose.
 */
@SuppressLint("ViewConstructor")
internal class AgentReactionCloudView(
    context: Context,
    private val feedback: AgentAnswerFeedback?,
    private val isRtl: Boolean,
    bumpCenterX: Int,
    private val onSelect: (AgentAnswerFeedback) -> Unit
) : FrameLayout(context),
    WThemedView {

    // Raised and shadowed as the message menu's surface is, over the same dim
    private val surfaceElevation = WMenuPopup.surfaceElevation(isOverDim = true)
    private val dot = View(context).apply { elevation = surfaceElevation }
    private val bump = View(context).apply { elevation = surfaceElevation }
    private val capsule = CapsuleView(context, isRtl).apply { elevation = surfaceElevation }
    private val canAnimate = WGlobalStorage.getAreAnimationsActive()
    private val buttons = AgentAnswerFeedback.entries.map { option ->
        ReactionButton(context, option, isChosen = option == feedback, canAnimate).apply {
            // As Telegram's, a choice plays no haptic of its own: the answer taps as the reaction lands on its corner
            setOnClickListener {
                if (!isLeaving) onSelect(option)
            }
        }
    }
    private val dotCenterX = bumpCenterX + DOT_SHIFT_DP.dp * (if (isRtl) -1 else 1)
    private val animators = mutableListOf<Animator>()
    private val poppedButtons = mutableSetOf<ReactionButton>()
    private var isTailShown = false
    private var lastIconPopTime = 0L
    private var isLeaving = false

    // The menu's surface, which the cloud moves with, and the translation it rests at
    private var anchor: View? = null
    private var anchorRestX = 0f
    private var anchorRestY = 0f
    private val anchorListener = ViewTreeObserver.OnPreDrawListener {
        anchor?.let {
            translationX = it.translationX - anchorRestX
            translationY = it.translationY - anchorRestY
        }
        true
    }

    init {
        clipChildren = false
        clipToPadding = false
        layoutDirection = LAYOUT_DIRECTION_LTR
        val dotSize = AgentReactionGeometry.CLOUD_DOT_SIZE.dp.roundToInt()
        val bumpSize = AgentReactionGeometry.CLOUD_BUMP_SIZE.dp.roundToInt()
        addView(
            dot,
            LayoutParams(dotSize, dotSize, Gravity.TOP or Gravity.LEFT).apply {
                leftMargin = (dotCenterX - dotSize / 2f).roundToInt()
                topMargin =
                    (AgentReactionGeometry.CLOUD_DOT_CENTER_Y.dp - dotSize / 2f).roundToInt()
            }
        )
        // The capsule covers the bump's top, so the bump reads as part of it
        addView(
            bump,
            LayoutParams(bumpSize, bumpSize, Gravity.TOP or Gravity.LEFT).apply {
                leftMargin = bumpCenterX - bumpSize / 2
                topMargin =
                    (AgentReactionGeometry.CLOUD_BUMP_CENTER_Y.dp - bumpSize / 2f).roundToInt()
            }
        )
        val width = AgentReactionGeometry.CLOUD_WIDTH.dp.roundToInt()
        val bodyHeight = AgentReactionGeometry.CLOUD_BODY_HEIGHT.dp.roundToInt()
        addView(capsule, LayoutParams(width, bodyHeight, Gravity.TOP or Gravity.LEFT))
        val buttonWidth = BUTTON_WIDTH_DP.dp.roundToInt()
        val iconSize = AgentReactionGeometry.CLOUD_ICON_SIZE.dp
        buttons.forEachIndexed { index, button ->
            val iconLeft =
                agentReactionCloudIconLeft(index, isRtl, resources.displayMetrics.density)
            capsule.addView(
                button,
                LayoutParams(buttonWidth, bodyHeight, Gravity.TOP or Gravity.LEFT).apply {
                    leftMargin = (iconLeft + iconSize / 2 - buttonWidth / 2f).roundToInt()
                }
            )
        }
        updateTheme()
    }

    /**
     * The dot, then the bump pop in; the capsule grows out of its trailing end, and each icon plays Telegram's appear
     * animation as the capsule passes it
     */
    fun animateIn() {
        if (!canAnimate) {
            alpha = 0f
            animate().alpha(1f).setDuration(AgentReactionMotion.FADE_MS).start()
            return
        }
        popTail()
        setCapsuleProgress(0f)
        buttons.forEach {
            it.isAwaitingAppearance = true
            it.selectionAlpha = 0f
        }
        startSpring(
            AgentReactionMotion.CLOUD_CAPSULE_RESPONSE,
            AgentReactionMotion.CLOUD_CAPSULE_DAMPING,
            delay = 2 * AgentReactionMotion.CLOUD_STAGGER_MS
        ) { animator ->
            setCapsuleProgress(animator.animatedValue as Float)
            popPassedIcons()
        }
    }

    /** Moves the cloud with [anchor], the menu's surface, by how far it moves from [restX], [restY], its translation */
    fun follow(anchor: View, restX: Float, restY: Float) {
        this.anchor = anchor
        anchorRestX = restX
        anchorRestY = restY
    }

    /** The cloud shrinks back toward its tail's dot, or fades, and leaves */
    fun animateOut() {
        if (isLeaving) return
        isLeaving = true
        animators.toList().forEach { it.cancel() }
        val animation = animate().alpha(0f)
        if (WGlobalStorage.getAreAnimationsActive()) {
            pivotX = dotCenterX
            pivotY = AgentReactionGeometry.CLOUD_DOT_CENTER_Y.dp
            animation.scaleX(AgentReactionMotion.CLOUD_OUT_SCALE)
                .scaleY(AgentReactionMotion.CLOUD_OUT_SCALE)
                .setInterpolator(CubicBezierInterpolator.EASE_IN)
                .setDuration(AgentReactionMotion.CLOUD_OUT_MS)
        } else {
            animation.setDuration(AgentReactionMotion.FADE_MS)
        }
        animation.withEndAction { (parent as? ViewGroup)?.removeView(this) }.start()
    }

    /**
     * The chosen [option] leaves the cloud, flying to the answer's corner from where the press left its icon: gives that
     * rect in the window and the frame the icon's still is on, as the icon gives way to it. The cloud closes into its
     * tail, as Telegram's does.
     */
    fun release(option: AgentAnswerFeedback): AgentReactionSource? {
        val pressed = buttonFor(option) ?: return null
        if (!pressed.isAttachedToWindow || isLeaving) return null
        val location = pressed.getLocationInWindow()
        val scaleX = pressed.scaleX * capsule.scaleX
        val scaleY = pressed.scaleY * capsule.scaleY
        val centerX = location.x + pressed.width * scaleX / 2
        val centerY = location.y + pressed.height * scaleY / 2
        val half = AgentReactionGeometry.CLOUD_ICON_SIZE.dp * pressed.pressScale * scaleX / 2
        val source = AgentReactionSource(
            RectF(centerX - half, centerY - half, centerX + half, centerY + half),
            pressed.stillProgress
        )
        pressed.alpha = 0f
        animateOut()
        return source
    }

    override fun updateTheme() {
        val background = agentReactionFillColor
        dot.setBackgroundColor(background, AgentReactionGeometry.CLOUD_DOT_SIZE.dp / 2, true)
        bump.setBackgroundColor(background, AgentReactionGeometry.CLOUD_BUMP_SIZE.dp / 2, true)
        capsule.color = background
        buttons.forEach { it.invalidate() }
        listOf(dot, bump, capsule).forEach { WMenuPopup.applySurfaceShadowColors(it) }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        viewTreeObserver.addOnPreDrawListener(anchorListener)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        viewTreeObserver.removeOnPreDrawListener(anchorListener)
        animators.toList().forEach { it.cancel() }
    }

    private fun setCapsuleProgress(progress: Float) {
        capsule.reveal = progress.coerceAtMost(1f)
        val scale = lerp(AgentReactionMotion.CLOUD_CAPSULE_START_SCALE, 1f, progress)
        capsule.scaleX = scale
        capsule.scaleY = scale
        capsule.alpha = (progress / CAPSULE_FADE_PROGRESS).coerceIn(0f, 1f)
    }

    // The dot, then the bump pop in
    private fun popTail() {
        isTailShown = true
        listOf(dot, bump).forEachIndexed { index, view ->
            view.scaleX = 0f
            view.scaleY = 0f
            startSpring(
                AgentReactionMotion.CLOUD_DOT_RESPONSE,
                AgentReactionMotion.CLOUD_DOT_DAMPING,
                delay = index * AgentReactionMotion.CLOUD_STAGGER_MS
            ) { animator ->
                val progress = animator.animatedValue as Float
                view.scaleX = progress
                view.scaleY = progress
            }
        }
    }

    // [button]'s icon appears, at least the stagger after the one before
    private fun appearIcon(button: ReactionButton) {
        poppedButtons += button
        val now = SystemClock.uptimeMillis()
        val delay = max(0L, lastIconPopTime + AgentReactionMotion.ICON_STAGGER_MS - now)
        lastIconPopTime = now + delay
        showSelection(button, delay) {
            button.appear(agentReactionSlotAppearance(canAnimate))
        }
    }

    private fun buttonFor(option: AgentAnswerFeedback): ReactionButton? =
        buttons.getOrNull(AgentAnswerFeedback.entries.indexOf(option))

    // An icon appears once the capsule's growing edge passes its centre
    private fun popPassedIcons() {
        val edge = capsule.revealedLeadingEdge
        for (button in buttons) {
            if (button in poppedButtons) continue
            val center = button.left + button.width / 2f
            val isPassed = if (isRtl) edge >= center else edge <= center
            if (isPassed) appearIcon(button)
        }
    }

    // The selection circle appears after [delay], as [onStart] shows the icon
    private fun showSelection(button: ReactionButton, delay: Long, onStart: () -> Unit = {}) {
        val grow = AgentReactionMotion.telegramSpring(AgentReactionMotion.SELECTION_GROW_MS)
        val fadeShare = AgentReactionMotion.SELECTION_FADE_MS.toFloat() /
            AgentReactionMotion.SELECTION_GROW_MS
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AgentReactionMotion.SELECTION_GROW_MS
            startDelay = delay
            interpolator = LinearInterpolator()
            addUpdateListener {
                val time = it.animatedValue as Float
                val alpha = CubicBezierInterpolator.EASE_BOTH
                    .getInterpolation((time / fadeShare).coerceAtMost(1f))
                val scale = lerp(
                    AgentReactionMotion.SELECTION_START_SCALE,
                    1f,
                    grow.getInterpolation(time)
                )
                button.setSelection(alpha, scale)
            }
            doOnStart { onStart() }
            doOnEnd { animators.remove(this) }
            animators += this
            start()
        }
    }

    private fun startSpring(
        response: Float,
        damping: Float,
        delay: Long,
        onUpdate: (ValueAnimator) -> Unit
    ): ValueAnimator = AgentReactionMotion.spring(response, damping).apply {
        startDelay = delay
        addUpdateListener(onUpdate)
        doOnEnd { animators.remove(this) }
        animators += this
        start()
    }

    /** The capsule, revealed from its trailing end; what it holds is clipped to what is revealed */
    @SuppressLint("ViewConstructor")
    private class CapsuleView(context: Context, private val isRtl: Boolean) : FrameLayout(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val shape = RectF()

        var color: Int
            get() = paint.color
            set(value) {
                paint.color = value
                invalidate()
            }

        /** 0: a circle at the trailing end, 1: the whole capsule */
        var reveal = 1f
            set(value) {
                field = value
                invalidateOutline()
                invalidate()
            }

        /** The x of the revealed part's leading edge */
        val revealedLeadingEdge: Float
            get() = if (isRtl) revealedWidth else width - revealedWidth

        private val revealedWidth: Float get() = lerp(height.toFloat(), width.toFloat(), reveal)

        init {
            setWillNotDraw(false)
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    updateShape()
                    outline.setRoundRect(
                        shape.left.roundToInt(),
                        0,
                        shape.right.roundToInt(),
                        height,
                        height / 2f
                    )
                }
            }
            clipToOutline = true
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            // The capsule grows out of the circle at its trailing end
            pivotX = if (isRtl) h / 2f else w - h / 2f
            pivotY = h / 2f
        }

        override fun onDraw(canvas: Canvas) {
            updateShape()
            canvas.drawRoundRect(shape, height / 2f, height / 2f, paint)
        }

        private fun updateShape() {
            val revealed = revealedWidth
            if (isRtl) {
                shape.set(0f, 0f, revealed, height.toFloat())
            } else {
                shape.set(width - revealed, 0f, width.toFloat(), height.toFloat())
            }
        }
    }

    /**
     * A reaction's icon, over a neutral circle when it is the answer's reaction. It rests on Telegram's still, the first
     * frame of its select animation, which a press plays as it sinks the icon.
     */
    @SuppressLint("ViewConstructor")
    private class ReactionButton(
        context: Context,
        private val option: AgentAnswerFeedback,
        isChosen: Boolean,
        private val canAnimate: Boolean
    ) : View(context) {
        private val still =
            AgentReactionAnimations.drawable(context, option, AgentReactionAnimation.SELECT)
                ?.also { it.callback = this }
        private var appearance: LottieDrawable? = null
        private val selectionPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private var pressAnimator: ValueAnimator? = null

        /** The press's sink, as the icon shows it */
        var pressScale = 1f
            private set(value) {
                field = value
                invalidate()
            }

        /** The frame the icon's still is on, as a press plays select */
        val stillProgress: Float get() = still?.progress ?: 0f

        /** Whether the icon waits for the growing capsule to reach it */
        var isAwaitingAppearance = false
            set(value) {
                field = value
                invalidate()
            }

        /** How much of the selection circle shows, from 0 to 1 */
        var selectionAlpha = 1f
            set(value) {
                field = value
                invalidate()
            }

        // The selection circle's scale as it grows from a dot
        private var selectionScale = 1f

        fun setSelection(alpha: Float, scale: Float) {
            selectionScale = scale
            selectionAlpha = alpha
        }

        init {
            contentDescription = option.actionTitle
            isSelected = isChosen
            isClickable = true
            isFocusable = true
            still?.addAnimatorListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    still.progress = 0f
                }
            })
        }

        /** The capsule has reached the icon: it plays [animation] once, if any, and rests on the still */
        fun appear(animation: AgentReactionAnimation?) {
            isAwaitingAppearance = false
            animation ?: return
            appearance = AgentReactionAnimations.drawable(context, option, animation)?.apply {
                callback = this@ReactionButton
                addAnimatorListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        appearance = null
                        invalidate()
                    }
                })
                playAnimation()
            }
        }

        override fun getAccessibilityClassName(): CharSequence = Button::class.java.name

        // A press sinks the icon and plays select; lifting the finger on the icon chooses it, however long it pressed
        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    press(isPressed = true)
                    playSelect()
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> press(isPressed = false)
            }
            return super.onTouchEvent(event)
        }

        override fun verifyDrawable(who: Drawable): Boolean =
            who === still || who === appearance || super.verifyDrawable(who)

        override fun onDraw(canvas: Canvas) {
            val centerX = width / 2f
            val centerY = height / 2f
            if (isSelected && selectionAlpha > 0f) {
                drawAgentReactionSelection(
                    canvas,
                    selectionPaint,
                    centerX,
                    centerY,
                    AgentReactionGeometry.SELECTION_SIZE.dp / 2 * selectionScale,
                    selectionAlpha
                )
            }
            if (isAwaitingAppearance) return
            val icon = appearance ?: still ?: return
            val half = AgentReactionGeometry.CLOUD_ICON_SIZE.dp / 2
            icon.setBounds(
                (centerX - half).roundToInt(),
                (centerY - half).roundToInt(),
                (centerX + half).roundToInt(),
                (centerY + half).roundToInt()
            )
            val scale = pressScale
            canvas.save()
            canvas.scale(scale, scale, centerX, centerY)
            icon.draw(canvas)
            canvas.restore()
        }

        // The still plays select once, while the icon has appeared
        private fun playSelect() {
            if (agentReactionPressAnimation(canAnimate) == null || appearance != null) return
            val still = still ?: return
            if (still.isAnimating) return
            still.progress = 0f
            still.playAnimation()
        }

        override fun onDetachedFromWindow() {
            super.onDetachedFromWindow()
            pressAnimator?.cancel()
            still?.cancelAnimation()
            appearance?.cancelAnimation()
        }

        private fun press(isPressed: Boolean) {
            pressAnimator?.cancel()
            if (!WGlobalStorage.getAreAnimationsActive()) {
                pressScale = if (isPressed) AgentReactionMotion.PRESSED_SCALE else 1f
                return
            }
            val from = pressScale
            pressAnimator = if (isPressed) {
                ValueAnimator.ofFloat(0f, 1f).apply {
                    duration = AgentReactionMotion.PRESS_MS
                    interpolator = CubicBezierInterpolator.EASE_OUT
                }
            } else {
                AgentReactionMotion.spring(
                    AgentReactionMotion.RELEASE_RESPONSE,
                    AgentReactionMotion.RELEASE_DAMPING
                )
            }.apply {
                val to = if (isPressed) AgentReactionMotion.PRESSED_SCALE else 1f
                addUpdateListener { pressScale = lerp(from, to, it.animatedValue as Float) }
                start()
            }
        }
    }
}

/** Draws the circle behind an answer's reaction at [centerX], [centerY], of [radius], with [alpha] of its shade */
internal fun drawAgentReactionSelection(
    canvas: Canvas,
    paint: Paint,
    centerX: Float,
    centerY: Float,
    radius: Float,
    alpha: Float
) {
    val color = agentReactionSelectionColor
    paint.color = color
    paint.alpha = (Color.alpha(color) * alpha).roundToInt()
    canvas.drawCircle(centerX, centerY, radius, paint)
}
