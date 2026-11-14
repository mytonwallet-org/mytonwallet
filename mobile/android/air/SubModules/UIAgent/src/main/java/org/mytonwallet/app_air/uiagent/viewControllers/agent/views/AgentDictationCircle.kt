package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.TimeInterpolator
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.view.Choreographer
import android.view.View
import android.view.ViewGroup
import android.view.animation.PathInterpolator
import androidx.core.content.ContextCompat
import androidx.core.graphics.ColorUtils
import kotlin.math.PI
import kotlin.math.abs
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

// The finger's travel up over which the lock closes, in dp
private const val LOCK_TRAVEL = 105f

// The open shackle stands this far above the body, its short leg this much further, in dp
private const val SHACKLE_LIFT = 3f
private const val SHACKLE_LEG_GAP = 3f

/** How far the finger has slid toward the lock, from 0 where it pressed to 1 at the lock, for [upDp] of travel up */
internal fun agentDictationLockProgress(upDp: Float): Float = (upDp / LOCK_TRAVEL).coerceIn(0f, 1f)

/** Where the padlock's shackle stands: how far above the body, and how far its short leg stops short of it, in dp */
internal data class AgentLockShackle(val lift: Float, val legGap: Float)

/**
 * Telegram's lock closing as the finger slides up: the shackle comes down in proportion to [closing], from open at 0
 * to shut at 1, where its short leg reaches into the body
 */
internal fun agentLockShackle(closing: Float): AgentLockShackle {
    val openness = 1 - closing.coerceIn(0f, 1f)
    return AgentLockShackle(
        lift = SHACKLE_LIFT * openness,
        legGap = (SHACKLE_LIFT + SHACKLE_LEG_GAP) * openness
    )
}

/**
 * Telegram's recording circle, grown out of the microphone while a question is recorded: a solid
 * accent circle with the microphone, or a checkmark once locked, inside two voice waves that swell
 * with the voice, and the lock panel above it. It follows the finger up and toward cancelling,
 * shrinking as it goes. Once locked, the panel turns into Telegram Android's pause button, which
 * shows the microphone while the recording is paused. A recording that produced no transcript turns
 * it red with a cross before it shrinks back into the microphone.
 *
 * It draws in [anchor]'s window overlay, centred on [anchor], so nothing clips it, and takes no
 * touches but the pause button's: the microphone under its centre finishes a locked recording.
 */
internal class AgentDictationCircle(private val anchor: View) {
    /** The circle shows or has gone */
    var onVisibilityChanged: ((Boolean) -> Unit)? = null

    /** The pause button is tapped, to pause the recording or resume it */
    var onPauseToggled: (() -> Unit)? = null

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
    private var isPaused = false
    private var isPresented = false
    private var isShowingFailure = false
    private var lastFrameNanos = 0L

    // Where the finger has taken the circle: up, and toward cancelling, in px
    private var targetTranslationY = 0f
    private var targetCancelX = 0f
    private var currentTranslationY = 0f
    private var currentCancelX = 0f
    private var currentScale = 1f

    private val blobScale = Tween(1f)
    private val blobAlpha = Tween(1f)
    private val panelOffset = Tween(0f)
    private val panelAlpha = Tween(1f)
    private val lockClose = Tween(0f)
    private val pauseMorph = Tween(0f)
    private val resumeMorph = Tween(0f)
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
    private var panelColor = WColor.Background.color
    private var iconColor = WColor.SecondaryText.color

    // The overlay takes no touches, so the pause button's own tap target lies over it in the window
    private val pauseButton = View(anchor.context).apply {
        isClickable = true
        isFocusable = true
        contentDescription = LocaleController.getString("\$agent_voice_pause")
        setOnClickListener { onPauseToggled?.invoke() }
    }

    private val isAnimated: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() && anchor.isAttachedToWindow

    fun update(state: AgentDictationState) {
        val previousPhase = phase
        phase = state.phase
        val hasBeenLocked = isLocked
        isLocked = state.locked
        level = state.waveLevel
        outerMotion.updateSpeedLevel(level)
        innerMotion.updateSpeedLevel(level)
        val sign = if (LocaleController.isRTL) 1f else -1f
        if (state.phase == AgentDictationPhase.RECORDING && !state.locked) {
            targetTranslationY = -state.lockDragDp.dp
            targetCancelX = sign * max(0f, state.cancelDragDp).dp
        } else {
            targetTranslationY = 0f
            targetCancelX = 0f
        }
        val isRecording = state.phase == AgentDictationPhase.RECORDING
        if (previousPhase != state.phase && state.phase == AgentDictationPhase.FAILED) {
            showFailure()
            return
        }
        if (isRecording && state.locked && !hasBeenLocked && isPresented) {
            lockPanel(shouldAnimate = isAnimated)
        }
        val shouldPause = isRecording && state.isPaused
        if (shouldPause != isPaused) {
            isPaused = shouldPause
            if (isRecording && isPresented) showPause(shouldAnimate = isAnimated)
            pauseButton.contentDescription = LocaleController.getString(
                if (shouldPause) "\$agent_voice_resume" else "\$agent_voice_pause"
            )
        }
        if (isRecording) setGlyph(resolveGlyph(state), shouldAnimate = isPresented && isAnimated)
        when {
            isRecording && !isPresented -> present()
            !isRecording && isPresented -> dismiss()
            state.phase == AgentDictationPhase.IDLE && isShowingFailure -> endFailureEarly()
        }
    }

    fun updateTheme() {
        tint = WColor.Tint.color
        onTintColor = WColor.TextOnTint.color
        error = WColor.Error.color
        panelColor = WColor.Background.color
        iconColor = WColor.SecondaryText.color
        layer.updateTheme()
        layer.invalidateSelf()
    }

    fun detach() {
        isPresented = false
        isShowingFailure = false
        hide()
    }

    private fun resolveGlyph(state: AgentDictationState) =
        if (state.locked) Glyph.CHECKMARK else Glyph.MICROPHONE

    private fun present() {
        isPresented = true
        isShowingFailure = false
        currentTranslationY = 0f
        currentCancelX = 0f
        currentScale = 1f
        failureColor.set(0f)
        wavesAlpha.set(1f)
        wavesShown.set(1f)
        blobAlpha.set(1f)
        setGlyph(resolveGlyph(), shouldAnimate = false)
        // A hands-free recording starts locked, with the pause button
        lockClose.set(if (isLocked) 1f else 0f)
        pauseMorph.set(if (isLocked) 1f else 0f)
        resumeMorph.set(0f)
        presentationLevel = 0f
        lastFrameNanos = 0L
        show()
        val now = System.nanoTime()
        if (!isAnimated) {
            presence.set(1f)
            blobScale.set(1f)
            panelOffset.set(0f)
            panelAlpha.set(1f)
            updateCover(now)
            return
        }
        presence.set(RESTING_PRESENCE)
        presence.animate(1f, now, PRESENCE_IN_MS, WInterpolator.easeInOut)
        // As in Telegram, the circle and its waves grow out of the microphone at once
        blobScale.set(PRESENT_FROM_SCALE)
        blobScale.animate(1f, now, PRESENT_MS, PRESENT_SPRING)
        panelOffset.set((if (isLocked) PANEL_LOCKED_RISE else PANEL_RISE).dp.toFloat())
        panelOffset.animate(0f, now, PRESENT_MS, PRESENT_SPRING)
        panelAlpha.set(0f)
        panelAlpha.animate(1f, now, PANEL_FADE_MS, WInterpolator.easeInOut)
        updateCover(now)
    }

    private fun updateCover(now: Long) {
        val value = when {
            host == null -> 0f

            isPresented -> {
                val diameter = blobScale.evaluate(now) * CENTRE_DIAMETER.dp
                (diameter / anchor.width.coerceAtLeast(1)).coerceIn(0f, 1f)
            }

            else -> blobAlpha.evaluate(now).coerceIn(0f, 1f)
        }
        if (value == cover) return
        cover = value
        onCoverChanged?.invoke(value)
    }

    private fun resolveGlyph() = if (isLocked) Glyph.CHECKMARK else Glyph.MICROPHONE

    private fun dismiss() {
        isPresented = false
        if (!isAnimated) {
            hide()
            return
        }
        val now = System.nanoTime()
        blobScale.animate(PRESENT_FROM_SCALE, now, DISMISS_MS, WInterpolator.easeInOut)
        blobAlpha.animate(0f, now, DISMISS_MS, WInterpolator.easeInOut)
        panelOffset.animate(PANEL_RISE.dp.toFloat(), now, DISMISS_MS, WInterpolator.easeInOut)
        panelAlpha.animate(0f, now, DISMISS_MS, WInterpolator.easeInOut)
        scheduleFrame()
    }

    // Once locked, the panel closes from where the finger left it as its padlock turns into
    // Telegram Android's pause button
    private fun lockPanel(shouldAnimate: Boolean) {
        val dragLockness = agentDictationLockProgress(abs(currentTranslationY) / 1f.dp)
        if (!shouldAnimate) {
            lockClose.set(1f)
            pauseMorph.set(1f)
            panelOffset.set(0f)
            return
        }
        val now = System.nanoTime()
        lockClose.set(dragLockness)
        lockClose.animate(1f, now, PANEL_CLOSE_MS, WInterpolator.easeInOut, PANEL_CLOSE_DELAY_MS)
        pauseMorph.animate(1f, now, PANEL_CLOSE_MS, WInterpolator.easeInOut, PANEL_CLOSE_DELAY_MS)
        // The panel followed the finger up; it settles back from there
        panelOffset.set(currentTranslationY)
        panelOffset.animate(0f, now, PANEL_CLOSE_MS, WInterpolator.easeInOut)
    }

    // Paused, the waves sink into the circle and the pause button shows the microphone that resumes, as in Telegram
    private fun showPause(shouldAnimate: Boolean) {
        val target = if (isPaused) 1f else 0f
        if (!shouldAnimate) {
            resumeMorph.set(target)
            wavesShown.set(1f - target)
            return
        }
        val now = System.nanoTime()
        resumeMorph.animate(target, now, PAUSE_SWAP_MS, WInterpolator.easeInOut)
        wavesShown.animate(1f - target, now, PAUSE_SWAP_MS, WInterpolator.easeInOut)
    }

    /**
     * The circle settles at rest, or pops back out of the microphone after recognition, turns red as
     * its waves go and shows a cross, then shrinks onto the microphone and fades into it, within the
     * controller's failure phase
     */
    private fun showFailure() {
        hasFailureBeenPresented = isPresented
        isPresented = false
        isShowingFailure = true
        val now = System.nanoTime()
        failureStartNanos = now
        show()
        panelOffset.animate(PANEL_RISE.dp.toFloat(), now, DISMISS_MS, WInterpolator.easeInOut)
        panelAlpha.animate(0f, now, DISMISS_MS, WInterpolator.easeInOut)
        if (hasFailureBeenPresented && isAnimated) {
            failureColor.animate(1f, now, FAILURE_COLOR_MS, WInterpolator.easeInOut)
            wavesAlpha.animate(0f, now, FAILURE_COLOR_MS, WInterpolator.easeInOut)
        } else {
            failureColor.set(1f)
            wavesAlpha.set(0f)
        }
        setGlyph(Glyph.CROSS, shouldAnimate = hasFailureBeenPresented && isAnimated)
        if (!isAnimated) {
            blobScale.set(1f)
            blobAlpha.set(1f)
            return
        }
        if (hasFailureBeenPresented) {
            blobScale.animate(FAILURE_POP_SCALE, now, FAILURE_POP_MS, EASE_OUT)
            blobScale.continueTo(1f, FAILURE_SETTLE_MS, FAILURE_SETTLE_SPRING)
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
            blobScale.animate(1f, now, FAILURE_EMERGE_MS, FAILURE_EMERGE_SPRING)
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
            onVisibilityChanged?.invoke(true)
        }
        scheduleFrame()
    }

    private fun hide() {
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        isFrameScheduled = false
        removePauseButton()
        val root = host ?: return
        host = null
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
            // Telegram's smoothing: each frame closes 30% of the remaining distance to the finger
            currentTranslationY = min(
                0f,
                currentTranslationY * (1 - FOLLOW_SHARE) + targetTranslationY * FOLLOW_SHARE
            )
            currentCancelX = currentCancelX * (1 - FOLLOW_SHARE) + targetCancelX * FOLLOW_SHARE
            val cancelProgress = (abs(currentCancelX) / CANCEL_SCALE_TRAVEL.dp).coerceIn(0f, 1f)
            currentScale = max(MIN_CANCEL_SCALE, 1 - cancelProgress)
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
        updatePauseButton(now)
        val isFinishedDismissing = !isPresented && !isShowingFailure && !blobAlpha.isRunning(now)
        val isFinishedFailure = isShowingFailure &&
            (now - failureStartNanos) / NANOS_PER_MS > FAILURE_TOTAL_MS && !blobAlpha.isRunning(now)
        when {
            isFinishedDismissing -> hide()

            isFinishedFailure -> {
                isShowingFailure = false
                hide()
            }

            else -> scheduleFrame()
        }
    }

    // The tap target follows the locked panel while it shows as the pause button
    private fun updatePauseButton(now: Long) {
        val root = host as? ViewGroup
        if (root == null || !isPresented || !isLocked || anchor.width <= 0) {
            removePauseButton()
            return
        }
        val size = PAUSE_TARGET.dp
        if (pauseButton.parent !== root) {
            removePauseButton()
            root.addView(pauseButton, ViewGroup.LayoutParams(size, size))
        }
        anchor.getLocationInWindow(location)
        val centreX = location[0] + anchor.width / 2f
        val centreY = location[1] + anchor.height / 2f - LOCK_PANEL_OFFSET.dp +
            panelOffset.evaluate(now) + LOCKED_PANEL_CENTRE.dp
        pauseButton.translationX = centreX - size / 2f
        pauseButton.translationY = centreY - size / 2f
    }

    private fun removePauseButton() {
        (pauseButton.parent as? ViewGroup)?.removeView(pauseButton)
    }

    private enum class Glyph { MICROPHONE, CHECKMARK, CROSS }

    private inner class CircleLayer : Drawable() {
        private val wavePaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val centrePaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val panelPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val outerPath = Path()
        private val innerPath = Path()
        private val glyphPath = Path()
        private val rect = RectF()
        private val leftBarRadii = FloatArray(CORNER_VALUES)
        private val rightBarRadii = FloatArray(CORNER_VALUES)

        // On the accent, in the colour of text on it, made once the circle's colours are set. Its
        // alpha follows the glyph's.
        private val microphone by lazy {
            ContextCompat.getDrawable(anchor.context, R.drawable.ic_agent_microphone)
                ?.mutate()
                ?.apply { setTint(onTintColor) }
        }

        // The pause button's microphone, which resumes the recording; made once the circle's colours are set
        private val resumeMicrophone by lazy {
            ContextCompat.getDrawable(anchor.context, R.drawable.ic_agent_microphone)
                ?.mutate()
                ?.apply { setTint(iconColor) }
        }

        fun updateTheme() {
            microphone?.setTint(onTintColor)
            resumeMicrophone?.setTint(iconColor)
        }

        override fun draw(canvas: Canvas) {
            if (anchor.width <= 0) return
            val now = System.nanoTime()
            anchor.getLocationInWindow(location)
            val restingX = location[0] + anchor.width / 2f
            val restingY = location[1] + anchor.height / 2f
            // Locked, the panel is a button over the waves
            if (!isLocked) drawLockPanel(canvas, restingX, restingY, now)
            drawBlob(canvas, restingX + currentCancelX, restingY + currentTranslationY, now)
            if (isLocked) drawLockPanel(canvas, restingX, restingY, now)
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

                Glyph.CHECKMARK -> {
                    val unit = CHECKMARK_GLYPH.dp
                    glyphPath.rewind()
                    glyphPath.moveTo(-0.36f * unit, 0.02f * unit)
                    glyphPath.lineTo(-0.11f * unit, 0.26f * unit)
                    glyphPath.lineTo(0.38f * unit, -0.26f * unit)
                    strokePaint.strokeWidth = GLYPH_STROKE.dp
                    strokePaint.color = applyAlpha(onTintColor, alpha)
                    canvas.drawPath(glyphPath, strokePaint)
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

        // Telegram's lock panel: a capsule with an open padlock and an arrow that closes as the
        // finger slides up, then the pause button
        private fun drawLockPanel(canvas: Canvas, centreX: Float, restingY: Float, now: Long) {
            val alpha = panelAlpha.evaluate(now).coerceIn(0f, 1f)
            if (alpha <= 0f) return
            val lockness = if (isLocked) {
                lockClose.evaluate(now).coerceIn(0f, 1f)
            } else {
                agentDictationLockProgress(abs(currentTranslationY) / 1f.dp)
            }
            val follow = if (isLocked || !isPresented) 0f else currentTranslationY
            val width = LOCK_PANEL_WIDTH.dp.toFloat()
            val fullHeight = LOCK_PANEL_HEIGHT.dp.toFloat()
            val height = fullHeight - (fullHeight - LOCKED_PANEL_HEIGHT.dp) * lockness
            val panelCentreY = restingY - LOCK_PANEL_OFFSET.dp + panelOffset.evaluate(now) + follow
            canvas.save()
            canvas.translate(centreX, panelCentreY)
            val top = -fullHeight / 2 + (fullHeight - height)
            rect.set(-width / 2, top, width / 2, fullHeight / 2)
            panelPaint.color = applyAlpha(panelColor, alpha)
            panelPaint.setShadowLayer(
                PANEL_SHADOW_RADIUS.dp,
                0f,
                PANEL_SHADOW_Y.dp,
                applyAlpha(Color.BLACK, PANEL_SHADOW_ALPHA * alpha)
            )
            canvas.drawRoundRect(rect, width / 2, width / 2, panelPaint)
            val resume = resumeMorph.evaluate(now).coerceIn(0f, 1f)
            val glyphCentreY = top + height / 2
            drawPadlock(
                canvas,
                top + PADLOCK_TOP.dp,
                glyphCentreY,
                lockness,
                pauseMorph.evaluate(now).coerceIn(0f, 1f),
                alpha * (1 - resume)
            )
            drawResumeGlyph(canvas, glyphCentreY, alpha * resume)
            val arrowAlpha = alpha * (1 - lockness)
            if (arrowAlpha > 0f) {
                val arrowY = -fullHeight / 2 + (ARROW_TOP - ARROW_TRAVEL * lockness).dp +
                    ARROW_BOX.dp / 2
                glyphPath.rewind()
                glyphPath.moveTo(-ARROW_HALF_WIDTH.dp, arrowY + ARROW_HALF_HEIGHT.dp)
                glyphPath.lineTo(0f, arrowY - ARROW_HALF_HEIGHT.dp)
                glyphPath.lineTo(ARROW_HALF_WIDTH.dp, arrowY + ARROW_HALF_HEIGHT.dp)
                strokePaint.strokeWidth = ICON_STROKE.dp
                strokePaint.color = applyAlpha(iconColor, arrowAlpha)
                canvas.drawPath(glyphPath, strokePaint)
            }
            canvas.restore()
        }

        /**
         * A padlock whose shackle closes as [closing] goes to 1, as the finger slides up to the lock and
         * then as it locks, and Telegram Android's pause as [pause] goes to 1: the shackle sinks into
         * the body as the body parts into two bars centred on [pauseCentreY]. [top] is the padlock's
         * box's top.
         */
        private fun drawPadlock(
            canvas: Canvas,
            top: Float,
            pauseCentreY: Float,
            closing: Float,
            pause: Float,
            alpha: Float
        ) {
            if (alpha <= 0f) return
            val unit = 1f.dp
            val bodyTop = top + PADLOCK_BOX / 2 * unit
            val shackleAlpha = alpha * (1 - pause)
            if (shackleAlpha > 0f) {
                strokePaint.strokeWidth = ICON_STROKE.dp
                strokePaint.color = applyAlpha(iconColor, shackleAlpha)
                val shackle = agentLockShackle(closing)
                val lift = shackle.lift * unit
                val shackleBottom = bodyTop + SHACKLE_SINK * unit * pause
                glyphPath.rewind()
                glyphPath.moveTo(-4 * unit, shackleBottom)
                glyphPath.lineTo(-4 * unit, shackleBottom - 3 * unit - lift)
                rect.set(
                    -4 * unit,
                    shackleBottom - 7 * unit - lift,
                    4 * unit,
                    shackleBottom + unit - lift
                )
                glyphPath.arcTo(rect, 180f, 180f)
                glyphPath.lineTo(4 * unit, shackleBottom - shackle.legGap * unit)
                canvas.drawPath(glyphPath, strokePaint)
            }
            fillPaint.color = applyAlpha(iconColor, alpha)
            // The body is as wide as the pause
            val halfWidth = PAUSE_GLYPH / 2 * unit
            val bodyBottom = bodyTop + PADLOCK_BODY_HEIGHT * unit
            val barTop = bodyTop + (pauseCentreY - halfWidth - bodyTop) * pause
            val barBottom = bodyBottom + (pauseCentreY + halfWidth - bodyBottom) * pause
            val outerRadius = (PADLOCK_RADIUS + (PAUSE_RADIUS - PADLOCK_RADIUS) * pause) * unit
            if (pause <= 0f) {
                rect.set(-halfWidth, barTop, halfWidth, barBottom)
                canvas.drawRoundRect(rect, outerRadius, outerRadius, fillPaint)
                return
            }
            val innerRadius = PAUSE_RADIUS * unit * pause
            val halfGap = PAUSE_GAP / 2 * unit * pause
            setBarRadii(leftBarRadii, start = outerRadius, end = innerRadius)
            setBarRadii(rightBarRadii, start = innerRadius, end = outerRadius)
            glyphPath.rewind()
            rect.set(-halfWidth, barTop, -halfGap, barBottom)
            glyphPath.addRoundRect(rect, leftBarRadii, Path.Direction.CW)
            rect.set(halfGap, barTop, halfWidth, barBottom)
            glyphPath.addRoundRect(rect, rightBarRadii, Path.Direction.CW)
            canvas.drawPath(glyphPath, fillPaint)
        }

        // Top-left, top-right, bottom-right and bottom-left corners, each as x and y
        private fun setBarRadii(radii: FloatArray, start: Float, end: Float) {
            radii.fill(start)
            radii.fill(end, fromIndex = 2, toIndex = 6)
        }

        private fun drawResumeGlyph(canvas: Canvas, centreY: Float, alpha: Float) {
            val icon = resumeMicrophone ?: return
            if (alpha <= 0f) return
            val half = RESUME_GLYPH.dp / 2
            val top = (centreY - half).roundToInt()
            icon.setBounds(-half, top, half, top + 2 * half)
            icon.alpha = (255 * alpha).roundToInt()
            icon.draw(canvas)
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

        // In dp
        const val CENTRE_DIAMETER = 99f
        const val OUTER_WAVE_MIN = 138f
        const val OUTER_WAVE_MAX = 259f
        const val MICROPHONE_GLYPH = 34
        const val CHECKMARK_GLYPH = 28f
        const val GLYPH_STROKE = 3.2f
        const val CROSS_GLYPH = 18f
        const val CROSS_STROKE = 3.4f
        const val LOCK_PANEL_WIDTH = 40
        const val LOCK_PANEL_HEIGHT = 72
        const val LOCKED_PANEL_HEIGHT = 40
        const val LOCK_PANEL_OFFSET = 122
        const val PANEL_RISE = 100
        const val PANEL_LOCKED_RISE = 36
        const val PANEL_SHADOW_RADIUS = 6f
        const val PANEL_SHADOW_Y = 1f
        const val PANEL_SHADOW_ALPHA = 0.12f
        const val PADLOCK_TOP = 4f
        const val PADLOCK_BOX = 16f
        const val PADLOCK_BODY_HEIGHT = 10f
        const val PADLOCK_RADIUS = 2.5f
        const val SHACKLE_SINK = 7f

        // Telegram Android's pause: two bars in a 12 dp square, 3.32 dp apart
        const val PAUSE_GLYPH = 12f
        const val PAUSE_GAP = 3.32f
        const val PAUSE_RADIUS = 1.5f
        const val RESUME_GLYPH = 22
        const val PAUSE_TARGET = 48

        // The locked panel's centre below the full panel's
        const val LOCKED_PANEL_CENTRE = (LOCK_PANEL_HEIGHT - LOCKED_PANEL_HEIGHT) / 2
        const val ARROW_TOP = 48f
        const val ARROW_TRAVEL = 39f
        const val ARROW_BOX = 16f
        const val ARROW_HALF_WIDTH = 4f
        const val ARROW_HALF_HEIGHT = 2f
        const val ICON_STROKE = 2f
        const val CANCEL_SCALE_TRAVEL = 300f

        const val OUTER_WAVE_ALPHA = 0.15f
        const val INNER_WAVE_ALPHA = 0.3f
        const val RESTING_PRESENCE = 0.75f
        const val LEVEL_SMOOTHING = 0.9
        const val FOLLOW_SHARE = 0.3f
        const val MIN_CANCEL_SCALE = 0.4f
        const val PRESENT_FROM_SCALE = 0.2f
        const val FAILURE_POP_SCALE = 1.1f
        const val GLYPH_FROM_SCALE = 0.3f
        const val GLYPH_GONE_SCALE = 0.001f

        // The microphone is 40 dp across
        const val FALLBACK_COLLAPSED_SCALE = 40f / 99f

        const val PRESENCE_IN_MS = 350L
        const val PRESENT_MS = 500L
        const val PANEL_FADE_MS = 100L
        const val DISMISS_MS = 180L
        const val PANEL_CLOSE_MS = 250L
        const val PANEL_CLOSE_DELAY_MS = 100L

        // Telegram's microphone fades into the paused panel over the first half of its 580 ms
        const val PAUSE_SWAP_MS = 290L
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
        const val CORNER_VALUES = 8
    }
}
