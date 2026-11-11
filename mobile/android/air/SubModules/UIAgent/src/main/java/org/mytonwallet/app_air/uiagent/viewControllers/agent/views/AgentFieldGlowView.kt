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
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/** How far the rim's view reaches beyond the field on every side, for its bloom, in dp */
internal const val AGENT_FIELD_RIM_MARGIN = 28f

/**
 * Telegram's listening glow of the composer's field, as iOS's `AgentFieldGlowView` draws it. Inside the field, [isRim]
 * false, a soft light in the accent colour along its edge, brightest at the bottom and the leading side, with lights
 * drifting along the bottom, through the field and up and down the leading side, at half the strength of the reference
 * shader and twice its pace. Around it, [isRim] true, the field's border gives off light: a thin, almost white core
 * line, a bloom in the accent colour spilling out beyond the field and gone by the view's edge, and a softer haze
 * inside it, brightest at the bottom and the leading side, with bright stretches running along it. A rim view lies
 * [AGENT_FIELD_RIM_MARGIN] dp beyond the field on every side. A runtime shader draws it where one is available, and
 * gradients elsewhere. Its frames run only while it shows and moves; without motion its lights stand still.
 */
@SuppressLint("ViewConstructor")
internal class AgentFieldGlowView(context: Context, private val isRim: Boolean = false) :
    View(context),
    Choreographer.FrameCallback {
    private val renderer: Renderer = createRenderer()
    private var glowStart = 0L
    private var fadeStart = 0L
    private var fadeFrom = 0f
    private var fadeTarget = 0f
    private var isFrameScheduled = false
    private val frame = Frame()

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val isMoving: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() && ValueAnimator.areAnimatorsEnabled()

    /** The glow shows, or is fading in or out */
    val isLit: Boolean
        get() = fadeTarget > 0f || computeOpacity(AnimationUtils.currentAnimationTimeMillis()) > 0f

    /** Fades the glow in or out from where it is */
    fun setGlowing(isGlowing: Boolean) {
        val target = if (isGlowing) 1f else 0f
        if (fadeTarget == target) return
        val now = AnimationUtils.currentAnimationTimeMillis()
        fadeFrom = computeOpacity(now)
        if (isGlowing && fadeFrom <= 0f) glowStart = now
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
        frame.time = if (isMoving) (now - glowStart) / MS_PER_SECOND * speed else 0f
        frame.opacity = shown
        frame.margin = if (isRim) AGENT_FIELD_RIM_MARGIN else 0f
        frame.leading = if (LocaleController.isRTL) 1f else 0f
        renderer.draw(canvas, frame)
    }

    private class Frame {
        var width = 0f
        var height = 0f
        var density = 1f
        var time = 0f
        var opacity = 0f

        /** How far the view reaches beyond the field on each side, in dp */
        var margin = 0f

        /** 0 while the leading side is the left one, 1 while it is the right one */
        var leading = 0f
        var tint = WColor.Tint.color
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
            shader.setFloatUniform("opacity", frame.opacity)
            shader.setFloatUniform("leading", frame.leading)
            shader.setFloatUniform(
                "tint",
                Color.red(frame.tint) / MAX_CHANNEL,
                Color.green(frame.tint) / MAX_CHANNEL,
                Color.blue(frame.tint) / MAX_CHANNEL
            )
            canvas.drawRect(0f, 0f, frame.width, frame.height, paint)
        }
    }

    /** The shader's lights as radial gradients, and its edge as a few strokes fading from the leading side */
    private class GradientRenderer : Renderer {
        private val lightPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val edgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
        private val matrix = Matrix()
        private val rect = RectF()
        private var lightShader: RadialGradient? = null
        private var edgeShader: LinearGradient? = null
        private var shaderTint = 0
        private var edgeWidth = 0f
        private var edgeLeading = -1f

        override fun draw(canvas: Canvas, frame: Frame) {
            val dp = frame.density
            val light = obtainLightShader(frame.tint)
            lightPaint.shader = light
            val time = frame.time
            drawLight(
                canvas,
                light,
                frame.fromLeading(0.35f + 0.25f * sin(time * 0.55f)),
                frame.height,
                BOTTOM_LIGHT_SIGMA * dp,
                BOTTOM_LIGHT_STRENGTH * frame.opacity
            )
            drawLight(
                canvas,
                light,
                frame.fromLeading(0.575f + 0.325f * sin(time * 0.37f + 2f)),
                frame.height * (0.725f + 0.275f * sin(time * 0.8f)),
                DRIFT_LIGHT_SIGMA * dp,
                DRIFT_LIGHT_STRENGTH * frame.opacity
            )
            drawLight(
                canvas,
                light,
                frame.fromLeading(0f),
                frame.height * (0.65f + 0.35f * sin(time * 0.45f + 1f)),
                SIDE_LIGHT_SIGMA * dp,
                SIDE_LIGHT_STRENGTH * frame.opacity
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

        // A share of the width from the leading side, in px
        private fun Frame.fromLeading(fraction: Float) = abs(leading - fraction) * width

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
            edgeShader?.takeIf { edgeWidth == frame.width && edgeLeading == frame.leading }
                ?.let { return it }
            val strong = frame.tint
            val weakAlpha = (TRAILING_EDGE * MAX_CHANNEL).toInt()
            val weak = ColorUtils.setAlphaComponent(frame.tint, weakAlpha)
            val from = frame.leading * frame.width
            return LinearGradient(
                from,
                0f,
                frame.width - from,
                0f,
                intArrayOf(strong, weak, weak),
                floatArrayOf(0f, LEADING_EDGE_SPAN, 1f),
                Shader.TileMode.CLAMP
            ).also {
                edgeShader = it
                edgeWidth = frame.width
                edgeLeading = frame.leading
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

        // Without a shader: the rim's core and its bloom, whose strokes reach 18 dp out, within the view's margin
        const val RIM_CORE_WIDTH = 1.4f
        val RIM_BLOOM_WIDTHS = floatArrayOf(4f, 10f, 20f, 36f)
        val RIM_BLOOM_ALPHAS = floatArrayOf(0.45f, 0.25f, 0.12f, 0.05f)
        const val RIM_CORE_WHITENING = 0.7f
        const val RIM_BLOOM_WHITENING = 0.1f

        // How the rim's lit stretches run round it, in turns per second of the glow's time
        const val RIM_TURN_RATE = 0.2f
        const val FULL_TURN = 360f

        // Without a shader: the rim between its lit stretches, and where they lie round it
        const val RIM_DIM = 0.35f
        val RIM_STOPS = floatArrayOf(0f, 0.2f, 0.5f, 0.72f, 1f)

        // In dp
        const val FIELD_RADIUS = 24f
        const val BOTTOM_LIGHT_SIGMA = 28f
        const val DRIFT_LIGHT_SIGMA = 40f
        const val SIDE_LIGHT_SIGMA = 22f
        val EDGE_INSETS = floatArrayOf(1f, 3.5f, 7f)
        val EDGE_WIDTHS = floatArrayOf(2f, 3f, 4f)

        val EDGE_ALPHAS = floatArrayOf(0.25f, 0.125f, 0.05f)
        const val BOTTOM_LIGHT_STRENGTH = 0.225f
        const val DRIFT_LIGHT_STRENGTH = 0.11f
        const val SIDE_LIGHT_STRENGTH = 0.175f

        // The edge fades from the leading side over this share of the width, to this strength
        const val LEADING_EDGE_SPAN = 0.3f
        const val TRAILING_EDGE = 0.35f

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
            uniform float leading;
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

            // A share of the width from the leading side, in dp
            float fromLeading(float fraction) {
                return abs(leading - fraction) * size.x;
            }

            half4 main(float2 position) {
                float2 xy = position / density - margin;
                float2 halfSize = size * 0.5;
                float inset = max(-roundedRectDistance(xy - halfSize, halfSize, radius), 0.0);
                float leadingDistance = abs(xy.x / size.x - leading) * size.x;
                float down = xy.y / size.y;
                float edgeBand = exp(-inset / 5.0);
                float nearLeading = exp(-leadingDistance / 50.0);

                // One light drifts along the bottom, one through the field and one up and down
                // the leading side
                float2 bottomCentre = float2(fromLeading(0.35 + 0.25 * sin(time * 0.55)), size.y);
                float2 driftCentre = float2(
                    fromLeading(0.575 + 0.325 * sin(time * 0.37 + 2.0)),
                    size.y * (0.725 + 0.275 * sin(time * 0.8))
                );
                float2 sideCentre = float2(
                    fromLeading(0.0),
                    size.y * (0.65 + 0.35 * sin(time * 0.45 + 1.0))
                );
                float bottomLight = glowLight(xy, bottomCentre, 28.0);
                float driftLight = glowLight(xy, driftCentre, 40.0);
                float sideLight = glowLight(xy, sideCentre, 22.0);
                float haze = 0.3 * exp(-(size.y - xy.y) / 22.0) * (0.5 + 0.5 * nearLeading);
                float glow = edgeBand * (0.35 + 1.1 * nearLeading + 0.6 * down) *
                    (0.7 + 0.9 * bottomLight + 0.5 * driftLight + 0.6 * sideLight) +
                    0.45 * bottomLight + 0.25 * driftLight + 0.35 * sideLight + haze;
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
            uniform float leading;
            uniform float3 tint;

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
                float across = clamp(xy.x / size.x, 0.0, 1.0);
                float nearLeading = exp(-abs(across - leading) * size.x / 90.0);
                float base = 0.15 + 0.45 * down + 0.6 * nearLeading;
                float spots = rimSpot(along, time * 140.0, total, 60.0) +
                    0.8 * rimSpot(along, total * 0.45 - time * 95.0, total, 48.0) +
                    0.6 * rimSpot(along, total * 0.7 + time * 60.0, total, 70.0);
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
