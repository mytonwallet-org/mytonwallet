package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.os.Build
import android.view.Choreographer
import android.view.View
import android.view.ViewGroup
import android.view.animation.PathInterpolator
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan
import kotlin.random.Random
import org.mytonwallet.app_air.uiagent.R
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationPhase
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationState
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

/**
 * The recording circle, grown out of the microphone while a question is recorded, as on iOS: a solid accent circle
 * with the microphone inside two voice waves that swell with the voice. Held, it follows the finger along the field
 * between the cross and Send. A tap's hands-free recording shows it as the stop button, as big as the field's buttons
 * and without waves, which a tap on it finishes. A recording that produced no transcript turns it red with a smaller
 * cross before it shrinks back into the microphone.
 *
 * It draws in [anchor]'s window overlay, so nothing clips it, where the microphone stood as the recording started, as
 * the field widens around it. It takes no touches but the stop button's.
 */
internal class AgentDictationCircle(private val anchor: View) {
    /** The circle shows or has gone */
    var onVisibilityChanged: ((Boolean) -> Unit)? = null

    /** The window was resized under a shown circle, which has taken its new place: the field's ends are measured anew */
    var onHostResized: (() -> Unit)? = null

    /** The stop button of a hands-free recording is tapped */
    var onStop: (() -> Unit)? = null

    /**
     * How much the circle stands in for the microphone, from 0 to 1: it covers it as it grows out of it, keeps it
     * hidden wherever the finger takes the circle, and gives it back as the circle goes
     */
    var onCoverChanged: ((Float) -> Unit)? = null
    private var cover = 0f

    private val layer = CircleLayer()
    private var host: View? = null
    private val location = IntArray(2)
    private var isFrameScheduled = false
    private val frameCallback = Choreographer.FrameCallback {
        isFrameScheduled = false
        step()
    }

    private var phase = AgentDictationPhase.IDLE
    private var isLocked = false
    private var isPresented = false
    private var isShowingFailure = false
    private var lastFrameNanos = 0L

    // Where the circle rests in the window, in px: where the microphone stood as the recording started, under the
    // finger, as the field then widens on both sides around it
    private var restingX = 0f

    // The cross's and Send's centres from the field's start, which the held circle travels between, in px
    private var travelStart = Float.NaN
    private var travelEnd = Float.NaN

    // How far from Send's centre a hands-free recording's stop keeps, in px, so both can be tapped
    private var sendClearance = 0f
    private var lastState: AgentDictationState? = null
    private val hostLayoutListener =
        View.OnLayoutChangeListener { view, left, _, right, _, oldLeft, _, oldRight, _ ->
            if (right - left != oldRight - oldLeft) handleHostResize(view)
        }

    // Where the finger has taken the circle along the field, in px, and its size
    private var targetCancelX = 0f
    private var currentCancelX = 0f
    private var currentScale = 1f

    private val blobScale = Tween(1f)
    private val blobAlpha = Tween(1f)
    private val wavesShown = Tween(1f)
    private val failureColor = Tween(0f)
    private val wavesAlpha = Tween(1f)
    private val presence = Tween(RESTING_PRESENCE)
    private var failureStartNanos = 0L
    private var hasFailureBeenPresented = false

    private var glyph = Glyph.MICROPHONE
    private var previousGlyph: Glyph? = null
    private var glyphSwapStartNanos = 0L

    private var level = 0f
    private var presentationLevel = 0f
    private val outerMotion = BlobMotion()
    private val innerMotion = BlobMotion()

    private var tint = WColor.Tint.color
    private var onTintColor = WColor.TextOnTint.color
    private var error = WColor.Error.color

    // The overlay takes no touches, so the stop button's own tap target lies over it in the window
    private val stopTarget = View(anchor.context).apply {
        isClickable = true
        isFocusable = true
        contentDescription = LocaleController.getString("\$agent_dictation_finish")
        setOnClickListener { onStop?.invoke() }
    }

    private val isAnimated: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() && anchor.isAttachedToWindow &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled())

    // A hands-free recording's stop keeps to the size of the field's buttons
    private val targetScale: Float
        get() = if (isLocked && phase == AgentDictationPhase.RECORDING) STOP_SCALE else 1f

    /** From the field's start to the circle's centre where it rests, in px */
    val restingDistance: Float
        get() = microphoneDistance + resolveHandsFreeShift() * LocaleController.rtlMultiplier

    // From the field's start to where the microphone stood as the recording started, in px
    private val microphoneDistance: Float
        get() = (restingX - resolveFieldStart()) * LocaleController.rtlMultiplier

    /**
     * The cross's and Send's centres from the field's start, in px, which the held circle travels between, and how far
     * from Send's centre a hands-free recording's stop keeps
     */
    fun setTravelBounds(cross: Float, send: Float, sendClearance: Float) {
        travelStart = min(cross, send)
        travelEnd = max(cross, send)
        this.sendClearance = sendClearance
    }

    fun update(state: AgentDictationState) {
        lastState = state
        val previousPhase = phase
        phase = state.phase
        isLocked = state.locked
        level = state.waveLevel
        outerMotion.updateSpeedLevel(level)
        innerMotion.updateSpeedLevel(level)
        val isRecording = state.phase == AgentDictationPhase.RECORDING
        if (isRecording && !isPresented) captureRestingPlace()
        targetCancelX = if (isRecording && !state.locked) {
            // The circle follows the finger along the field, from the cross to Send and no further
            val sign = if (LocaleController.isRTL) 1f else -1f
            clampTravel(sign * state.cancelDragDp.dp)
        } else {
            resolveHandsFreeShift()
        }
        if (previousPhase != state.phase && state.phase == AgentDictationPhase.FAILED) {
            showFailure()
            return
        }
        if (isRecording) {
            val canAnimate = isPresented && isAnimated
            setGlyph(if (state.locked) Glyph.STOP else Glyph.MICROPHONE, shouldAnimate = canAnimate)
            // The stop has no waves
            val waves = if (state.locked) 0f else 1f
            val now = System.nanoTime()
            if (!canAnimate) {
                wavesShown.set(waves)
            } else if (wavesShown.evaluate(now) != waves && !wavesShown.isRunning(now)) {
                wavesShown.animate(waves, now, WAVES_SWAP_MS, WInterpolator.easeInOut)
            }
        }
        when {
            isRecording && !isPresented -> present()
            !isRecording && isPresented -> dismiss()
            state.phase == AgentDictationPhase.IDLE && isShowingFailure -> endFailureEarly()
            isPresented -> scheduleFrame()
        }
    }

    private fun clampTravel(offset: Float): Float {
        if (travelStart.isNaN() || travelEnd.isNaN()) return offset
        val direction = LocaleController.rtlMultiplier
        val distance = offset * direction
        val resting = microphoneDistance
        val lowest = min(0f, travelStart - resting)
        val highest = max(0f, travelEnd - resting)
        return distance.coerceIn(lowest, highest) * direction
    }

    // A hands-free recording's stop moves a button before Send where the microphone stood in Send's place, in px
    private fun resolveHandsFreeShift(): Float {
        if (!isLocked || phase != AgentDictationPhase.RECORDING || travelEnd.isNaN()) return 0f
        val beforeSend = travelEnd - sendClearance
        val resting = microphoneDistance
        return min(0f, beforeSend - resting) * LocaleController.rtlMultiplier
    }

    // A resized window lays the field out anew, so the circle goes to where the microphone now stands
    private fun handleHostResize(root: View) {
        layer.setBounds(0, 0, root.width, root.height)
        if (!isPresented) return
        captureRestingPlace()
        onHostResized?.invoke() ?: lastState?.let(::update)
    }

    fun updateTheme() {
        tint = WColor.Tint.color
        onTintColor = WColor.TextOnTint.color
        error = WColor.Error.color
        layer.updateTheme()
        layer.invalidateSelf()
    }

    fun detach() {
        isPresented = false
        isShowingFailure = false
        hide()
    }

    // The microphone's centre in the window, before the field widens for the recording
    private fun captureRestingPlace() {
        if (anchor.width <= 0) return
        anchor.getLocationInWindow(location)
        restingX = location[0] + anchor.width / 2f
    }

    private fun resolveFieldStart(): Float {
        val field = anchor.parent as? View ?: return 0f
        field.getLocationInWindow(location)
        return location[0] + if (LocaleController.isRTL) field.width * field.scaleX else 0f
    }

    private fun present() {
        isPresented = true
        isShowingFailure = false
        captureRestingPlace()
        currentCancelX = targetCancelX
        currentScale = targetScale
        failureColor.set(0f)
        wavesAlpha.set(1f)
        wavesShown.set(if (isLocked) 0f else 1f)
        blobAlpha.set(1f)
        setGlyph(if (isLocked) Glyph.STOP else Glyph.MICROPHONE, shouldAnimate = false)
        presentationLevel = 0f
        lastFrameNanos = 0L
        show()
        val now = System.nanoTime()
        if (!isAnimated) {
            presence.set(1f)
            blobScale.set(1f)
            updateCover(now)
            return
        }
        presence.set(RESTING_PRESENCE)
        presence.animate(1f, now, PRESENCE_IN_MS, WInterpolator.easeInOut)
        // As in Telegram, the circle and its waves grow out of the microphone at once; a stop grows straight to its
        // size
        blobScale.set(PRESENT_FROM_SCALE)
        blobScale.animate(1f, now, PRESENT_MS, PRESENT_SPRING)
        updateCover(now)
    }

    private fun updateCover(now: Long) {
        val value = when {
            host == null -> 0f

            isPresented -> {
                val diameter = currentScale * blobScale.evaluate(now) * CENTRE_DIAMETER.dp
                (diameter / anchor.width.coerceAtLeast(1)).coerceIn(0f, 1f)
            }

            else -> blobAlpha.evaluate(now).coerceIn(0f, 1f)
        }
        if (value == cover) return
        cover = value
        onCoverChanged?.invoke(value)
    }

    private fun dismiss() {
        isPresented = false
        removeStopTarget()
        if (!isAnimated) {
            hide()
            return
        }
        val now = System.nanoTime()
        blobScale.animate(PRESENT_FROM_SCALE, now, DISMISS_MS, WInterpolator.easeInOut)
        blobAlpha.animate(0f, now, DISMISS_MS, WInterpolator.easeInOut)
        scheduleFrame()
    }

    /**
     * The circle pops back out of the microphone after recognition, or swells where it is after a recording, turns
     * red as its waves go and shows a cross as it settles smaller, then shrinks onto the microphone and fades into it,
     * within the controller's failure phase
     */
    private fun showFailure() {
        hasFailureBeenPresented = isPresented
        isPresented = false
        isShowingFailure = true
        removeStopTarget()
        if (!hasFailureBeenPresented) {
            captureRestingPlace()
            currentCancelX = 0f
        }
        currentScale = 1f
        val now = System.nanoTime()
        failureStartNanos = now
        show()
        if (hasFailureBeenPresented && isAnimated) {
            failureColor.animate(1f, now, FAILURE_COLOR_MS, WInterpolator.easeInOut)
            wavesAlpha.animate(0f, now, FAILURE_COLOR_MS, WInterpolator.easeInOut)
        } else {
            failureColor.set(1f)
            wavesAlpha.set(0f)
        }
        setGlyph(Glyph.CROSS, shouldAnimate = hasFailureBeenPresented && isAnimated)
        if (!isAnimated) {
            currentCancelX = 0f
            blobScale.set(FAILURE_SCALE)
            blobAlpha.set(1f)
            return
        }
        if (hasFailureBeenPresented) {
            val from = blobScale.evaluate(now) * (if (isLocked) STOP_SCALE else 1f)
            blobScale.animate(FAILURE_POP_SCALE, now, FAILURE_POP_MS, EASE_OUT, from = from)
            blobScale.continueTo(FAILURE_SCALE, FAILURE_SETTLE_MS, FAILURE_SETTLE_SPRING)
            blobScale.continueTo(collapsedScale, FAILURE_COLLAPSE_MS, FAILURE_COLLAPSE_SPRING)
            blobAlpha.animate(
                0f,
                now,
                FAILURE_FADE_MS,
                EASE_IN,
                delayMs = FAILURE_POP_MS + FAILURE_SETTLE_MS + FAILURE_FADE_DELAY_MS,
                from = 1f
            )
        } else {
            // It pops back out of the microphone
            blobScale.set(collapsedScale)
            blobScale.animate(FAILURE_SCALE, now, FAILURE_EMERGE_MS, FAILURE_EMERGE_SPRING)
            blobScale.continueTo(collapsedScale, FAILURE_COLLAPSE_MS, FAILURE_COLLAPSE_SPRING)
            blobAlpha.animate(1f, now, FAILURE_EMERGE_FADE_MS, WInterpolator.easeInOut, from = 0f)
            blobAlpha.continueTo(
                0f,
                FAILURE_FADE_MS,
                EASE_IN,
                delayMs = FAILURE_EMERGE_MS - FAILURE_EMERGE_FADE_MS + FAILURE_FADE_DELAY_MS
            )
        }
        scheduleFrame()
    }

    // The failure ended before its animation did, so the circle fades out at once
    private fun endFailureEarly() {
        isShowingFailure = false
        if (!isAnimated) {
            hide()
            return
        }
        blobAlpha.animate(0f, System.nanoTime(), FAILURE_END_MS, WInterpolator.easeInOut)
        scheduleFrame()
    }

    private val collapsedScale: Float
        get() = anchor.width.takeIf { it > 0 }?.let { it / CENTRE_DIAMETER.dp }
            ?: FALLBACK_COLLAPSED_SCALE

    // Telegram's glyph swap: the old glyph shrinks away as the new one grows from 30%
    private fun setGlyph(newGlyph: Glyph, shouldAnimate: Boolean) {
        if (glyph == newGlyph) return
        previousGlyph = if (shouldAnimate) glyph else null
        glyph = newGlyph
        glyphSwapStartNanos = System.nanoTime()
        layer.invalidateSelf()
    }

    private fun show() {
        if (host == null) {
            val root = anchor.rootView ?: return
            host = root
            layer.setBounds(0, 0, root.width, root.height)
            root.overlay.add(layer)
            root.addOnLayoutChangeListener(hostLayoutListener)
            onVisibilityChanged?.invoke(true)
        }
        scheduleFrame()
    }

    private fun hide() {
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        isFrameScheduled = false
        removeStopTarget()
        val root = host ?: return
        host = null
        root.removeOnLayoutChangeListener(hostLayoutListener)
        root.overlay.remove(layer)
        updateCover(System.nanoTime())
        onVisibilityChanged?.invoke(false)
    }

    private fun scheduleFrame() {
        if (isFrameScheduled || host == null) return
        isFrameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private fun step() {
        val now = System.nanoTime()
        val deltaSeconds = if (lastFrameNanos == 0L) {
            1f / FRAMES_PER_SECOND
        } else {
            ((now - lastFrameNanos) / NANOS_PER_SECOND).coerceIn(0f, MAX_FRAME_S)
        }
        lastFrameNanos = now
        if (isPresented) {
            // Telegram's smoothing: each frame closes 30% of the remaining distance to the finger. Without motion the
            // circle keeps up with the finger at once.
            val share = if (isAnimated) FOLLOW_SHARE else 1f
            currentCancelX = currentCancelX * (1 - share) + targetCancelX * share
            currentScale = currentScale * (1 - share) + targetScale * share
        } else if (isShowingFailure) {
            // The failure's cross goes back to the microphone's place from where the finger let go, as on iOS and the
            // web
            currentCancelX *= 1 - (if (isAnimated) FOLLOW_SHARE else 1f)
        }
        val smoothing = Math.pow(
            LEVEL_SMOOTHING,
            (deltaSeconds * FRAMES_PER_SECOND).toDouble()
        ).toFloat()
        presentationLevel = presentationLevel * smoothing + level * (1 - smoothing)
        if (isAnimated) {
            outerMotion.advance(deltaSeconds)
            innerMotion.advance(deltaSeconds)
        }
        layer.invalidateSelf()
        updateCover(now)
        updateStopTarget()
        val isFinishedDismissing = !isPresented && !isShowingFailure && !blobAlpha.isRunning(now)
        val isFinishedFailure = isShowingFailure &&
            (now - failureStartNanos) / NANOS_PER_MS > FAILURE_TOTAL_MS && !blobAlpha.isRunning(now)
        // A still stop waits for the next state rather than running frames
        val isSettled = isPresented && !isAnimated && !blobScale.isRunning(now) &&
            !wavesShown.isRunning(now)
        when {
            isFinishedDismissing -> hide()

            isFinishedFailure -> {
                isShowingFailure = false
                hide()
            }

            isSettled -> Unit

            else -> scheduleFrame()
        }
    }

    // The stop's tap target stands over it while it shows
    private fun updateStopTarget() {
        val root = host as? ViewGroup
        if (root == null || !isPresented || !isLocked || phase != AgentDictationPhase.RECORDING ||
            anchor.width <= 0
        ) {
            removeStopTarget()
            return
        }
        val size = STOP_TARGET.dp
        if (stopTarget.parent !== root) {
            removeStopTarget()
            root.addView(stopTarget, ViewGroup.LayoutParams(size, size))
        }
        anchor.getLocationInWindow(location)
        val centreY = location[1] + anchor.height / 2f
        stopTarget.translationX = restingX + currentCancelX - size / 2f
        stopTarget.translationY = centreY - size / 2f
    }

    private fun removeStopTarget() {
        (stopTarget.parent as? ViewGroup)?.removeView(stopTarget)
    }

    private enum class Glyph { MICROPHONE, STOP, CROSS }

    private inner class CircleLayer : Drawable() {
        private val wavePaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val centrePaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val outerPath = Path()
        private val innerPath = Path()
        private val rect = RectF()

        // On the accent, in the colour of text on it, made once the circle's colours are set. Its
        // alpha follows the glyph's.
        private val microphone by lazy {
            ContextCompat.getDrawable(anchor.context, R.drawable.ic_agent_microphone)
                ?.mutate()
                ?.apply { setTint(onTintColor) }
        }

        fun updateTheme() {
            microphone?.setTint(onTintColor)
        }

        override fun draw(canvas: Canvas) {
            if (anchor.width <= 0) return
            val now = System.nanoTime()
            anchor.getLocationInWindow(location)
            val restingY = location[1] + anchor.height / 2f
            drawBlob(canvas, restingX + currentCancelX, restingY, now)
        }

        private fun drawBlob(canvas: Canvas, centreX: Float, centreY: Float, now: Long) {
            val scale = currentScale * blobScale.evaluate(now)
            val alpha = blobAlpha.evaluate(now).coerceIn(0f, 1f)
            if (scale <= 0f || alpha <= 0f) return
            canvas.save()
            canvas.translate(centreX, centreY)
            canvas.scale(scale, scale)
            drawWaves(canvas, alpha * wavesAlpha.evaluate(now).coerceIn(0f, 1f), now)
            val failure = failureColor.evaluate(now).coerceIn(0f, 1f)
            centrePaint.color = applyAlpha(ColorUtils.blendARGB(tint, error, failure), alpha)
            canvas.drawCircle(0f, 0f, CENTRE_DIAMETER.dp / 2f, centrePaint)
            drawGlyphs(canvas, alpha, now)
            canvas.restore()
        }

        private fun drawWaves(canvas: Canvas, alpha: Float, now: Long) {
            val shown = wavesShown.evaluate(now).coerceIn(0f, 1f)
            if (alpha <= 0f || shown <= 0f) return
            val presenceValue = presence.evaluate(now)
            val swell = (OUTER_WAVE_MIN + (OUTER_WAVE_MAX - OUTER_WAVE_MIN) * presentationLevel) *
                presenceValue
            // Sunk into the circle, the waves are as wide as it is
            val outer = CENTRE_DIAMETER + (swell - CENTRE_DIAMETER) * shown
            val inner = sqrt(CENTRE_DIAMETER * outer)
            val isStill = !isAnimated
            outerMotion.buildPath(outerPath, outer.dp, isStill)
            innerMotion.buildPath(innerPath, inner.dp, isStill)
            wavePaint.color = applyAlpha(tint, OUTER_WAVE_ALPHA * alpha)
            canvas.drawPath(outerPath, wavePaint)
            wavePaint.color = applyAlpha(tint, INNER_WAVE_ALPHA * alpha)
            canvas.drawPath(innerPath, wavePaint)
        }

        private fun drawGlyphs(canvas: Canvas, alpha: Float, now: Long) {
            val elapsed = (now - glyphSwapStartNanos) / NANOS_PER_MS
            val old = previousGlyph
            if (old == null || elapsed >= GLYPH_SWAP_MS) {
                previousGlyph = null
                drawGlyph(canvas, glyph, 1f, alpha)
                return
            }
            val move = TELEGRAM_CURVE.getInterpolation((elapsed / GLYPH_SWAP_MS).coerceIn(0f, 1f))
            val fade = (elapsed / GLYPH_FADE_MS).coerceIn(0f, 1f)
            drawGlyph(canvas, old, 1f + (GLYPH_GONE_SCALE - 1f) * move, alpha * (1f - fade))
            val newScale = GLYPH_FROM_SCALE + (1f - GLYPH_FROM_SCALE) * move
            drawGlyph(canvas, glyph, newScale, alpha * fade)
        }

        private fun drawGlyph(canvas: Canvas, kind: Glyph, scale: Float, alpha: Float) {
            if (alpha <= 0f || scale <= 0f) return
            canvas.save()
            canvas.scale(scale, scale)
            when (kind) {
                Glyph.MICROPHONE -> microphone?.let { icon ->
                    val half = MICROPHONE_GLYPH.dp / 2
                    icon.setBounds(-half, -half, half, half)
                    icon.alpha = (255 * alpha).roundToInt()
                    icon.draw(canvas)
                }

                // The composer's Stop, at the circle's size, which the stop shrinks to the field's buttons'
                Glyph.STOP -> {
                    val half = STOP_GLYPH.dp / 2
                    rect.set(-half, -half, half, half)
                    fillPaint.color = applyAlpha(onTintColor, alpha)
                    val radius = STOP_GLYPH_RADIUS.dp
                    canvas.drawRoundRect(rect, radius, radius, fillPaint)
                }

                Glyph.CROSS -> {
                    val half = CROSS_GLYPH.dp / 2
                    strokePaint.strokeWidth = CROSS_STROKE.dp
                    // White on the failure's red
                    strokePaint.color = applyAlpha(Color.WHITE, alpha)
                    canvas.drawLine(-half, -half, half, half, strokePaint)
                    canvas.drawLine(-half, half, half, -half, strokePaint)
                }
            }
            canvas.restore()
        }

        override fun setAlpha(alpha: Int) = Unit

        override fun setColorFilter(colorFilter: ColorFilter?) = Unit

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    /**
     * One wave's motion, as Telegram's `ChatRecordingBlobMotion`: eight points round the centre at
     * random radii, morphing to a new random shape whenever the last morph ends, faster the louder
     * the voice was meanwhile
     */
    private class BlobMotion {
        private var fromPoints = generateRandomPoints()
        private var toPoints = generateRandomPoints()
        private var duration = 1f
        private var elapsed = 0f
        private var speedLevel = 0f
        private val from = FloatArray(SEGMENT_VALUES * POINT_COUNT)
        private val to = FloatArray(SEGMENT_VALUES * POINT_COUNT)

        init {
            startNextShape()
        }

        // The loudest level since the current shape started decides the next one's speed
        fun updateSpeedLevel(level: Float) {
            speedLevel = max(speedLevel, level)
        }

        fun advance(time: Float) {
            elapsed += time
            while (elapsed >= duration) {
                elapsed -= duration
                fromPoints = toPoints
                startNextShape()
            }
        }

        /** The outline round the origin, [diameter] across at its nominal radius */
        fun buildPath(path: Path, diameter: Float, isStill: Boolean) {
            buildSegments(if (isStill) CIRCLE_POINTS else fromPoints, from)
            if (!isStill) buildSegments(toPoints, to)
            val progress = if (isStill) {
                0f
            } else {
                WInterpolator.easeInOut.getInterpolation((elapsed / duration).coerceIn(0f, 1f))
            }
            fun evaluate(index: Int): Float {
                val start = from[index]
                val end = if (isStill) start else to[index]
                return (start + (end - start) * progress) * diameter
            }
            path.rewind()
            path.moveTo(evaluate(0), evaluate(1))
            for (segment in 0 until POINT_COUNT) {
                val base = segment * SEGMENT_VALUES
                path.cubicTo(
                    evaluate(base + 2),
                    evaluate(base + 3),
                    evaluate(base + 4),
                    evaluate(base + 5),
                    evaluate(base + 6),
                    evaluate(base + 7)
                )
            }
            path.close()
        }

        private fun startNextShape() {
            toPoints = generateRandomPoints()
            duration = 1 / max(MIN_DURATION_SPEED, MIN_SPEED + (MAX_SPEED - MIN_SPEED) * speedLevel)
            speedLevel = 0f
        }

        companion object {
            private const val POINT_COUNT = 8

            // Start, two controls and end of a cubic segment
            private const val SEGMENT_VALUES = 8
            private const val MIN_SPEED = 0.9f
            private const val MAX_SPEED = 4f
            private const val MIN_DURATION_SPEED = 0.05f

            // Each point lies between 1 / (1 + randomness / 10) of the nominal radius and the radius
            private const val RANDOMNESS = 1f
            private val STEP = (2 * PI / POINT_COUNT).toFloat()

            // The handles of a closed curve through evenly placed points: the standard cubic circle
            private val SMOOTHNESS = ((4f / 3f) * tan(STEP / 4)) / sin(STEP / 2) / 2

            private val CIRCLE_POINTS = FloatArray(POINT_COUNT * 2) { index ->
                val angle = STEP * (index / 2)
                if (index % 2 == 0) sin(angle) * 0.5f else cos(angle) * 0.5f
            }

            private fun generateRandomPoints(): FloatArray {
                val rangeStart = 1 / (1 + RANDOMNESS / 10)
                val startAngle = STEP * Random.nextFloat()
                val angleRandomness = STEP * 0.1f
                val points = FloatArray(POINT_COUNT * 2)
                for (index in 0 until POINT_COUNT) {
                    val radius = (rangeStart + Random.nextFloat() * (1 - rangeStart)) / 2
                    val pointAngle = STEP +
                        STEP * (angleRandomness * Random.nextFloat() - angleRandomness * 0.5f)
                    val angle = startAngle + index * pointAngle
                    points[index * 2] = sin(angle) * radius
                    points[index * 2 + 1] = cos(angle) * radius
                }
                return points
            }

            // Each point's handles follow the direction from its previous to its next neighbour
            private fun buildSegments(points: FloatArray, out: FloatArray) {
                for (index in 0 until POINT_COUNT) {
                    val previous = (index + POINT_COUNT - 1) % POINT_COUNT
                    val end = (index + 1) % POINT_COUNT
                    val afterEnd = (index + 2) % POINT_COUNT
                    val startX = points[index * 2]
                    val startY = points[index * 2 + 1]
                    val endX = points[end * 2]
                    val endY = points[end * 2 + 1]
                    val handle = SMOOTHNESS * hypot(endX - startX, endY - startY)
                    val startDirectionX = points[end * 2] - points[previous * 2]
                    val startDirectionY = points[end * 2 + 1] - points[previous * 2 + 1]
                    val startLength =
                        hypot(startDirectionX, startDirectionY).takeIf { it > 0f } ?: 1f
                    val endDirectionX = points[afterEnd * 2] - startX
                    val endDirectionY = points[afterEnd * 2 + 1] - startY
                    val endLength = hypot(endDirectionX, endDirectionY).takeIf { it > 0f } ?: 1f
                    val base = index * SEGMENT_VALUES
                    out[base] = startX
                    out[base + 1] = startY
                    out[base + 2] = startX + startDirectionX / startLength * handle
                    out[base + 3] = startY + startDirectionY / startLength * handle
                    out[base + 4] = endX - endDirectionX / endLength * handle
                    out[base + 5] = endY - endDirectionY / endLength * handle
                    out[base + 6] = endX
                    out[base + 7] = endY
                }
            }
        }
    }

    /** A value that tweens from where it is to a target, then through any legs queued after it */
    private class Tween(initial: Float) {
        private var from = initial
        private var to = initial
        private var startNanos = 0L
        private var durationMs = 0f
        private var interpolator: TimeInterpolator = WInterpolator.easeInOut
        private val legs = ArrayDeque<Leg>()

        private class Leg(
            val to: Float,
            val durationMs: Float,
            val interpolator: TimeInterpolator,
            val delayMs: Float
        )

        fun set(value: Float) {
            from = value
            to = value
            durationMs = 0f
            legs.clear()
        }

        fun animate(
            target: Float,
            now: Long,
            durationMs: Long,
            interpolator: TimeInterpolator,
            delayMs: Long = 0L,
            from: Float = evaluate(now)
        ) {
            legs.clear()
            this.from = from
            to = target
            startNanos = now + (delayMs * NANOS_PER_MS).toLong()
            this.durationMs = durationMs.toFloat()
            this.interpolator = interpolator
        }

        /** Goes on to [target] once the legs before it end, after [delayMs] */
        fun continueTo(
            target: Float,
            durationMs: Long,
            interpolator: TimeInterpolator,
            delayMs: Long = 0L
        ) {
            legs.addLast(Leg(target, durationMs.toFloat(), interpolator, delayMs.toFloat()))
        }

        fun isRunning(now: Long): Boolean {
            evaluate(now)
            return legs.isNotEmpty() || (durationMs > 0f && now < endNanos)
        }

        fun evaluate(now: Long): Float {
            while (legs.isNotEmpty() && now >= endNanos) {
                val legStart = endNanos
                val leg = legs.removeFirst()
                from = to
                to = leg.to
                startNanos = legStart + (leg.delayMs * NANOS_PER_MS).toLong()
                durationMs = leg.durationMs
                interpolator = leg.interpolator
            }
            if (durationMs <= 0f) return to
            val elapsed = (now - startNanos) / NANOS_PER_MS
            if (elapsed <= 0f) return from
            if (elapsed >= durationMs) return to
            return from + (to - from) * interpolator.getInterpolation(elapsed / durationMs)
        }

        private val endNanos: Long
            get() = startNanos + (durationMs * NANOS_PER_MS).toLong()
    }

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000f
        const val NANOS_PER_MS = 1_000_000f
        const val FRAMES_PER_SECOND = 60f
        const val MAX_FRAME_S = 0.05f

        // In dp: a circle a little taller than the field, the waves reaching past it, as on iOS
        const val CENTRE_DIAMETER = 54f
        const val OUTER_WAVE_MIN = 66f
        const val OUTER_WAVE_MAX = 108f
        const val MICROPHONE_GLYPH = 26
        const val CROSS_GLYPH = 18f
        const val CROSS_STROKE = 3.4f

        // The field's buttons are 40 dp across, the stop button's tap target 48 dp
        const val FIELD_BUTTON = 40f
        const val STOP_TARGET = 48

        // The composer's 12 dp Stop with 2.5 dp corners, at the circle's size
        const val STOP_GLYPH = 12f * CENTRE_DIAMETER / FIELD_BUTTON
        const val STOP_GLYPH_RADIUS = 2.5f * CENTRE_DIAMETER / FIELD_BUTTON

        // A hands-free recording's stop is as big as the field's buttons; a failure's circle settles smaller
        const val STOP_SCALE = FIELD_BUTTON / CENTRE_DIAMETER
        const val FAILURE_SCALE = 30f / CENTRE_DIAMETER

        const val OUTER_WAVE_ALPHA = 0.15f
        const val INNER_WAVE_ALPHA = 0.3f
        const val RESTING_PRESENCE = 0.75f
        const val LEVEL_SMOOTHING = 0.9
        const val FOLLOW_SHARE = 0.3f
        const val PRESENT_FROM_SCALE = 0.2f
        const val FAILURE_POP_SCALE = 1.1f
        const val GLYPH_FROM_SCALE = 0.3f
        const val GLYPH_GONE_SCALE = 0.001f

        // The microphone is 40 dp across
        const val FALLBACK_COLLAPSED_SCALE = FIELD_BUTTON / CENTRE_DIAMETER

        const val PRESENCE_IN_MS = 350L
        const val PRESENT_MS = 500L
        const val DISMISS_MS = 180L
        const val WAVES_SWAP_MS = 290L
        const val FAILURE_COLOR_MS = 200L
        const val FAILURE_POP_MS = 120L
        const val FAILURE_SETTLE_MS = 300L
        const val FAILURE_EMERGE_MS = 420L
        const val FAILURE_EMERGE_FADE_MS = 100L
        const val FAILURE_COLLAPSE_MS = 300L
        const val FAILURE_FADE_MS = 160L
        const val FAILURE_FADE_DELAY_MS = 120L
        const val FAILURE_END_MS = 120L
        const val FAILURE_TOTAL_MS = 750f
        const val GLYPH_SWAP_MS = 300f
        const val GLYPH_FADE_MS = 200f

        val TELEGRAM_CURVE = PathInterpolator(0.38f, 0.7f, 0.125f, 1f)
        val EASE_OUT = PathInterpolator(0f, 0f, 0.58f, 1f)
        val EASE_IN = PathInterpolator(0.42f, 0f, 1f, 1f)

        // UIKit's damping-ratio springs, settling within their duration
        val PRESENT_SPRING = createUiKitSpring(0.55f)
        val FAILURE_SETTLE_SPRING = createUiKitSpring(0.55f)
        val FAILURE_EMERGE_SPRING = createUiKitSpring(0.55f)
        val FAILURE_COLLAPSE_SPRING = createUiKitSpring(0.99f)

        fun createUiKitSpring(damping: Float): TimeInterpolator =
            WInterpolator.spring(damping, (ln(SETTLED_DECAY) / damping).toFloat())

        // The spring's envelope has fallen to 0.1% by the end of its duration
        const val SETTLED_DECAY = 1000.0

        fun applyAlpha(color: Int, alpha: Float): Int = ColorUtils.setAlphaComponent(
            color,
            (Color.alpha(color) * alpha).toInt().coerceIn(0, MAX_ALPHA)
        )

        const val MAX_ALPHA = 255
    }
}
