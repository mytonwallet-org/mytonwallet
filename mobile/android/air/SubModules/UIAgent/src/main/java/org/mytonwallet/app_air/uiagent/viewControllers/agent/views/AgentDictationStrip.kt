package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.os.SystemClock
import android.text.TextUtils
import android.view.Choreographer
import android.view.Gravity
import android.view.View
import android.view.animation.PathInterpolator
import androidx.core.view.doOnPreDraw
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import org.mytonwallet.app_air.uiagent.agentV2.AGENT_DICTATION_MAX_DURATION_MS
import org.mytonwallet.app_air.uiagent.agentV2.AGENT_DICTATION_WARNING_START_MS
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationPhase
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationState
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

/**
 * The field's content while a question is recorded, as Telegram's recording panel: a blinking red
 * dot, the time with centiseconds and "‹ Slide to cancel", which follows the finger. Locked, the
 * hint gives way to "Cancel"; near the limit it counts down in red; paused, the dot goes and the
 * time stops; while recognizing it reads "Recognizing…".
 */
@SuppressLint("ViewConstructor")
internal class AgentDictationStrip(context: Context) :
    WFrameLayout(context),
    WThemedView {

    var onCancel: (() -> Unit)? = null

    /** The strip's "Cancel", for TalkBack to move to while recognizing */
    val cancelView: View get() = cancelLabel

    private var state = AgentDictationState()
    private var isAnimating = false
    private var blinkAnimator: ValueAnimator? = null
    private var wobbleAnimator: ValueAnimator? = null
    private var wobble = 0f
    private var drag = 0f
    private var slide = 0f

    // While locking turns the hint into Cancel, the hint keeps its place as it rises away
    private var cancelReveal: ValueAnimator? = null
    private var isTimerFrameScheduled = false
    private val timerFrame = Choreographer.FrameCallback {
        isTimerFrameScheduled = false
        updateTimer()
        scheduleTimerFrame()
    }

    private val recordingDot = View(context).apply {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val timerLabel = WLabel(context).apply {
        setStyle(TEXT_SIZE, WFont.Regular)
        gravity = Gravity.CENTER_VERTICAL or Gravity.START
        fontFeatureSettings = "tnum"
        setSingleLine()
    }

    private val hintLabel = WLabel(context).apply {
        setStyle(TEXT_SIZE, WFont.Regular)
        gravity = Gravity.CENTER
        ellipsize = TextUtils.TruncateAt.END
        setSingleLine()
    }

    private val cancelLabel = WLabel(context).apply {
        setStyle(CANCEL_TEXT_SIZE, WFont.Regular)
        text = LocaleController.getString("Cancel")
        gravity = Gravity.CENTER
        isClickable = true
        isFocusable = true
        setSingleLine()
        setOnClickListener { onCancel?.invoke() }
    }

    init {
        minimumHeight = HEIGHT.dp
        clipChildren = false
        clipToPadding = false
        addView(recordingDot, LayoutParams(DOT.dp, DOT.dp))
        addView(timerLabel, LayoutParams(LayoutParams.WRAP_CONTENT, HEIGHT.dp))
        addView(hintLabel, LayoutParams(LayoutParams.WRAP_CONTENT, HEIGHT.dp))
        addView(cancelLabel, LayoutParams(LayoutParams.WRAP_CONTENT, HEIGHT.dp))
        updateTheme()
    }

    fun render(newState: AgentDictationState) {
        val previousPhase = state.phase
        val wasLocked = state.locked
        val wasPaused = state.isPaused
        state = newState
        val isRecording = newState.phase == AgentDictationPhase.RECORDING
        val isRecognizing = newState.phase == AgentDictationPhase.RECOGNIZING
        val isLocked = isRecording && newState.locked
        val canAnimate = isAttachedToWindow && isShown && WGlobalStorage.getAreAnimationsActive()
        // Locking turns "Slide to cancel" into "Cancel", as in Telegram
        val shouldRevealCancel = isLocked && !wasLocked &&
            previousPhase == AgentDictationPhase.RECORDING && canAnimate
        val isComingIn = isRecording && previousPhase != AgentDictationPhase.RECORDING && canAnimate
        val isNearLimit = isRecording && newState.elapsedMs >= AGENT_DICTATION_WARNING_START_MS
        if (!isLocked) cancelReveal?.cancel()
        val shouldKeepHint = shouldRevealCancel || cancelReveal != null

        recordingDot.visibility = if (isRecognizing) GONE else VISIBLE
        if (!isRecording) {
            recordingDot.scaleX = 1f
            recordingDot.scaleY = 1f
        } else if (newState.isPaused != wasPaused) {
            showDot(isShown = !newState.isPaused)
        }
        timerLabel.visibility = if (isRecognizing) GONE else VISIBLE
        cancelLabel.visibility = if (isRecognizing || isLocked) VISIBLE else GONE
        if (!shouldKeepHint) hintLabel.visibility = if (isLocked && !isNearLimit) GONE else VISIBLE
        hintLabel.text = when {
            isRecognizing -> LocaleController.getString("\$agent_dictation_recognizing")

            isNearLimit -> {
                val remainingMs = AGENT_DICTATION_MAX_DURATION_MS - newState.elapsedMs
                formatCountdown(
                    max(0, ceil(remainingMs / 1000.0).toInt()),
                    isCancelShown = isLocked
                )
            }

            // The arrow is isolated so that RTL text doesn't mirror its direction
            LocaleController.isRTL ->
                "\u2066›\u2069 " + LocaleController.getString("\$agent_dictation_slide_to_cancel")

            else -> "‹ " + LocaleController.getString("\$agent_dictation_slide_to_cancel")
        }
        hintLabel.gravity = if (isRecognizing) {
            Gravity.CENTER_VERTICAL or Gravity.START
        } else {
            Gravity.CENTER
        }
        drag = if (isRecording && !newState.locked) {
            cancelSign * max(0f, newState.cancelDragDp).dp
        } else {
            0f
        }
        if (!shouldKeepHint) {
            hintLabel.alpha = if (isRecording && !newState.locked) {
                max(0f, 1f - abs(drag) / measureHintFadeTravel())
            } else {
                1f
            }
        }
        applyHintTranslation()
        updateTimer()
        applyTextColors()
        updateAnimations()
        requestLayout()
        if (shouldRevealCancel) revealCancel()
        // Starts from its first frame, once the strip is laid out
        if (isComingIn) doOnPreDraw { animateComingIn() }
    }

    // The long form where it fits between the timer and Cancel, as in a chat's composer, else the short one, so the
    // countdown never ends in "…"
    private fun formatCountdown(seconds: Int, isCancelShown: Boolean): String {
        val long = LocaleController.getString("\$agent_dictation_time_left")
            .replace("%seconds%", seconds.toString())
        if (width <= 0) return long
        val cancelSpace = if (isCancelShown) {
            cancelLabel.measuredWidth + CANCEL_PADDING.dp + HINT_CANCEL_GAP.dp
        } else {
            0
        }
        val room = width - (DOT.dp + GAP.dp + measureTimerWidth() + GAP.dp) - cancelSpace
        val longWidth = ceil(hintLabel.paint.measureText(long)).toInt() +
            hintLabel.paddingLeft + hintLabel.paddingRight
        if (longWidth <= room) return long
        return LocaleController.getString("\$agent_dictation_time_left_short")
            .replace("%seconds%", seconds.toString())
    }

    // The hint is gone by the time its text reaches the timer, and 110 dp along at most
    private fun measureHintFadeTravel(): Float {
        val textWidth = hintLabel.paint.measureText(hintLabel.text.toString())
        val textStart = max(0f, (hintLabel.width - textWidth) / 2f)
        return min(HINT_FADE_TRAVEL.dp, textStart + GAP.dp)
    }

    // Toward the start of the line in reading order
    private val cancelSign: Float
        get() = if (LocaleController.isRTL) 1f else -1f

    private fun applyHintTranslation() {
        hintLabel.translationX = drag + wobble + slide
    }

    private fun updateTimer() {
        val isRunning = state.phase == AgentDictationPhase.RECORDING && !state.isPaused
        val elapsed = if (isRunning && state.startedAtMs > 0L) {
            (SystemClock.elapsedRealtime() - state.startedAtMs)
                .coerceIn(0L, AGENT_DICTATION_MAX_DURATION_MS)
        } else {
            state.elapsedMs
        }
        val seconds = elapsed / 1000
        val centiseconds = min(99L, elapsed % 1000 / 10)
        // "m:ss,cc", every frame without formatting
        timerText.setLength(0)
        timerText.append(seconds / 60).append(':')
        if (seconds % 60 < 10) timerText.append('0')
        timerText.append(seconds % 60).append(',')
        if (centiseconds < 10) timerText.append('0')
        timerText.append(centiseconds)
        timerLabel.text = timerText
    }

    private val timerText = StringBuilder()

    // As wide as the widest time, so a new time only redraws the label
    private fun measureTimerWidth(): Int {
        val paint = timerLabel.paint
        val digit = (0..9).maxOf { paint.measureText(it.toString()) }
        val text = TIMER_DIGITS * digit + paint.measureText(":") + paint.measureText(",")
        return ceil(text).toInt() + timerLabel.paddingLeft + timerLabel.paddingRight
    }

    private fun scheduleTimerFrame() {
        if (isTimerFrameScheduled || !isAnimating) return
        isTimerFrameScheduled = true
        Choreographer.getInstance().postFrameCallback(timerFrame)
    }

    // Telegram's recording panel coming in: the hint slides in from past the end, the timer fades
    // in on its layout spring, and the dot grows in before it starts blinking
    private fun animateComingIn() {
        if (!isAttachedToWindow) return
        val textWidth = min(
            hintLabel.width.toFloat(),
            hintLabel.paint.measureText(hintLabel.text.toString())
        )
        val startX = if (LocaleController.isRTL) {
            -textWidth - hintLabel.left
        } else {
            width + textWidth - hintLabel.left
        }
        ValueAnimator.ofFloat(startX, 0f).apply {
            duration = SLIDE_IN_MS
            interpolator = TELEGRAM_CURVE
            addUpdateListener {
                slide = it.animatedValue as Float
                applyHintTranslation()
            }
            start()
        }
        timerLabel.alpha = 0f
        timerLabel.animate().alpha(1f).setDuration(TIMER_FADE_MS)
            .setInterpolator(TELEGRAM_SPRING).start()
        blinkAnimator?.cancel()
        recordingDot.alpha = 0f
        recordingDot.scaleX = DOT_FROM_SCALE
        recordingDot.scaleY = DOT_FROM_SCALE
        recordingDot.animate().alpha(1f).scaleX(1f).scaleY(1f)
            .setDuration(DOT_APPEARANCE_MS)
            .setInterpolator(WInterpolator.easeInOut)
            .withEndAction { if (isAnimating) startBlink() }
            .start()
    }

    // Telegram's paused recording: the dot shrinks away, and grows back as the recording resumes
    private fun showDot(isShown: Boolean) {
        val scale = if (isShown) 1f else 0f
        recordingDot.animate().cancel()
        if (!isAttachedToWindow || !WGlobalStorage.getAreAnimationsActive()) {
            recordingDot.scaleX = scale
            recordingDot.scaleY = scale
            return
        }
        recordingDot.animate().scaleX(scale).scaleY(scale).setDuration(DOT_APPEARANCE_MS)
            .setInterpolator(WInterpolator.easeInOut).start()
    }

    // Telegram's `updateIsDisplayingCancel`: the hint rises and shrinks away while Cancel rises in
    private fun revealCancel() {
        val hint = hintLabel
        hint.animate().cancel()
        hint.pivotX = hint.width / 2f
        hint.pivotY = hint.height / 2f
        hint.animate().translationY(-CANCEL_REVEAL_OFFSET.dp.toFloat())
            .setDuration(HINT_RISE_MS).start()
        cancelReveal = ValueAnimator.ofFloat(1f, 0f).apply {
            duration = CANCEL_REVEAL_MS
            addUpdateListener {
                val fade = it.animatedValue as Float
                hint.alpha = fade
                val scale = CANCEL_REVEAL_SCALE + (1 - CANCEL_REVEAL_SCALE) * fade
                hint.scaleX = scale
                hint.scaleY = scale
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (cancelReveal === animation) cancelReveal = null
                    hint.animate().cancel()
                    hint.translationY = 0f
                    hint.scaleX = 1f
                    hint.scaleY = 1f
                    hint.alpha = 1f
                    val isNearLimit = state.elapsedMs >= AGENT_DICTATION_WARNING_START_MS
                    if (state.locked && !isNearLimit) hint.visibility = GONE
                    requestLayout()
                }
            })
            start()
        }
        cancelLabel.translationY = CANCEL_REVEAL_OFFSET.dp.toFloat()
        cancelLabel.scaleX = CANCEL_REVEAL_SCALE
        cancelLabel.scaleY = CANCEL_REVEAL_SCALE
        cancelLabel.alpha = 0f
        cancelLabel.animate().translationY(0f).scaleX(1f).scaleY(1f).alpha(1f)
            .setDuration(CANCEL_REVEAL_MS).start()
    }

    private fun updateAnimations() {
        val shouldAnimate = isAttachedToWindow && state.phase == AgentDictationPhase.RECORDING &&
            !state.isPaused
        val isMotionOn = WGlobalStorage.getAreAnimationsActive()
        if (shouldAnimate == isAnimating) return
        isAnimating = shouldAnimate
        if (!shouldAnimate) {
            blinkAnimator?.cancel()
            blinkAnimator = null
            wobbleAnimator?.cancel()
            wobbleAnimator = null
            wobble = 0f
            recordingDot.alpha = 1f
            applyHintTranslation()
            return
        }
        scheduleTimerFrame()
        if (!isMotionOn) return
        startBlink()
        // The wobble rides on the slide that follows the finger
        wobbleAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = WOBBLE_MS
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener {
                val t = it.animatedValue as Float
                val half = if (t < 0.5f) t * 2 else (1 - t) * 2
                wobble =
                    cancelSign * HINT_WOBBLE.dp * WInterpolator.easeInOut.getInterpolation(half)
                applyHintTranslation()
            }
            start()
        }
    }

    // Telegram's recording dot: on for half the cycle, then off, back and forth
    private fun startBlink() {
        blinkAnimator?.cancel()
        if (!WGlobalStorage.getAreAnimationsActive()) return
        blinkAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = BLINK_MS
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            addUpdateListener {
                val t = it.animatedValue as Float
                recordingDot.alpha = when {
                    t <= BLINK_ON_END -> 1f
                    t >= BLINK_OFF_START -> 0f
                    else -> 1f - (t - BLINK_ON_END) / (BLINK_OFF_START - BLINK_ON_END)
                }
            }
            start()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updateAnimations()
    }

    override fun onDetachedFromWindow() {
        isAnimating = false
        blinkAnimator?.cancel()
        wobbleAnimator?.cancel()
        Choreographer.getInstance().removeFrameCallback(timerFrame)
        isTimerFrameScheduled = false
        super.onDetachedFromWindow()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val height = HEIGHT.dp
        val wrap = MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        val exactHeight = MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY)
        recordingDot.measure(
            MeasureSpec.makeMeasureSpec(DOT.dp, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(DOT.dp, MeasureSpec.EXACTLY)
        )
        val timerWidth = measureTimerWidth()
        // A fixed width keeps the label from asking for a layout with every new time
        if (timerLabel.layoutParams.width != timerWidth) timerLabel.layoutParams.width = timerWidth
        timerLabel.measure(
            MeasureSpec.makeMeasureSpec(timerWidth, MeasureSpec.EXACTLY),
            exactHeight
        )
        cancelLabel.measure(wrap, exactHeight)
        val hintWidth = max(0, computeHintWidth(MeasureSpec.getSize(widthMeasureSpec)))
        hintLabel.measure(MeasureSpec.makeMeasureSpec(hintWidth, MeasureSpec.EXACTLY), exactHeight)
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), height)
    }

    private fun computeContentStart(): Int = if (state.phase == AgentDictationPhase.RECOGNIZING) {
        0
    } else {
        DOT.dp + GAP.dp + timerLabel.measuredWidth + GAP.dp
    }

    // Cancel rises into the middle, where the hint fades, unless the countdown stays beside it
    private val isCancelCentred: Boolean
        get() = state.phase == AgentDictationPhase.RECORDING && state.locked &&
            (hintLabel.visibility == GONE || cancelReveal != null)

    private fun computeCancelWidth(available: Int): Int = min(
        cancelLabel.measuredWidth + CANCEL_PADDING.dp,
        max(0, available - computeContentStart())
    )

    private fun computeCancelX(available: Int): Int {
        val contentStart = computeContentStart()
        val cancelWidth = computeCancelWidth(available)
        return if (isCancelCentred) {
            contentStart + (available - contentStart - cancelWidth) / 2
        } else {
            available - cancelWidth
        }
    }

    private fun computeHintWidth(available: Int): Int {
        val end = if (cancelLabel.visibility == VISIBLE && !isCancelCentred) {
            computeCancelX(available) - HINT_CANCEL_GAP.dp
        } else {
            available
        }
        return end - computeContentStart()
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val width = right - left
        val height = bottom - top
        val isRtl = LocaleController.isRTL
        fun place(view: View, x: Int, viewWidth: Int, viewHeight: Int) {
            val start = if (isRtl) width - x - viewWidth else x
            val y = (height - viewHeight) / 2
            view.layout(start, y, start + viewWidth, y + viewHeight)
        }
        place(recordingDot, 0, DOT.dp, DOT.dp)
        place(timerLabel, DOT.dp + GAP.dp, timerLabel.measuredWidth, height)
        place(cancelLabel, computeCancelX(width), computeCancelWidth(width), height)
        place(hintLabel, computeContentStart(), max(0, computeHintWidth(width)), height)
    }

    private fun applyTextColors() {
        val isNearLimit = state.phase == AgentDictationPhase.RECORDING &&
            state.elapsedMs >= AGENT_DICTATION_WARNING_START_MS
        timerLabel.setTextColor(if (isNearLimit) WColor.Error else WColor.PrimaryText)
        hintLabel.setTextColor(if (isNearLimit) WColor.Error else WColor.SecondaryText)
    }

    override fun updateTheme() {
        recordingDot.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(RECORDING_DOT_COLOR)
        }
        cancelLabel.setTextColor(WColor.Tint)
        applyTextColors()
    }

    private companion object {
        // "m:ss,cc"
        const val TIMER_DIGITS = 5
        const val HEIGHT = 48
        const val DOT = 10
        const val GAP = 8
        const val TEXT_SIZE = 15f
        const val CANCEL_TEXT_SIZE = 17f
        const val CANCEL_PADDING = 12
        const val HINT_CANCEL_GAP = 4
        const val HINT_FADE_TRAVEL = 110f
        const val HINT_WOBBLE = 6f
        const val CANCEL_REVEAL_OFFSET = 22
        const val CANCEL_REVEAL_SCALE = 0.25f
        const val DOT_FROM_SCALE = 0.3f
        const val RECORDING_DOT_COLOR = 0xFFFF2D55.toInt()

        const val SLIDE_IN_MS = 400L
        const val TIMER_FADE_MS = 500L
        const val DOT_APPEARANCE_MS = 150L
        const val HINT_RISE_MS = 200L
        const val CANCEL_REVEAL_MS = 250L
        const val WOBBLE_MS = 1500L
        const val BLINK_MS = 500L
        const val BLINK_ON_END = 0.4546f
        const val BLINK_OFF_START = 0.9091f

        val TELEGRAM_CURVE = PathInterpolator(0.38f, 0.7f, 0.125f, 1f)

        // Telegram's layout spring (mass 1, stiffness 555, damping 47): critically damped, ~0.4 s
        val TELEGRAM_SPRING = WInterpolator.spring(0.99f, 9f)
    }
}
