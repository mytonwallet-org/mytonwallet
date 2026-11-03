package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.RuntimeShader
import android.graphics.drawable.Drawable
import android.os.Build
import android.view.Choreographer
import android.view.RoundedCorner
import android.view.View
import android.view.ViewGroup
import android.view.animation.AnimationUtils
import androidx.annotation.RequiresApi
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * The glow that runs around the screen's edge while the Agent thinks: a blue and a purple light
 * travelling clockwise, each side in the same time, fading inward over a few dp, as in Apple
 * Intelligence
 */
interface AgentEdgeGlow {
    /** Fades the glow in or out from where it is */
    fun setGlowing(isGlowing: Boolean)

    /** Takes the glow off its host at once */
    fun detach()
}

/** The glow over [host], above all its children, or null where runtime shaders are unavailable */
fun attachAgentEdgeGlow(host: ViewGroup, paneBounds: (() -> Rect)? = null): AgentEdgeGlow? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return null
    return try {
        AgentEdgeGlowDrawable(host, paneBounds)
    } catch (_: IllegalArgumentException) {
        // The device can't build the shader
        null
    }
}

/**
 * Compiled shaders kept for the next chat: compiling one takes the main thread a while, and a chat leaves its glow
 * as it closes
 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private object AgentEdgeGlowShaders {
    private const val KEPT = 2
    private val free = ArrayList<RuntimeShader>(KEPT)

    fun obtain(): RuntimeShader =
        free.removeLastOrNull() ?: RuntimeShader(AgentEdgeGlowDrawable.SHADER)

    fun recycle(shader: RuntimeShader) {
        if (free.size < KEPT && shader !in free) free.add(shader)
    }
}

/**
 * Lives in its host's overlay and draws only four strips along the host's edges, so nothing else is
 * redrawn because of it. Its frames stop while it is hidden, and wait while the window is not
 * visible.
 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private class AgentEdgeGlowDrawable(
    private val host: ViewGroup,
    private val paneBounds: (() -> Rect)?
) : Drawable(),
    AgentEdgeGlow,
    Choreographer.FrameCallback {
    private val shader = AgentEdgeGlowShaders.obtain()
    private val paint = Paint().apply { shader = this@AgentEdgeGlowDrawable.shader }
    private val strips = Array(4) { RectF() }
    private val location = IntArray(2)
    private val layoutListener = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
        updateGeometry()
    }
    private val startTime = AnimationUtils.currentAnimationTimeMillis()
    private var fadeStart = 0L
    private var fadeFrom = 0f
    private var fadeTarget = 0f
    private var isFrameScheduled = false
    private var isAttached = true

    // In dp
    private var cornerRadius = 0f

    init {
        host.overlay.add(this)
        host.addOnLayoutChangeListener(layoutListener)
        updateGeometry()
    }

    private val isMoving: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() && ValueAnimator.areAnimatorsEnabled()

    override fun setGlowing(isGlowing: Boolean) {
        val target = if (isGlowing) 1f else 0f
        if (!isAttached || fadeTarget == target) return
        val now = AnimationUtils.currentAnimationTimeMillis()
        fadeFrom = computeOpacity(now)
        fadeTarget = target
        fadeStart = now
        if (isGlowing) updateGeometry()
        invalidateSelf()
        scheduleFrame(0L)
    }

    override fun detach() {
        if (!isAttached) return
        isAttached = false
        Choreographer.getInstance().removeFrameCallback(this)
        isFrameScheduled = false
        host.removeOnLayoutChangeListener(layoutListener)
        host.overlay.remove(this)
        paint.shader = null
        AgentEdgeGlowShaders.recycle(shader)
    }

    override fun doFrame(frameTimeNanos: Long) {
        isFrameScheduled = false
        if (!isAttached) return
        val now = AnimationUtils.currentAnimationTimeMillis()
        val isFading = computeOpacity(now) != fadeTarget
        if (!isFading && (fadeTarget == 0f || !isMoving)) {
            // A finished fade, or still lights, keep their last frame
            invalidateSelf()
            return
        }
        if (host.windowVisibility != View.VISIBLE) {
            scheduleFrame(HIDDEN_WINDOW_CHECK_MS)
            return
        }
        invalidateSelf()
        scheduleFrame(0L)
    }

    private fun scheduleFrame(delayMs: Long) {
        if (isFrameScheduled) return
        isFrameScheduled = true
        Choreographer.getInstance().postFrameCallbackDelayed(this, delayMs)
    }

    // A constant rate, so reversing a fade midway takes only as long as the distance back
    private fun computeOpacity(time: Long): Float {
        val distance = abs(fadeTarget - fadeFrom)
        if (distance == 0f) return fadeTarget
        val duration = if (fadeTarget > fadeFrom) FADE_IN_DURATION_MS else FADE_OUT_DURATION_MS
        val progress = (max(0L, time - fadeStart).toFloat() / duration) / distance
        return fadeFrom + (fadeTarget - fadeFrom) * min(1f, progress)
    }

    override fun draw(canvas: Canvas) {
        val now = AnimationUtils.currentAnimationTimeMillis()
        val value = computeOpacity(now).coerceIn(0f, 1f)
        // Eased at both ends, so the glow neither pops in nor cuts off
        val shown = value * value * (3f - 2f * value)
        if (shown <= 0f) return
        updateGeometry()
        if (bounds.isEmpty) return
        val density = host.resources.displayMetrics.density
        val time = if (isMoving) ((now - startTime) % LOOP_DURATION_MS) / 1000f else 0f
        shader.setFloatUniform("size", bounds.width() / density, bounds.height() / density)
        shader.setFloatUniform("density", density)
        shader.setFloatUniform("radius", cornerRadius)
        shader.setFloatUniform("time", time)
        shader.setFloatUniform("opacity", shown)
        shader.setFloatUniform("dark", if (ThemeManager.isDark) 1f else 0f)
        canvas.save()
        canvas.translate(bounds.left.toFloat(), bounds.top.toFloat())
        for (strip in strips) {
            if (!strip.isEmpty) canvas.drawRect(strip, paint)
        }
        canvas.restore()
    }

    private fun updateGeometry() {
        val pane = paneBounds?.invoke() ?: Rect(0, 0, host.width, host.height)
        val density = host.resources.displayMetrics.density
        val isFullWindow = pane.left == 0 && pane.top == 0 &&
            pane.right == host.width && pane.bottom == host.height
        val radius = (if (isFullWindow) getDisplayCornerRadius() else 20.dp.toFloat()) / density
        if (bounds == pane && cornerRadius == radius) return
        bounds = pane
        cornerRadius = radius
        val width = pane.width()
        val height = pane.height()
        // Deep enough to cover the band also where it curves in along a rounded corner: the band's
        // inner edge is a quarter circle of radius `cornerRadius - GLOW_DEPTH`, reaching furthest
        // on the diagonal
        val innerRadius = max(0f, cornerRadius - GLOW_DEPTH)
        val cornerDepth = cornerRadius - innerRadius * DIAGONAL
        val depth = (ceil(max(GLOW_DEPTH, cornerDepth)) + 2f) * density
        val w = width.toFloat()
        val h = height.toFloat()
        val bandDepth = min(depth, h)
        val sideBottom = max(bandDepth, h - depth)
        strips[0].set(0f, 0f, w, bandDepth)
        strips[1].set(max(0f, w - depth), bandDepth, w, sideBottom)
        strips[2].set(0f, max(0f, h - depth), w, h)
        strips[3].set(0f, bandDepth, min(depth, w), sideBottom)
        invalidateSelf()
    }

    // The screen's corner rounding in px, when the host fills the window
    private fun getDisplayCornerRadius(): Float {
        val root = host.rootView
        val insets = root.rootWindowInsets ?: host.rootWindowInsets ?: return 0f
        host.getLocationInWindow(location)
        // Insets can reserve system-bar rows while this pane still occupies the full display width.
        if (location[0] != 0 || host.width != root.width) return 0f
        var radius = 0
        for (position in CORNER_POSITIONS) {
            radius = max(radius, insets.getRoundedCorner(position)?.radius ?: 0)
        }
        return radius.toFloat()
    }

    override fun setAlpha(alpha: Int) = Unit

    override fun setColorFilter(colorFilter: ColorFilter?) = Unit

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT

    companion object {
        // One loop of the lights, as in the shader
        const val LOOP_DURATION_MS = 2667L
        const val FADE_IN_DURATION_MS = 700f
        const val FADE_OUT_DURATION_MS = 400f
        const val HIDDEN_WINDOW_CHECK_MS = 500L

        // The shader draws up to 30 dp in from the rounded edge
        const val GLOW_DEPTH = 30f
        const val DIAGONAL = 0.7071f

        val CORNER_POSITIONS = intArrayOf(
            RoundedCorner.POSITION_TOP_LEFT,
            RoundedCorner.POSITION_TOP_RIGHT,
            RoundedCorner.POSITION_BOTTOM_RIGHT,
            RoundedCorner.POSITION_BOTTOM_LEFT
        )

        const val SHADER = """
            uniform float2 size;
            uniform float density;
            uniform float radius;
            uniform float time;
            uniform float opacity;
            uniform float dark;

            float roundedRectDistance(float2 p, float2 halfSize, float r) {
                float2 q = abs(p) - halfSize + r;
                return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
            }

            // One colour blob along the perimeter: a squared cosine over a little less than half of the loop
            float blob(float p, float centre) {
                float dp = abs(fract(p - centre + 0.5) - 0.5);
                const float halfWidth = 0.2375;
                if (dp >= halfWidth) {
                    return 0.0;
                }
                float c = cos(1.5707964 * dp / halfWidth);
                return c * c;
            }

            half4 main(float2 position) {
                float2 halfSize = size * 0.5;
                float2 centred = position / density - halfSize;
                // Inward from the rounded edge
                float inset = -roundedRectDistance(centred, halfSize, radius);
                if (inset < 0.0 || inset > 30.0) {
                    return half4(0.0);
                }
                inset = max(inset, 0.0);

                // Every side takes the same share of the loop, clockwise from the middle of the top edge (0)
                // through the right (0.25), the bottom (0.5) and the left (0.75)
                float2 uv = centred / size;
                float2 s = uv / max(max(abs(uv.x), abs(uv.y)), 0.00001) * 0.5;
                bool isVerticalSide = abs(s.x) >= abs(s.y);
                float p = 0.0;
                if (!isVerticalSide && s.y < 0.0) {
                    p = s.x * 0.25;
                    if (p < 0.0) {
                        p += 1.0;
                    }
                } else if (isVerticalSide && s.x > 0.0) {
                    p = 0.125 + (s.y + 0.5) * 0.25;
                } else if (!isVerticalSide) {
                    p = 0.375 + (0.5 - s.x) * 0.25;
                } else {
                    p = 0.625 + (0.5 - s.y) * 0.25;
                }

                // A full loop takes 2.667 s; the purple blob runs half a loop behind the blue one
                float blueCentre = fract(time / 2.667 + 0.125);
                float blue = blob(p, blueCentre);
                float purple = blob(p, blueCentre + 0.5);
                float weight = min(1.0, blue + purple);

                // Gaussian falloff inward (sigma 8 dp). The long sides are dimmer except near the corners, and within
                // about one corner radius of a corner the glow is a quarter brighter.
                const float sigma = 8.0;
                float falloff = exp(-(inset * inset) / (2.0 * sigma * sigma));
                bool isLongSide = isVerticalSide == (size.y >= size.x);
                float alongEdge = max(halfSize.x - abs(centred.x), halfSize.y - abs(centred.y));
                float cornerZone = max(radius, 24.0);
                float corner = 1.0 - smoothstep(0.25 * cornerZone, cornerZone, alongEdge);
                float sideGain = isLongSide ? 0.8 + 0.2 * (1.0 - smoothstep(20.0, 90.0, alongEdge)) : 1.0;
                float intensity = falloff * sideGain * (1.0 + 0.25 * corner);

                if (dark > 0.5) {
                    float3 blueColor = float3(5.0, 109.0, 205.0) / 255.0;
                    float3 purpleColor = float3(144.0, 70.0, 203.0) / 255.0;
                    float3 color = (blueColor * blue + purpleColor * purple) / max(blue + purple, 0.0001);
                    // Between the blobs the content shows through
                    float strength = intensity * weight;
                    float alpha = min(strength, 1.0);
                    return half4(float4(clamp(color * strength, 0.0, alpha), alpha) * opacity);
                }
                float3 blueColor = float3(50.0, 158.0, 255.0) / 255.0;
                float3 purpleColor = float3(190.0, 118.0, 253.0) / 255.0;
                float3 haze = float3(244.0, 245.0, 252.0) / 255.0;
                float3 blobColor = (blueColor * blue + purpleColor * purple) / max(blue + purple, 0.0001);
                // Between the blobs a white haze runs along the edge; above full intensity the colour deepens
                float coverage = 0.95 * intensity;
                float3 band = clamp(mix(haze, blobColor, weight * max(coverage, 1.0)), 0.0, 1.0);
                float alpha = min(coverage, 1.0);
                return half4(float4(band * alpha, alpha) * opacity);
            }
        """
    }
}
