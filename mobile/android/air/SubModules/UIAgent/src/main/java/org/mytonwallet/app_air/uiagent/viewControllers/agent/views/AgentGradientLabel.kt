package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.view.Choreographer
import kotlin.math.max
import kotlin.math.min
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * Text painted with the Agent gradient, which sweeps along it in the reading direction once every two seconds while
 * it is on screen and animations are on. After [startGlint] a glint of whitish light crosses it once.
 */
@SuppressLint("ViewConstructor")
class AgentGradientLabel(context: Context) : WLabel(context) {
    private val gradientMatrix = Matrix()
    private var gradient: LinearGradient? = null
    private var tileWidth = 0f
    private var startTimeNanos = 0L
    private var isFrameScheduled = false
    private val glint = AgentStatusGlint()
    private val glintMatrix = Matrix()
    private val glintPaint = Paint().apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_ATOP)
    }
    private var glintShader: LinearGradient? = null
    private var glintShaderHeight = 0f
    private var lastFrameNanos = 0L

    // A page of the tabs laid out beside the selected one still counts as visible
    private val onScreenTracker = AgentOnScreenTracker(this) { scheduleFrameIfNeeded() }
    private val isShownOnScreen: Boolean
        get() = onScreenTracker.isOnScreen

    /** Holds the motion still, as while the screen showing it doesn't render */
    var isAnimationPaused = false
        set(value) {
            if (field == value) return
            field = value
            invalidate()
            scheduleFrameIfNeeded()
        }

    private val onSystemAnimationsChanged: () -> Unit = {
        invalidate()
        scheduleFrameIfNeeded()
    }

    private val frameCallback = Choreographer.FrameCallback { frameTimeNanos ->
        isFrameScheduled = false
        val seconds = if (lastFrameNanos == 0L) {
            0f
        } else {
            min(MAX_FRAME_STEP_S, ((frameTimeNanos - lastFrameNanos) / NANOS_PER_SECOND).toFloat())
        }
        lastFrameNanos = frameTimeNanos
        glint.step(seconds)
        invalidate()
        scheduleFrameIfNeeded()
    }

    init {
        // The gradient paints over an opaque color
        setTextColor(Color.BLACK)
    }

    /** Lets a glint of whitish light cross the text once, as its new text comes into focus */
    fun startGlint() {
        // No glint while animations are off, nor in debug builds while system animations are off, to keep E2E runs fast
        if (!WGlobalStorage.getAreAnimationsActive() ||
            !AgentDebugAnimations.areSystemAnimationsOn(context)
        ) {
            return
        }
        glint.start()
        invalidate()
        scheduleFrameIfNeeded()
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
        onScreenTracker.setVisibilityAggregated(isVisible)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        onScreenTracker.attach()
        AgentDebugAnimations.addListener(context, onSystemAnimationsChanged)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        onScreenTracker.detach()
        AgentDebugAnimations.removeListener(context, onSystemAnimationsChanged)
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        isFrameScheduled = false
        lastFrameNanos = 0L
    }

    override fun onDraw(canvas: Canvas) {
        val gradient = gradient ?: makeGradient()
        val seconds = if (isMoving) (System.nanoTime() - startTimeNanos) / NANOS_PER_SECOND else 0.0
        val progress = (seconds / SWEEP_PERIOD_S % 1.0).toFloat()
        val direction = if (LocaleController.isRTL) -1f else 1f
        gradientMatrix.setTranslate(direction * progress * tileWidth, 0f)
        gradient.setLocalMatrix(gradientMatrix)
        paint.shader = gradient
        val glintShader = if (isMoving) obtainGlintShader() else null
        if (glintShader == null) {
            super.onDraw(canvas)
            return
        }
        // The glint lights only the text, over its gradient, slanted as light on a polished surface
        val saveCount = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
        super.onDraw(canvas)
        glintPaint.shader = glintShader
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), glintPaint)
        canvas.restoreToCount(saveCount)
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

    // The glint where it crosses the text now, or null before and after it
    private fun obtainGlintShader(): Shader? {
        val time = glint.time ?: return null
        val layout = layout ?: return null
        if (layout.lineCount == 0) return null
        var textLeft = Float.MAX_VALUE
        var textRight = -Float.MAX_VALUE
        for (line in 0 until layout.lineCount) {
            textLeft = min(textLeft, layout.getLineLeft(line))
            textRight = max(textRight, layout.getLineRight(line))
        }
        val centre = AgentStatusGlint.computeCentre(
            time,
            textRight - textLeft,
            GLINT_HALF_WIDTH.dp,
            LocaleController.isRTL
        ) ?: return null
        val textHeight = layout.height.toFloat()
        val shader = glintShader?.takeIf { glintShaderHeight == textHeight }
            ?: makeGlintShader(textHeight)
        glintMatrix.setTranslate(totalPaddingLeft + textLeft + centre, totalPaddingTop.toFloat())
        shader.setLocalMatrix(glintMatrix)
        return shader
    }

    // The glint across text `height` px tall, from its bottom left to its top right, its middle at x = 0
    private fun makeGlintShader(height: Float): LinearGradient {
        val reach = GLINT_HALF_WIDTH.dp + height * GLINT_SLANT
        return LinearGradient(
            -reach,
            height,
            reach,
            0f,
            GLINT_COLORS,
            GLINT_POSITIONS,
            Shader.TileMode.CLAMP
        ).also {
            glintShader = it
            glintShaderHeight = height
        }
    }

    // Debug builds stop the sweep and glint while system animations are off, to keep E2E runs fast
    private val isMoving: Boolean
        get() = isShownOnScreen && isAttachedToWindow && !isAnimationPaused &&
            WGlobalStorage.getAreAnimationsActive() &&
            AgentDebugAnimations.areSystemAnimationsOn(context)

    private fun scheduleFrameIfNeeded() {
        if (!isMoving) {
            // The glint waits where it is until the text moves again
            lastFrameNanos = 0L
            return
        }
        if (isFrameScheduled) return
        if (startTimeNanos == 0L) startTimeNanos = System.nanoTime()
        isFrameScheduled = true
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    private companion object {
        const val NANOS_PER_SECOND = 1_000_000_000.0
        const val SWEEP_PERIOD_S = 2.0
        const val MAX_FRAME_STEP_S = 0.05f

        // Half the glint's width across, in dp, and how far it leans, for each px of the text's height
        const val GLINT_HALF_WIDTH = 16f
        const val GLINT_SLANT = 0.35f

        // White, at 0.4 in its middle: a soft light rather than a white streak
        val GLINT_COLORS = intArrayOf(0x00FFFFFF, 0x66FFFFFF, 0x00FFFFFF)
        val GLINT_POSITIONS = floatArrayOf(0f, 0.5f, 1f)
    }
}

/**
 * The glint of whitish light that crosses the Agent's status once each time the status changes, as light runs over
 * metal, as iOS's `AgentGradientLabel` passes it: it starts 0.3 s after the change, as the new text comes into focus,
 * and takes 0.75 s. Its time moves on only with the frames the text is drawn in.
 */
internal class AgentStatusGlint {
    /** Seconds into the glint, negative while it waits for the new text, or null once it has passed */
    var time: Float? = null
        private set

    fun start() {
        time = -DELAY_S
    }

    /** Moves the glint on by [seconds] */
    fun step(seconds: Float) {
        val next = (time ?: return) + seconds
        time = if (next > DURATION_S) null else next
    }

    companion object {
        const val DELAY_S = 0.3f
        const val DURATION_S = 0.75f

        /**
         * Where the glint's middle crosses text [width] px wide [time] seconds into the glint, from the text's left,
         * or null before or after it. It runs in the reading direction, eased, from [halfWidth] twice before the text
         * to as far past it.
         */
        fun computeCentre(
            time: Float,
            width: Float,
            halfWidth: Float,
            isRightToLeft: Boolean
        ): Float? {
            val progress = time / DURATION_S
            if (progress < 0f || progress > 1f) return null
            val eased = progress * progress * (3f - 2f * progress)
            val travel = width + 4f * halfWidth
            val distance = -2f * halfWidth + eased * travel
            return if (isRightToLeft) width - distance else distance
        }
    }
}
