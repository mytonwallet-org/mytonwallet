package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import android.view.Choreographer
import android.view.View
import androidx.annotation.RequiresApi
import androidx.core.graphics.ColorUtils
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * A hands-free recording's voice inside the text field, as on iOS: a thread of light the voice spins out of the stop
 * button, whose strands braid and glint on their crests. It runs frames only while it shows
 * on screen; with animations off it runs none, shows and goes at once and only its brightness follows the voice.
 * Android 13 and later draw it with the iOS shader; earlier versions draw its strands as lines.
 */
internal class AgentVoiceRibbonView(context: Context) :
    View(context),
    Choreographer.FrameCallback {
    private val model = AgentVoiceRibbonModel()
    private val renderer: Renderer = createRenderer()
    private val onScreen = AgentOnScreenTracker(this) { updatePlayback() }
    private var rawLevel = 0f
    private var lastFrameNanos = 0L
    private var isFrameScheduled = false
    private var tint = WColor.Tint.color
    private var palette = makeAgentVoiceRibbonPalette(tint, ThemeManager.isDark, model.parameters)

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        visibility = INVISIBLE
    }

    /** From the view's leading edge to the stop button's centre, which the thread comes out of, in px */
    var stopCenter: Float = 0f
        set(value) {
            field = value
            model.stopCenter = value / resources.displayMetrics.density
            invalidate()
        }

    /** Spins the thread out of the stop button */
    fun start() {
        model.start()
        updatePlayback()
    }

    /** Gathers the thread back into the stop button, as the recording goes to be recognized */
    fun stop() {
        model.stop()
        updatePlayback()
    }

    /** Drains the thread of colour as it fades */
    fun cancel() {
        model.cancel()
        updatePlayback()
    }

    /** Slides the thread into Send */
    fun send() {
        model.send()
        updatePlayback()
    }

    /** The voice's peak since the last frame, from 0 to 1 */
    fun setLevel(level: Float) {
        rawLevel = level.coerceIn(0f, 1f)
        if (!isMoving) settle()
    }

    fun updateTheme() {
        tint = WColor.Tint.color
        palette = makeAgentVoiceRibbonPalette(tint, ThemeManager.isDark, model.parameters)
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        onScreen.attach()
    }

    override fun onDetachedFromWindow() {
        onScreen.detach()
        super.onDetachedFromWindow()
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        onScreen.setVisibilityAggregated(isVisible)
    }

    // With animations off, the thread holds still and only its brightness follows the voice
    private val isMoving: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled())

    private fun updatePlayback() {
        model.isReduceMotion = !isMoving
        if (!isMoving) settle()
        visibility = if (model.isFinished) INVISIBLE else VISIBLE
        if (model.isFinished || !onScreen.isOnScreen || !isMoving) {
            Choreographer.getInstance().removeFrameCallback(this)
            isFrameScheduled = false
            lastFrameNanos = 0L
            return
        }
        if (!isFrameScheduled) {
            isFrameScheduled = true
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    // Without frames the levels and the transitions take their latest values at once
    private fun settle() {
        model.step(SETTLED_DELTA_TIME, rawLevel)
        invalidate()
    }

    override fun doFrame(frameTimeNanos: Long) {
        isFrameScheduled = false
        model.isReduceMotion = !isMoving
        // A frame after a pause takes no more than a frame's time, so the thread doesn't jump ahead
        val deltaTime = if (lastFrameNanos == 0L) {
            0f
        } else {
            min((frameTimeNanos - lastFrameNanos) / NANOS_PER_SECOND, SETTLED_DELTA_TIME)
        }
        lastFrameNanos = frameTimeNanos
        model.step(deltaTime, rawLevel)
        invalidate()
        updatePlayback()
    }

    override fun onDraw(canvas: Canvas) {
        if (model.isFinished || width == 0 || height == 0) return
        renderer.draw(canvas, this)
    }

    private interface Renderer {
        fun draw(canvas: Canvas, view: AgentVoiceRibbonView)
    }

    private fun createRenderer(): Renderer {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                return ShaderRenderer()
            } catch (_: IllegalArgumentException) {
                // The device can't build the shader
            }
        }
        return LineRenderer()
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private class ShaderRenderer : Renderer {
        private val shader = RuntimeShader(AGENT_VOICE_RIBBON_SHADER)
        private val paint = Paint().apply { shader = this@ShaderRenderer.shader }
        private val sections = FloatArray(MAX_SECTION_COUNT * 4)
        private val pixels = IntArray(MAX_SECTION_COUNT * 2)
        private val bitmap = Bitmap.createBitmap(MAX_SECTION_COUNT, 2, Bitmap.Config.ARGB_8888)

        init {
            val bitmapShader = BitmapShader(bitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            bitmapShader.filterMode = BitmapShader.FILTER_MODE_NEAREST
            shader.setInputShader("sections", bitmapShader)
        }

        override fun draw(canvas: Canvas, view: AgentVoiceRibbonView) {
            val model = view.model
            val parameters = model.parameters
            val density = view.resources.displayMetrics.density
            val start = model.farEnd - SECTION_MARGIN
            val count = min(
                ceil((model.stopCenterX + SECTION_MARGIN - start) / SECTION_SPACING).toInt() + 2,
                MAX_SECTION_COUNT
            )
            model.fillSections(sections, start, SECTION_SPACING, count)
            for (index in 0 until count) {
                val center = encodeWide((sections[index * 4] + 32) / 64)
                val radius = encodeWide(sections[index * 4 + 1] / 64)
                val level = (sections[index * 4 + 2].coerceIn(0f, 1f) * 255).roundToInt()
                val opacity = (sections[index * 4 + 3].coerceIn(0f, 1f) * 255).roundToInt()
                pixels[index] = Color.argb(255, center shr 8, center and 0xFF, level)
                pixels[MAX_SECTION_COUNT + index] =
                    Color.argb(255, radius shr 8, radius and 0xFF, opacity)
            }
            bitmap.setPixels(pixels, 0, MAX_SECTION_COUNT, 0, 0, MAX_SECTION_COUNT, 2)
            val transition = model.transition
            val palette = view.palette
            val isDark = ThemeManager.isDark
            val isRightToLeft = LocaleController.isRTL
            shader.setFloatUniform(
                "canvas",
                view.width / density,
                view.height / density,
                density,
                if (isRightToLeft) 1f else 0f
            )
            shader.setFloatUniform(
                "span",
                model.farEnd,
                model.farEnd + parameters.fadeLength,
                model.stopCenterX,
                AgentVoiceRibbonModel.VIEW_ORIGIN
            )
            shader.setFloatUniform("sectionGrid", start, SECTION_SPACING, count.toFloat(), 0f)
            shader.setFloatUniform(
                "clocks",
                model.braidPhase,
                model.silkPhase,
                model.bendPhase,
                model.breathTime
            )
            val reduceMotion = if (model.isReduceMotion) 1f else 0f
            shader.setFloatUniform("levels", model.fastLevel, model.slowLevel, reduceMotion, 0f)
            shader.setFloatUniform(
                "transition",
                0f,
                transition.opacity,
                transition.slide,
                model.desaturation
            )
            shader.setFloatUniform(
                "braid",
                parameters.strandCount.coerceIn(1, 3).toFloat(),
                parameters.braidTwist,
                parameters.braidIrregularity,
                parameters.strandSpread
            )
            shader.setFloatUniform("radius", 0f, 0f, parameters.heightLimit, 0f)
            shader.setFloatUniform(
                "strand",
                parameters.strandWidthAtRest,
                parameters.strandWidthGrowth,
                parameters.silkTwist,
                parameters.farStrandBrightness
            )
            shader.setFloatUniform("bend", 0f, 0f, parameters.breath, 0f)
            shader.setFloatUniform("flare", parameters.curl, parameters.flareLength)
            shader.setFloatUniform(
                "light",
                parameters.coreBrightness,
                parameters.coreWidth,
                parameters.glowWidth,
                parameters.glowStrength
            )
            shader.setFloatUniform(
                "specular",
                parameters.glint,
                parameters.whitening,
                if (isDark) 1f else 0f
            )
            setColorUniform("deepColor", palette.deep)
            setColorUniform("coreColor", palette.core)
            setColorUniform("glowColor", palette.glow)
            setColorUniform("hotColor", palette.hot)
            canvas.drawRect(0f, 0f, view.width.toFloat(), view.height.toFloat(), paint)
        }

        private fun setColorUniform(name: String, color: Int) {
            val red = Color.red(color) / 255f
            val green = Color.green(color) / 255f
            shader.setFloatUniform(name, red, green, Color.blue(color) / 255f, 1f)
        }

        // A value from 0 to 1 in sixteen bits, for the bitmap's red and green
        private fun encodeWide(value: Float) = (value.coerceIn(0f, 1f) * 65535).roundToInt()
    }

    // Each strand as a line with its glow, along the braid's cross-sections, for versions without runtime shaders
    private class LineRenderer : Renderer {
        private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val sections = FloatArray(MAX_SECTION_COUNT * 4)
        private val strand = FloatArray(2)
        private val path = Path()

        override fun draw(canvas: Canvas, view: AgentVoiceRibbonView) {
            val model = view.model
            val parameters = model.parameters
            val density = view.resources.displayMetrics.density
            val transition = model.transition
            val opacity = transition.opacity
            if (opacity <= 0f) return
            val start = model.farEnd
            val count = min(
                ceil((model.stopCenterX - start) / LINE_SPACING).toInt() + 1,
                MAX_SECTION_COUNT
            )
            model.fillSections(sections, start, LINE_SPACING, count)
            val isRightToLeft = LocaleController.isRTL
            val middle = view.height / 2f
            val slide = transition.slide * SEND_SLIDE
            val palette = view.palette
            val isDark = ThemeManager.isDark
            val strandCount = parameters.strandCount.coerceIn(1, 3)
            val secondColor = if (isDark) palette.glow else palette.deep
            val colors = intArrayOf(palette.core, secondColor, palette.glow)
            val level = model.fastLevel
            canvas.save()
            if (isRightToLeft) canvas.scale(-1f, 1f, view.width / 2f, middle)
            for (index in 0 until strandCount) {
                path.rewind()
                var hasStarted = false
                var strandOpacity = 0f
                for (column in 0 until count) {
                    val x = start + column * LINE_SPACING
                    val center = sections[column * 4]
                    model.getStrand(center, sections[column * 4 + 1], x, index, strand)
                    val screenX = (x - AgentVoiceRibbonModel.VIEW_ORIGIN + slide) * density
                    val screenY = middle + strand[0] * density
                    if (sections[column * 4 + 3] < 0.02f) {
                        hasStarted = false
                        continue
                    }
                    strandOpacity = max(strandOpacity, sections[column * 4 + 3])
                    if (hasStarted) path.lineTo(screenX, screenY) else path.moveTo(screenX, screenY)
                    hasStarted = true
                }
                val color = colors[index]
                val halfWidth = parameters.strandWidthAtRest + parameters.strandWidthGrowth * level
                val width = halfWidth * 2 * density
                linePaint.strokeWidth = width * (1 + parameters.glowWidth * 2)
                linePaint.color =
                    applyAlpha(color, 0.18f * parameters.glowStrength * strandOpacity * opacity)
                canvas.drawPath(path, linePaint)
                linePaint.strokeWidth = width
                linePaint.color = applyAlpha(color, 0.9f * strandOpacity * opacity)
                canvas.drawPath(path, linePaint)
            }
            canvas.restore()
        }

        private fun applyAlpha(color: Int, alpha: Float) =
            ColorUtils.setAlphaComponent(color, (alpha.coerceIn(0f, 1f) * 255).roundToInt())
    }

    private companion object {
        const val MAX_SECTION_COUNT = 512

        // dp of ribbon x the shader's sections reach past the far end and the Stop circle's centre
        const val SECTION_MARGIN = 6f

        // dp between the fallback's points along a strand
        const val LINE_SPACING = 2f

        // How far sending slides the thread, in dp, as the shader does
        const val SEND_SLIDE = 90f

        // Longer frames, such as after a stall, advance the thread by this much only, in seconds
        const val SETTLED_DELTA_TIME = 0.05f
        const val NANOS_PER_SECOND = 1e9f
    }
}
