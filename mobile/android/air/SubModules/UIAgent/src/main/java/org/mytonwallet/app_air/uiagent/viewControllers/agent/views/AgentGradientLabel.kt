package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Shader
import android.view.Choreographer
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * Text painted with the Agent gradient, which sweeps along it in the reading direction once every two seconds while
 * it is on screen and animations are on
 */
@SuppressLint("ViewConstructor")
class AgentGradientLabel(context: Context) : WLabel(context) {
    private val gradientMatrix = Matrix()
    private var gradient: LinearGradient? = null
    private var tileWidth = 0f
    private var startTimeNanos = 0L
    private var isFrameScheduled = false
    private var isShownOnScreen = false

    /** Holds the motion still, as while the screen showing it doesn't render */
    var isAnimationPaused = false
        set(value) {
            if (field == value) return
            field = value
            invalidate()
            scheduleFrameIfNeeded()
        }

    private val frameCallback = Choreographer.FrameCallback {
        isFrameScheduled = false
        invalidate()
        scheduleFrameIfNeeded()
    }

    init {
        // The gradient paints over an opaque color
        setTextColor(Color.BLACK)
    }

    override fun onTextChanged(
        text: CharSequence,
        start: Int,
        lengthBefore: Int,
        lengthAfter: Int
    ) {
        super.onTextChanged(text, start, lengthBefore, lengthAfter)
        gradient = null
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        gradient = null
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        isShownOnScreen = isVisible
        scheduleFrameIfNeeded()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        isFrameScheduled = false
    }

    override fun onDraw(canvas: Canvas) {
        val gradient = gradient ?: makeGradient()
        val seconds = if (isMoving) (System.nanoTime() - startTimeNanos) / NANOS_PER_SECOND else 0.0
        val progress = (seconds / SWEEP_PERIOD_S % 1.0).toFloat()
        val direction = if (LocaleController.isRTL) -1f else 1f
        gradientMatrix.setTranslate(direction * progress * tileWidth, 0f)
        gradient.setLocalMatrix(gradientMatrix)
        paint.shader = gradient
        super.onDraw(canvas)
    }

    private fun makeGradient(): LinearGradient {
        val layout = layout
        val textWidth = if (layout != null && layout.lineCount > 0) {
            (0 until layout.lineCount).maxOf { layout.getLineWidth(it) }
        } else {
            width.toFloat()
        }
        // The tile spans two text widths, so the whole text is one sweep of the gradient
        tileWidth = (textWidth * 2).coerceAtLeast(1f)
        return LinearGradient(
            totalPaddingLeft.toFloat(),
            0f,
            totalPaddingLeft + tileWidth,
            0f,
            AGENT_GRADIENT_BAND_COLORS,
            AGENT_GRADIENT_BAND_POSITIONS,
            Shader.TileMode.REPEAT
        ).also { gradient = it }
    }

    private val isMoving: Boolean
        get() = isShownOnScreen && isAttachedToWindow && !isAnimationPaused &&
            WGlobalStorage.getAreAnimationsActive()

    private fun scheduleFrameIfNeeded() {
        if (!isMoving || isFrameScheduled) return
        if (startTimeNanos == 0L) startTimeNanos = System.nanoTime()
        isFrameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000.0
        const val SWEEP_PERIOD_S = 2.0
    }
}
