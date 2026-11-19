package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.graphics.SweepGradient
import android.os.Build
import android.view.Choreographer
import android.view.View
import android.view.animation.AnimationUtils
import androidx.annotation.RequiresApi
import androidx.core.graphics.ColorUtils
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/** How far the rim's view reaches beyond the field on every side, for its bloom, in dp */
internal const val AGENT_FIELD_RIM_MARGIN = 28f

/**
 * Telegram's listening glow of the composer's field, as iOS's `AgentFieldGlowView` draws it. Inside the field, [isRim]
 * false, a soft light in the accent colour along its edge, brightest at the bottom and as bright near either side, with
 * lights wandering over the field, one low along the bottom and two through it, at half the strength of the reference
 * shader and twice its pace. Around it, [isRim] true, the field's border gives off light: a thin, almost white core
 * line, a bloom in the accent colour spilling out beyond the field and gone by the view's edge, and a softer haze
 * inside it, brightest at the bottom and as bright near either side, with bright stretches running along it both ways
 * at paces that rise and fall. A rim view lies [AGENT_FIELD_RIM_MARGIN] dp beyond the field on every side. A runtime
 * shader draws it where one is available, and gradients elsewhere. Its frames run only while it shows and moves;
 * without motion its lights stand still.
 */
@SuppressLint("ViewConstructor")
internal class AgentFieldGlowView(context: Context, private val isRim: Boolean = false) :
    View(context),
    Choreographer.FrameCallback {
    private val renderer: Renderer = createRenderer()
    private var glowStart = 0L

    /** Where in its motion the glow starts, picked at random each time it comes in, so no two glows move alike */
    private var timeOffset = 0f
    private var fadeStart = 0L
    private var fadeFrom = 0f
    private var fadeTarget = 0f
    private var isFrameScheduled = false
    private val frame = Frame()

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val isMoving: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled())

    /** The glow shows, or is fading in or out */
    val isLit: Boolean
        get() = fadeTarget > 0f || computeOpacity(AnimationUtils.currentAnimationTimeMillis()) > 0f

    /** Fades the glow in or out from where it is */
    fun setGlowing(isGlowing: Boolean) {
        val target = if (isGlowing) 1f else 0f
        if (fadeTarget == target) return
        val now = AnimationUtils.currentAnimationTimeMillis()
        fadeFrom = computeOpacity(now)
        if (isGlowing && fadeFrom <= 0f) {
            glowStart = now
            timeOffset = Random.nextFloat() * MAX_TIME_OFFSET
            rimSpots.reset()
        }
        fadeTarget = target
        fadeStart = now
        invalidate()
        scheduleFrame(0L)
    }

    fun updateTheme() {
        frame.tint = WColor.Tint.color
        invalidate()
    }

    override fun doFrame(frameTimeNanos: Long) {
        isFrameScheduled = false
        if (!isAttachedToWindow) return
        val now = AnimationUtils.currentAnimationTimeMillis()
        val isFading = computeOpacity(now) != fadeTarget
        if (!isFading && (fadeTarget == 0f || !isMoving)) {
            // A finished fade, or still lights, keep their last frame
            invalidate()
            return
        }
        if (windowVisibility != VISIBLE) {
            scheduleFrame(HIDDEN_WINDOW_CHECK_MS)
            return
        }
        invalidate()
        scheduleFrame(0L)
    }

    private fun scheduleFrame(delayMs: Long) {
        if (isFrameScheduled || !isAttachedToWindow) return
        isFrameScheduled = true
        Choreographer.getInstance().postFrameCallbackDelayed(this, delayMs)
    }

    // It takes no room of its own: the field's content sizes the field, and the glow fills it
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(resolveSize(0, widthMeasureSpec), resolveSize(0, heightMeasureSpec))
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        scheduleFrame(0L)
    }

    override fun onDetachedFromWindow() {
        Choreographer.getInstance().removeFrameCallback(this)
        isFrameScheduled = false
        super.onDetachedFromWindow()
    }

    // A constant rate, so reversing a fade midway takes only as long as the distance back
    private fun computeOpacity(time: Long): Float {
        val distance = abs(fadeTarget - fadeFrom)
        if (distance == 0f) return fadeTarget
        val duration = if (fadeTarget > fadeFrom) FADE_IN_MS else FADE_OUT_MS
        val progress = (max(0L, time - fadeStart).toFloat() / duration) / distance
        return fadeFrom + (fadeTarget - fadeFrom) * min(1f, progress)
    }

    override fun onDraw(canvas: Canvas) {
        val now = AnimationUtils.currentAnimationTimeMillis()
        val value = computeOpacity(now).coerceIn(0f, 1f)
        // Eased at both ends, so the glow neither pops in nor cuts off
        val shown = value * value * (3f - 2f * value)
        if (shown <= 0f || width == 0 || height == 0) return
        frame.width = width.toFloat()
        frame.height = height.toFloat()
        frame.density = resources.displayMetrics.density
        val speed = if (isRim) 1f else LIGHTS_SPEED
        val elapsed = if (isMoving) (now - glowStart) / MS_PER_SECOND * speed else 0f
        frame.time = timeOffset + elapsed
        frame.opacity = shown
        frame.margin = if (isRim) AGENT_FIELD_RIM_MARGIN else 0f
        if (isRim) {
            val widthDp = frame.width / frame.density - 2 * frame.margin
            val heightDp = frame.height / frame.density - 2 * frame.margin
            rimSpots.advance(frame.time, getRimLength(widthDp, heightDp))
            frame.rimPhases = rimSpots.phases
        }
        renderer.draw(canvas, frame)
    }

    /**
     * Where the rim's three bright stretches stand, as shares of its loop. They move on at their
     * paces in dp along the rim, so they keep them on a field of any size and are carried along as
     * it grows or shrinks.
     */
    private class RimSpots {
        val phases = FloatArray(3)
        private var time = Float.NaN

        fun reset() {
            time = Float.NaN
        }

        fun advance(nextTime: Float, rimLength: Float) {
            val elapsed = nextTime - time
            // A glow that starts anew starts them over
            if (elapsed.isNaN() || elapsed < 0f || rimLength <= 0f) {
                val loop = RIM_START_LOOP
                phases[0] = (nextTime * 140f + 60f * sin(nextTime * 0.7f)) / loop
                phases[1] = 0.45f + (-nextTime * 95f + 50f * sin(nextTime * 0.53f + 1f)) / loop
                phases[2] = 0.7f + (nextTime * 60f + 40f * sin(nextTime * 0.91f + 2f)) / loop
            } else {
                // Each pace rises and falls, and the second goes the other way
                phases[0] += (140f + 42f * cos(nextTime * 0.7f)) * elapsed / rimLength
                phases[1] += (-95f + 26.5f * cos(nextTime * 0.53f + 1f)) * elapsed / rimLength
                phases[2] += (60f + 36.4f * cos(nextTime * 0.91f + 2f)) * elapsed / rimLength
            }
            for (index in phases.indices) phases[index] %= 1f
            time = nextTime
        }
    }

    private val rimSpots = RimSpots()

    // The rounded rectangle's perimeter in dp, as the rim shader measures its loop
    private fun getRimLength(widthDp: Float, heightDp: Float): Float {
        val radius = min(FIELD_RADIUS, heightDp / 2f)
        val innerWidth = max(widthDp / 2f - radius, 0f)
        val innerHeight = max(heightDp / 2f - radius, 0f)
        return 4f * (innerWidth + innerHeight + HALF_PI * radius)
    }

    private class Frame {
        var width = 0f
        var height = 0f
        var density = 1f
        var time = 0f
        var opacity = 0f

        /** How far the view reaches beyond the field on each side, in dp */
        var margin = 0f
        var tint = WColor.Tint.color

        /** Where the rim's bright stretches stand, for the rim's shader */
        var rimPhases: FloatArray? = null
    }

    private interface Renderer {
        fun draw(canvas: Canvas, frame: Frame)
    }

    private fun createRenderer(): Renderer {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                return ShaderRenderer(if (isRim) RIM_SHADER else SHADER)
            } catch (_: IllegalArgumentException) {
                // The device can't build the shader
            }
        }
        return if (isRim) RimGradientRenderer() else GradientRenderer()
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private class ShaderRenderer(source: String) : Renderer {
        private val shader = RuntimeShader(source)
        private val paint = Paint().apply { shader = this@ShaderRenderer.shader }

        override fun draw(canvas: Canvas, frame: Frame) {
            // The field's size, inside the view's margin
            val widthDp = frame.width / frame.density - 2 * frame.margin
            val heightDp = frame.height / frame.density - 2 * frame.margin
            if (widthDp <= 0f || heightDp <= 0f) return
            shader.setFloatUniform("size", widthDp, heightDp)
            shader.setFloatUniform("margin", frame.margin)
            shader.setFloatUniform("density", frame.density)
            shader.setFloatUniform("radius", min(FIELD_RADIUS, heightDp / 2f))
            shader.setFloatUniform("time", frame.time)
            frame.rimPhases?.let { shader.setFloatUniform("rimPhases", it[0], it[1], it[2]) }
            shader.setFloatUniform("opacity", frame.opacity)
            shader.setFloatUniform(
                "tint",
                Color.red(frame.tint) / MAX_CHANNEL,
                Color.green(frame.tint) / MAX_CHANNEL,
                Color.blue(frame.tint) / MAX_CHANNEL
            )
            canvas.drawRect(0f, 0f, frame.width, frame.height, paint)
        }
    }

    /** The shader's lights as radial gradients, and its edge as a few strokes fading from either side */
    private class GradientRenderer : Renderer {
        private val lightPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val edgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
        private val matrix = Matrix()
        private val rect = RectF()
        private var lightShader: RadialGradient? = null
        private var edgeShader: LinearGradient? = null
        private var shaderTint = 0
        private var edgeWidth = 0f

        override fun draw(canvas: Canvas, frame: Frame) {
            val dp = frame.density
            val light = obtainLightShader(frame.tint)
            lightPaint.shader = light
            val time = frame.time
            drawLight(
                canvas,
                light,
                frame.width * wander(time, 0.55f, 0f, 1.31f, 1.7f),
                frame.height * (0.9f + 0.1f * sin(time * 0.83f + 0.4f)),
                BOTTOM_LIGHT_SIGMA * dp,
                BOTTOM_LIGHT_STRENGTH * frame.opacity
            )
            drawLight(
                canvas,
                light,
                frame.width * wander(time, 0.37f, 2f, 0.97f, 4.1f),
                frame.height * (0.6f + 0.3f * sin(time * 0.8f)),
                DRIFT_LIGHT_SIGMA * dp,
                DRIFT_LIGHT_STRENGTH * frame.opacity
            )
            drawLight(
                canvas,
                light,
                frame.width * wander(time, 0.45f, 4.2f, 1.13f, 0.6f),
                frame.height * (0.65f + 0.35f * sin(time * 0.61f + 1f)),
                STRAY_LIGHT_SIGMA * dp,
                STRAY_LIGHT_STRENGTH * frame.opacity
            )
            edgePaint.shader = obtainEdgeShader(frame)
            val radius = min(FIELD_RADIUS * dp, frame.height / 2f)
            for (index in EDGE_INSETS.indices) {
                val inset = EDGE_INSETS[index] * dp
                edgePaint.strokeWidth = EDGE_WIDTHS[index] * dp
                edgePaint.alpha = (EDGE_ALPHAS[index] * frame.opacity * MAX_CHANNEL).toInt()
                rect.set(inset, inset, frame.width - inset, frame.height - inset)
                val cornerRadius = max(0f, radius - inset)
                canvas.drawRoundRect(rect, cornerRadius, cornerRadius, edgePaint)
            }
        }

        // A share of the width that wanders over all of it, as the shader's wander does
        private fun wander(
            time: Float,
            first: Float,
            firstPhase: Float,
            second: Float,
            secondPhase: Float
        ) = 0.5f + 0.28f * sin(time * first + firstPhase) + 0.17f * sin(time * second + secondPhase)

        private fun drawLight(
            canvas: Canvas,
            light: RadialGradient,
            centreX: Float,
            centreY: Float,
            sigma: Float,
            strength: Float
        ) {
            val radius = sigma * LIGHT_REACH
            matrix.setScale(radius, radius)
            matrix.postTranslate(centreX, centreY)
            light.setLocalMatrix(matrix)
            lightPaint.alpha = (strength.coerceIn(0f, 1f) * MAX_CHANNEL).toInt()
            canvas.drawCircle(centreX, centreY, radius, lightPaint)
        }

        // A unit gaussian, scaled to each light
        private fun obtainLightShader(tint: Int): RadialGradient {
            lightShader?.takeIf { shaderTint == tint }?.let { return it }
            val colors = IntArray(GAUSSIAN_STOPS.size) { index ->
                ColorUtils.setAlphaComponent(tint, (GAUSSIAN_STOPS[index] * MAX_CHANNEL).toInt())
            }
            return RadialGradient(0f, 0f, 1f, colors, GAUSSIAN_POSITIONS, Shader.TileMode.CLAMP)
                .also {
                    lightShader = it
                    shaderTint = tint
                    edgeShader = null
                }
        }

        private fun obtainEdgeShader(frame: Frame): LinearGradient {
            edgeShader?.takeIf { edgeWidth == frame.width }?.let { return it }
            val side = ColorUtils.setAlphaComponent(frame.tint, (SIDE_EDGE * MAX_CHANNEL).toInt())
            val middleAlpha = (MIDDLE_EDGE * MAX_CHANNEL).toInt()
            val middle = ColorUtils.setAlphaComponent(frame.tint, middleAlpha)
            return LinearGradient(
                0f,
                0f,
                frame.width,
                0f,
                intArrayOf(side, middle, middle, side),
                floatArrayOf(0f, SIDE_EDGE_SPAN, 1f - SIDE_EDGE_SPAN, 1f),
                Shader.TileMode.CLAMP
            ).also {
                edgeShader = it
                edgeWidth = frame.width
            }
        }
    }

    /**
     * The rim's core and its bloom and haze as strokes round the field, the bloom's outer half beyond the field and its
     * inner half inside it, and its lit stretches a sweep turning round it
     */
    private class RimGradientRenderer : Renderer {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
        private val matrix = Matrix()
        private val rect = RectF()
        private var coreShader: SweepGradient? = null
        private var bloomShader: SweepGradient? = null
        private var shaderTint = 0

        override fun draw(canvas: Canvas, frame: Frame) {
            obtainShaders(frame.tint)
            val dp = frame.density
            val margin = frame.margin * dp
            val radius = min(FIELD_RADIUS * dp, (frame.height - 2 * margin) / 2f)
            if (radius <= 0f) return
            matrix.setRotate(frame.time * RIM_TURN_RATE * FULL_TURN)
            matrix.postTranslate(frame.width / 2f, frame.height / 2f)
            coreShader?.setLocalMatrix(matrix)
            bloomShader?.setLocalMatrix(matrix)
            paint.shader = bloomShader
            for (index in RIM_BLOOM_WIDTHS.indices) {
                paint.strokeWidth = RIM_BLOOM_WIDTHS[index] * dp
                paint.alpha = (RIM_BLOOM_ALPHAS[index] * frame.opacity * MAX_CHANNEL).toInt()
                drawRim(canvas, frame, margin, radius)
            }
            paint.shader = coreShader
            paint.strokeWidth = RIM_CORE_WIDTH * dp
            paint.alpha = (frame.opacity * MAX_CHANNEL).toInt()
            drawRim(canvas, frame, margin, radius)
        }

        private fun drawRim(canvas: Canvas, frame: Frame, margin: Float, radius: Float) {
            rect.set(margin, margin, frame.width - margin, frame.height - margin)
            canvas.drawRoundRect(rect, radius, radius, paint)
        }

        // Two bright stretches and two dim ones round the rim: a core whitened as the shader's is, and a bloom in the
        // accent colour whitened by a tenth
        private fun obtainShaders(tint: Int) {
            if (coreShader != null && shaderTint == tint) return
            val core = ColorUtils.blendARGB(tint, Color.WHITE, RIM_CORE_WHITENING)
            val coreDim = ColorUtils.setAlphaComponent(core, (RIM_DIM * MAX_CHANNEL).toInt())
            val bloom = ColorUtils.blendARGB(tint, Color.WHITE, RIM_BLOOM_WHITENING)
            val bloomDim = ColorUtils.setAlphaComponent(bloom, (RIM_DIM * MAX_CHANNEL).toInt())
            coreShader = SweepGradient(
                0f,
                0f,
                intArrayOf(coreDim, core, coreDim, core, coreDim),
                RIM_STOPS
            )
            bloomShader = SweepGradient(
                0f,
                0f,
                intArrayOf(bloomDim, bloom, bloomDim, bloom, bloomDim),
                RIM_STOPS
            )
            shaderTint = tint
        }
    }

    private companion object {
        const val FADE_IN_MS = 300f
        const val FADE_OUT_MS = 400f
        const val HIDDEN_WINDOW_CHECK_MS = 500L
        const val MS_PER_SECOND = 1000f
        const val MAX_CHANNEL = 255f

        // The lights inside move at twice the pace of the reference shader, the rim at its own
        const val LIGHTS_SPEED = 2f

        // The motion's swings don't repeat within this many seconds, so a start picked in it is as good as any
        const val MAX_TIME_OFFSET = 1000f

        // Without a shader: the rim's core and its bloom, whose strokes reach 18 dp out, within the view's margin
        const val RIM_CORE_WIDTH = 1.4f
        val RIM_BLOOM_WIDTHS = floatArrayOf(4f, 10f, 20f, 36f)
        val RIM_BLOOM_ALPHAS = floatArrayOf(0.45f, 0.25f, 0.12f, 0.05f)
        const val RIM_CORE_WHITENING = 0.7f
        const val RIM_BLOOM_WHITENING = 0.1f

        // How the rim's lit stretches run round it, in turns per second of the glow's time
        const val RIM_TURN_RATE = 0.2f

        // The loop in dp whose shares the shader's stretches start at
        const val RIM_START_LOOP = 800f
        const val HALF_PI = (Math.PI / 2).toFloat()
        const val FULL_TURN = 360f

        // Without a shader: the rim between its lit stretches, and where they lie round it
        const val RIM_DIM = 0.35f
        val RIM_STOPS = floatArrayOf(0f, 0.2f, 0.5f, 0.72f, 1f)

        // In dp
        const val FIELD_RADIUS = 24f
        const val BOTTOM_LIGHT_SIGMA = 28f
        const val DRIFT_LIGHT_SIGMA = 40f
        const val STRAY_LIGHT_SIGMA = 26f
        val EDGE_INSETS = floatArrayOf(1f, 3.5f, 7f)
        val EDGE_WIDTHS = floatArrayOf(2f, 3f, 4f)

        val EDGE_ALPHAS = floatArrayOf(0.25f, 0.125f, 0.05f)
        const val BOTTOM_LIGHT_STRENGTH = 0.225f
        const val DRIFT_LIGHT_STRENGTH = 0.11f
        const val STRAY_LIGHT_STRENGTH = 0.175f

        // The edge fades from either side over this share of the width, from the first strength to the second: the
        // two sides share the light one alone would have
        const val SIDE_EDGE_SPAN = 0.3f
        const val SIDE_EDGE = 0.7f
        const val MIDDLE_EDGE = 0.35f

        // A gaussian drawn out to 2.5 sigma
        const val LIGHT_REACH = 2.5f
        val GAUSSIAN_POSITIONS = floatArrayOf(0f, 0.2f, 0.4f, 0.6f, 0.8f, 1f)
        val GAUSSIAN_STOPS = floatArrayOf(1f, 0.88f, 0.61f, 0.32f, 0.14f, 0f)

        const val SHADER = """
            uniform float2 size;
            uniform float margin;
            uniform float density;
            uniform float radius;
            uniform float time;
            uniform float opacity;
            uniform float3 tint;

            float roundedRectDistance(float2 p, float2 halfSize, float r) {
                float2 q = abs(p) - halfSize + r;
                return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
            }

            // A soft light spreading over sigma dp
            float glowLight(float2 xy, float2 centre, float sigma) {
                float2 d = xy - centre;
                return exp(-dot(d, d) / (2.0 * sigma * sigma));
            }

            // How near x lies to either side, the light along the edge reaching reach dp in from each
            float nearSide(float x, float reach) {
                return exp(-max(min(x, size.x - x), 0.0) / reach);
            }

            // A share of the width that wanders over all of it along two slow swings that never quite repeat
            float wander(float first, float firstPhase, float second, float secondPhase) {
                return 0.5 + 0.28 * sin(time * first + firstPhase) +
                    0.17 * sin(time * second + secondPhase);
            }

            half4 main(float2 position) {
                float2 xy = position / density - margin;
                float2 halfSize = size * 0.5;
                float inset = max(-roundedRectDistance(xy - halfSize, halfSize, radius), 0.0);
                float down = xy.y / size.y;
                float edgeBand = exp(-inset / 5.0);
                float sides = nearSide(xy.x, 50.0);

                // Three lights wander over the field, one low along the bottom and two through it,
                // so neither side is favoured
                float2 bottomCentre = float2(
                    size.x * wander(0.55, 0.0, 1.31, 1.7),
                    size.y * (0.9 + 0.1 * sin(time * 0.83 + 0.4))
                );
                float2 driftCentre = float2(
                    size.x * wander(0.37, 2.0, 0.97, 4.1),
                    size.y * (0.6 + 0.3 * sin(time * 0.8))
                );
                float2 strayCentre = float2(
                    size.x * wander(0.45, 4.2, 1.13, 0.6),
                    size.y * (0.65 + 0.35 * sin(time * 0.61 + 1.0))
                );
                float bottomLight = glowLight(xy, bottomCentre, 28.0);
                float driftLight = glowLight(xy, driftCentre, 40.0);
                float strayLight = glowLight(xy, strayCentre, 26.0);
                // Each side is lit half as much, so the two together light the field as one alone would
                float haze = 0.3 * exp(-(size.y - xy.y) / 22.0) * (0.5 + 0.25 * sides);
                float glow = edgeBand * (0.35 + 0.55 * sides + 0.6 * down) *
                    (0.7 + 0.9 * bottomLight + 0.5 * driftLight + 0.6 * strayLight) +
                    0.45 * bottomLight + 0.25 * driftLight + 0.35 * strayLight + haze;
                // Half the strength of the reference shader
                float alpha = clamp(glow * 0.275, 0.0, 0.46) * opacity;
                // The brightest light whitens
                float3 color = mix(tint, float3(1.0), clamp((glow - 1.1) * 0.35, 0.0, 0.6));
                return half4(half3(color * alpha), half(alpha));
            }
        """

        const val RIM_SHADER = """
            uniform float2 size;
            uniform float margin;
            uniform float density;
            uniform float radius;
            uniform float time;
            uniform float opacity;
            uniform float3 tint;
            // Where the rim's three bright stretches stand, as shares of its loop
            uniform float3 rimPhases;

            const float PI = 3.14159265;
            const float HALF_PI = 1.57079633;

            float roundedRectDistance(float2 p, float2 halfSize, float r) {
                float2 q = abs(p) - halfSize + r;
                return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
            }

            // Where along the field's border the point of it nearest to local lies, in dp clockwise from the middle
            // of the top edge, on a border total dp long
            float rimAlong(float2 local, float2 halfSize, float r, float total) {
                float2 inner = max(halfSize - r, 0.0);
                float arc = HALF_PI * r;
                float2 q = clamp(local, -inner, inner);
                float2 d = local - q;
                float2 border = float2(0.0);
                if (length(d) > 0.001) {
                    border = q + normalize(d) * r;
                } else if (inner.y - abs(local.y) < inner.x - abs(local.x)) {
                    border = float2(local.x, sign(local.y) * halfSize.y);
                } else {
                    border = float2(sign(local.x) * halfSize.x, local.y);
                }
                if (abs(border.x) <= inner.x) {
                    // The top edge, its left half at the end of the loop, or the bottom edge
                    if (border.y < 0.0) {
                        return border.x >= 0.0 ? border.x : total + border.x;
                    }
                    return 3.0 * inner.x + 2.0 * arc + 2.0 * inner.y - (border.x + inner.x);
                }
                if (abs(border.y) <= inner.y) {
                    // The right edge, or the left one
                    if (border.x > 0.0) {
                        return inner.x + arc + (border.y + inner.y);
                    }
                    return 3.0 * inner.x + 3.0 * arc + 2.0 * inner.y + (inner.y - border.y);
                }
                // A corner: the angle clockwise from up around its centre
                float2 centre = sign(border) * inner;
                float2 v = border - centre;
                float angle = atan(v.x, -v.y);
                if (angle < 0.0) {
                    angle += 2.0 * PI;
                }
                if (angle <= HALF_PI) {
                    return inner.x + r * angle;
                }
                if (angle <= PI) {
                    return inner.x + arc + 2.0 * inner.y + r * (angle - HALF_PI);
                }
                if (angle <= 1.5 * PI) {
                    return 3.0 * inner.x + 2.0 * arc + 2.0 * inner.y + r * (angle - PI);
                }
                return 3.0 * inner.x + 3.0 * arc + 4.0 * inner.y + r * (angle - 1.5 * PI);
            }

            // A bright stretch of the rim centred centre dp along a border total dp long
            float rimSpot(float along, float centre, float total, float sigma) {
                float d = abs(fract((along - centre) / total + 0.5) - 0.5) * total;
                return exp(-d * d / (2.0 * sigma * sigma));
            }

            half4 main(float2 position) {
                float2 xy = position / density - margin;
                float2 halfSize = size * 0.5;
                float2 local = xy - halfSize;
                float edgeDistance = roundedRectDistance(local, halfSize, radius);
                float2 inner = max(halfSize - radius, 0.0);
                float total = 4.0 * (inner.x + inner.y + HALF_PI * radius);
                float along = rimAlong(local, halfSize, radius, total);

                float down = clamp(xy.y / size.y, 0.0, 1.0);
                float sides = exp(-max(min(xy.x, size.x - xy.x), 0.0) / 90.0);
                float base = 0.15 + 0.45 * down + 0.3 * sides;
                // The stretches run both ways round the rim, each at a pace that rises and falls, so
                // they meet and part anywhere. They stand at shares of the loop, which a field that
                // grows or shrinks carries along with it.
                float first = fract(rimPhases.x) * total;
                float second = fract(rimPhases.y) * total;
                float third = fract(rimPhases.z) * total;
                float spots = rimSpot(along, first, total, 60.0) +
                    0.8 * rimSpot(along, second, total, 48.0) +
                    0.6 * rimSpot(along, third, total, 70.0);
                float intensity = base * (0.3 + 1.2 * spots);

                float core = exp(-edgeDistance * edgeDistance / (2.0 * 0.6 * 0.6));
                // The bloom spreads out over a few dp and fades on over more, and the haze inside is softer
                float outer = edgeDistance > 0.0 ?
                    exp(-edgeDistance / 7.0) + 0.35 * exp(-edgeDistance / 18.0) : 0.0;
                // It is gone by the view's edge
                outer *= 1.0 - smoothstep(0.5 * margin, margin, edgeDistance);
                float haze = edgeDistance < 0.0 ? 0.45 * exp(edgeDistance / 9.0) : 0.0;
                float coreAlpha = clamp(core * intensity, 0.0, 1.0);
                float bloomAlpha = clamp((outer + haze) * intensity, 0.0, 0.9);
                // The core whitens the brighter it is
                float3 coreColor = mix(tint, float3(1.0), clamp(0.45 + 0.45 * intensity, 0.0, 0.9));
                float3 bloomColor = mix(tint, float3(1.0), 0.1);
                float3 color = coreColor * coreAlpha + bloomColor * bloomAlpha * (1.0 - coreAlpha);
                float alpha = coreAlpha + bloomAlpha * (1.0 - coreAlpha);
                return half4(half3(color * opacity), half(alpha * opacity));
            }
        """
    }
}
