package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.Color
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
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.animation.AnimationUtils
import androidx.annotation.RequiresApi
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * The glow of the screen's edge while the Agent thinks, as iOS's `AgentEdgeGlowView` draws it, as the Agent's field
 * glows while it listens: a thin, almost white core line along the rounded edge giving off a short bright bloom and a
 * longer softer haze inward, with blue and violet stretches running along it at their own speeds. The edge is brighter
 * toward the bottom and toward both sides alike, and faint lights drift behind the composer near the bottom.
 */
interface AgentEdgeGlow {
    /** Fades the glow in or out from where it is */
    fun setGlowing(isGlowing: Boolean)

    /** Ends the glow without a fade, as when the Agent finished while the chat was away */
    fun hideAtOnce()

    /** Takes the glow off its views at once */
    fun detach()
}

/**
 * The glow along the edges of [pane], a child of [host], or null where runtime shaders are unavailable. As iOS keeps
 * its glow behind its glass controls, it lies in two layers. From [headerBottom] px below the top of [host] down it
 * lies in [pane] right under [under] and the views after it, such as the composer and the buttons over the chat.
 * Above that it lies in [host] over the header's background, its rounded corners included, right under
 * [headerContent], the header's title and buttons.
 */
fun attachAgentEdgeGlow(
    host: ViewGroup,
    headerContent: View?,
    pane: ViewGroup,
    under: View,
    headerBottom: () -> Int
): AgentEdgeGlow? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return null
    return try {
        AgentEdgeGlowRenderer(host, headerContent, pane, under, headerBottom)
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
        free.removeLastOrNull() ?: RuntimeShader(AgentEdgeGlowRenderer.SHADER)

    fun recycle(shader: RuntimeShader) {
        if (free.size < KEPT && shader !in free) free.add(shader)
    }
}

/**
 * Draws the glow only into four strips along the pane's edges, the bottom one tall enough for the drifting lights, in
 * two layers: one in the host above the header's bottom and one in the pane below it. Its frames stop while it is
 * hidden, and wait while the window is not visible or the host is off screen.
 */
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private class AgentEdgeGlowRenderer(
    private val host: ViewGroup,
    private val headerContent: View?,
    private val pane: ViewGroup,
    under: View,
    private val headerBottom: () -> Int
) : AgentEdgeGlow,
    Choreographer.FrameCallback {
    private val shader = AgentEdgeGlowShaders.obtain()
    private val paint = Paint().apply { shader = this@AgentEdgeGlowRenderer.shader }
    private val frontView = makeLayer(isFront = true)
    private val backView = makeLayer(isFront = false)
    private val strips = Array(4) { RectF() }
    private val hostLocation = IntArray(2)
    private val paneLocation = IntArray(2)
    private val hostVisibleRect = Rect()
    private val layoutListener = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
        invalidateParts()
    }
    private var startTime = AnimationUtils.currentAnimationTimeMillis()

    // How far the fade has gone, in ms, as of its last frame, and when that frame was. Each frame moves it on by at
    // most `MAX_FADE_STEP_MS`, so a stall, such as the device compiling the shader for its first draw, delays the fade
    // rather than skipping it.
    private var fadeElapsed = 0f
    private var fadeFrameTime = 0L
    private var fadeFrom = 0f
    private var fadeTarget = 0f
    private var lastDrawnFrameNanos = 0L
    private var isFrameScheduled = false
    private var isAttached = true
    private var isShaderWarm = false
    private var isWarmUpDue = false

    // Once the chat has opened, the shader is drawn once, unseen, so the device compiles it before the glow first shows
    private val warmUp = Runnable {
        isWarmUpDue = true
        backView.invalidate()
    }

    // Where the pane lies in the host and the size the strips were laid out for, in px, and the corner radius, in dp
    private val paneRect = Rect()
    private var stripsWidth = 0
    private var stripsHeight = 0
    private var cornerRadius = 0f

    init {
        pane.addView(
            backView,
            pane.indexOfChild(under),
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        pane.addOnLayoutChangeListener(layoutListener)
        host.postDelayed(warmUp, WARM_UP_DELAY_MS)
    }

    private val isMoving: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() && ValueAnimator.areAnimatorsEnabled()

    // Debug builds end each fade at once while system animations are off, to keep E2E runs fast
    private val isFadeAnimated: Boolean
        get() = !DEBUG_MODE || ValueAnimator.areAnimatorsEnabled()

    override fun setGlowing(isGlowing: Boolean) {
        val target = if (isGlowing) 1f else 0f
        if (!isAttached || fadeTarget == target) return
        if (isGlowing) placeFrontLayer()
        val now = AnimationUtils.currentAnimationTimeMillis()
        advanceFade(now)
        fadeFrom = computeOpacity()
        // A glow that comes back while it still fades out goes on from where its lights are
        if (isGlowing && fadeFrom <= 0f) startTime = now
        fadeTarget = target
        fadeElapsed = 0f
        invalidateParts()
        scheduleFrame(0L)
    }

    override fun hideAtOnce() {
        if (!isAttached) return
        fadeFrom = 0f
        fadeTarget = 0f
        Choreographer.getInstance().removeFrameCallback(this)
        isFrameScheduled = false
        invalidateParts()
    }

    override fun detach() {
        if (!isAttached) return
        isAttached = false
        host.removeCallbacks(warmUp)
        Choreographer.getInstance().removeFrameCallback(this)
        isFrameScheduled = false
        pane.removeOnLayoutChangeListener(layoutListener)
        host.removeView(frontView)
        pane.removeView(backView)
        frontView.background = null
        backView.background = null
        paint.shader = null
        AgentEdgeGlowShaders.recycle(shader)
    }

    override fun doFrame(frameTimeNanos: Long) {
        isFrameScheduled = false
        if (!isAttached) return
        advanceFade(AnimationUtils.currentAnimationTimeMillis())
        val isFading = computeOpacity() != fadeTarget
        if (!isFading && (fadeTarget == 0f || !isMoving)) {
            // A finished fade, or still lights, keep their last frame
            invalidateParts()
            return
        }
        // A chat on a tab page laid out beside the selected one is off screen while its window shows
        if (host.windowVisibility != View.VISIBLE || !host.getGlobalVisibleRect(hostVisibleRect)) {
            scheduleFrame(HIDDEN_WINDOW_CHECK_MS)
            return
        }
        // At most 60 frames a second, as on iOS. A frame due a little early still draws, so a 60 Hz display gets every
        // one.
        if (frameTimeNanos - lastDrawnFrameNanos >= MIN_FRAME_INTERVAL_NANOS) {
            lastDrawnFrameNanos = frameTimeNanos
            invalidateParts()
        }
        scheduleFrame(0L)
    }

    private fun scheduleFrame(delayMs: Long) {
        if (isFrameScheduled) return
        isFrameScheduled = true
        Choreographer.getInstance().postFrameCallbackDelayed(this, delayMs)
    }

    private fun invalidateParts() {
        frontView.invalidate()
        backView.invalidate()
    }

    private fun makeLayer(isFront: Boolean) = View(host.context).apply {
        id = View.generateViewId()
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        background = Part(isFront)
    }

    /**
     * Puts the front layer right under the header's title and buttons, over the header's background, which the host
     * adds and orders once its screen is set up
     */
    private fun placeFrontLayer() {
        val index = host.indexOfChild(frontView)
        val isPlaced = index >= 0 &&
            (headerContent == null || host.getChildAt(index + 1) === headerContent)
        if (isPlaced) return
        if (index >= 0) host.removeView(frontView)
        val headerIndex = headerContent?.let(host::indexOfChild) ?: -1
        host.addView(frontView, headerIndex, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    private fun advanceFade(now: Long) {
        fadeElapsed += min(max(0L, now - fadeFrameTime), MAX_FADE_STEP_MS).toFloat()
        fadeFrameTime = now
    }

    // A constant rate, so reversing a fade midway takes only as long as the distance back
    private fun computeOpacity(): Float {
        val distance = abs(fadeTarget - fadeFrom)
        if (distance == 0f || !isFadeAnimated) return fadeTarget
        val duration = if (fadeTarget > fadeFrom) FADE_IN_DURATION_MS else FADE_OUT_DURATION_MS
        val progress = (fadeElapsed / duration) / distance
        return fadeFrom + (fadeTarget - fadeFrom) * min(1f, progress)
    }

    /** The part over the header's background, in the host, or the one under the composer, in the pane */
    private fun drawPart(canvas: Canvas, isFront: Boolean) {
        val now = AnimationUtils.currentAnimationTimeMillis()
        val value = computeOpacity().coerceIn(0f, 1f)
        // Eased at both ends, so the glow neither pops in nor cuts off
        val shown = value * value * (3f - 2f * value)
        if (shown <= 0f && !isFront && isWarmUpDue && !isShaderWarm && updateGeometry()) {
            // A pixel of the strips with nothing in it: the paint stays opaque, so the draw isn't skipped
            isShaderWarm = true
            canvas.save()
            canvas.translate(-backView.left.toFloat(), -backView.top.toFloat())
            canvas.clipRect(0f, 0f, 1f, 1f)
            drawStrips(canvas, now, 0f)
            canvas.restore()
        }
        if (shown <= 0f || !updateGeometry()) return
        // The header's bottom, from the pane's top
        val split = (headerBottom() - paneRect.top).toFloat()
        canvas.save()
        if (isFront) {
            canvas.translate(
                (paneRect.left - frontView.left).toFloat(),
                (paneRect.top - frontView.top).toFloat()
            )
            canvas.clipRect(0f, 0f, paneRect.width().toFloat(), split)
        } else {
            canvas.translate(-backView.left.toFloat(), -backView.top.toFloat())
            canvas.clipRect(0f, split, paneRect.width().toFloat(), paneRect.height().toFloat())
        }
        drawStrips(canvas, now, shown)
        canvas.restore()
    }

    private fun drawStrips(canvas: Canvas, now: Long, opacity: Float) {
        val density = host.resources.displayMetrics.density
        // The motion repeats over its period, as in the shader, so the time wraps without a jump
        val time = if (isMoving) ((now - startTime) % MOTION_PERIOD_MS) / MS_PER_SECOND else 0f
        val blue = AgentGlowPalette.glowBlue
        val violet = AgentGlowPalette.glowViolet
        shader.setFloatUniform("size", stripsWidth / density, stripsHeight / density)
        shader.setFloatUniform("density", density)
        shader.setFloatUniform("radius", cornerRadius)
        shader.setFloatUniform("time", time)
        shader.setFloatUniform("opacity", opacity)
        shader.setFloatUniform("lightsHeight", LIGHTS_HEIGHT)
        shader.setFloatUniform(
            "blueColor",
            Color.red(blue) / MAX_CHANNEL,
            Color.green(blue) / MAX_CHANNEL,
            Color.blue(blue) / MAX_CHANNEL
        )
        shader.setFloatUniform(
            "purpleColor",
            Color.red(violet) / MAX_CHANNEL,
            Color.green(violet) / MAX_CHANNEL,
            Color.blue(violet) / MAX_CHANNEL
        )
        for (strip in strips) {
            if (!strip.isEmpty) canvas.drawRect(strip, paint)
        }
    }

    /** Lays the strips out for where the pane is now, false while it has no size */
    private fun updateGeometry(): Boolean {
        host.getLocationInWindow(hostLocation)
        pane.getLocationInWindow(paneLocation)
        val left = paneLocation[0] - hostLocation[0]
        val top = paneLocation[1] - hostLocation[1]
        paneRect.set(left, top, left + pane.width, top + pane.height)
        if (paneRect.isEmpty) return false
        val density = host.resources.displayMetrics.density
        val isFullWindow = paneRect.left == 0 && paneRect.top == 0 &&
            paneRect.right == host.width && paneRect.bottom == host.height
        val radius = (if (isFullWindow) getDisplayCornerRadius() else PANE_RADIUS.dp) / density
        val width = paneRect.width()
        val height = paneRect.height()
        if (width == stripsWidth && height == stripsHeight && radius == cornerRadius) return true
        stripsWidth = width
        stripsHeight = height
        cornerRadius = radius
        // Deep enough to cover the band also where it curves in along a rounded corner: the band's
        // inner edge is a quarter circle of radius `cornerRadius - GLOW_DEPTH`, reaching furthest
        // on the diagonal
        val innerRadius = max(0f, cornerRadius - GLOW_DEPTH)
        val cornerDepth = cornerRadius - innerRadius * DIAGONAL
        val w = width.toFloat()
        val h = height.toFloat()
        val depth = min((ceil(max(GLOW_DEPTH, cornerDepth)) + 2f) * density, h)
        val bottomDepth = min(max(depth, LIGHTS_HEIGHT * density), h / 2f)
        val sideBottom = max(depth, h - bottomDepth)
        strips[0].set(0f, 0f, w, depth)
        strips[1].set(max(0f, w - depth), depth, w, sideBottom)
        strips[2].set(0f, max(0f, h - bottomDepth), w, h)
        strips[3].set(0f, depth, min(depth, w), sideBottom)
        return true
    }

    // The screen's corner rounding in px, when the pane fills the window
    private fun getDisplayCornerRadius(): Float {
        val root = host.rootView
        val insets = root.rootWindowInsets ?: host.rootWindowInsets ?: return 0f
        // Insets can reserve system-bar rows while this pane still occupies the full display width.
        if (hostLocation[0] != 0 || host.width != root.width) return 0f
        var radius = 0
        for (position in CORNER_POSITIONS) {
            radius = max(radius, insets.getRoundedCorner(position)?.radius ?: 0)
        }
        return radius.toFloat()
    }

    private inner class Part(private val isFront: Boolean) : Drawable() {
        override fun draw(canvas: Canvas) = drawPart(canvas, isFront)

        override fun setAlpha(alpha: Int) = Unit

        override fun setColorFilter(colorFilter: ColorFilter?) = Unit

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    companion object {
        // The motion repeats every 24 s, as in the shader
        const val MOTION_PERIOD_MS = 24_000L
        const val MS_PER_SECOND = 1000f

        // The glow comes in slowly and goes a little faster, each eased at both ends
        const val FADE_IN_DURATION_MS = 700f
        const val FADE_OUT_DURATION_MS = 400f
        const val HIDDEN_WINDOW_CHECK_MS = 500L

        // About two frames at 60 Hz
        const val MAX_FADE_STEP_MS = 34L
        const val MIN_FRAME_INTERVAL_NANOS = 1_000_000_000L / 60 - 2_000_000L

        // Past a chat's opening transition
        const val WARM_UP_DELAY_MS = 1000L
        const val MAX_CHANNEL = 255f

        // In dp: the shader draws the edge's light up to 32 dp in from the rounded edge, and the drifting lights reach
        // 150 dp up from the bottom, behind the composer. A pane short of the window rounds its corners by 20 dp.
        const val GLOW_DEPTH = 32f
        const val LIGHTS_HEIGHT = 150f
        const val PANE_RADIUS = 20f
        const val DIAGONAL = 0.7071f

        val CORNER_POSITIONS = intArrayOf(
            RoundedCorner.POSITION_TOP_LEFT,
            RoundedCorner.POSITION_TOP_RIGHT,
            RoundedCorner.POSITION_BOTTOM_RIGHT,
            RoundedCorner.POSITION_BOTTOM_LEFT
        )

        // iOS's `AgentEdgeGlow.metal`, in dp
        const val SHADER = """
            uniform float2 size;
            uniform float density;
            uniform float radius;
            uniform float time;
            uniform float opacity;
            uniform float lightsHeight;
            uniform float3 blueColor;
            uniform float3 purpleColor;

            const float PI = 3.14159265;
            const float HALF_PI = 1.57079633;

            // The motion repeats every PERIOD seconds: every stretch and light goes round a whole number of times in
            // it, so the time can wrap without a jump
            const float PERIOD = 24.0;
            // The edge's light reaches this far in, and fades out over the last dp of it
            const float DEPTH = 32.0;

            float roundedRectDistance(float2 p, float2 halfSize, float r) {
                float2 q = abs(p) - halfSize + r;
                return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
            }

            // Where along the pane's border the point of it nearest to local lies, in dp clockwise from the middle
            // of the top edge, on a border total dp long
            float edgeAlong(float2 local, float2 halfSize, float r, float total) {
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
                // Strictly within the straight part, so that with square corners a point of a side stays on the side
                if (abs(border.x) < inner.x) {
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

            // A bright stretch of the edge that goes round loops times a period, from start of the way round, sigma
            // dp long on either side
            float stretch(float along, float total, float start, float loops, float sigma) {
                float centre = fract(start + loops * time / PERIOD) * total;
                float d = abs(fract((along - centre) / total + 0.5) - 0.5) * total;
                return exp(-d * d / (2.0 * sigma * sigma));
            }

            // A soft light spreading over sigma dp
            float glowLight(float2 xy, float2 centre, float sigma) {
                float2 d = xy - centre;
                return exp(-dot(d, d) / (2.0 * sigma * sigma));
            }

            // A slow sway that repeats cycles times a period
            float sway(float cycles, float phase) {
                return sin(2.0 * PI * cycles * time / PERIOD + phase);
            }

            half4 main(float2 position) {
                float2 xy = position / density;
                float2 halfSize = size * 0.5;
                float2 local = xy - halfSize;
                float edgeDistance = roundedRectDistance(local, halfSize, radius);
                // Nothing shows past the rounded edge, which is smoothed over a pixel
                float edge = clamp(0.5 - edgeDistance * density, 0.0, 1.0);
                float inset = max(-edgeDistance, 0.0);
                float fromBottom = size.y - xy.y;
                if (edge <= 0.0 || (inset >= DEPTH && fromBottom >= lightsHeight)) {
                    return half4(0.0);
                }

                float3 color = float3(0.0);
                float alpha = 0.0;
                if (inset < DEPTH) {
                    float2 inner = max(halfSize - radius, 0.0);
                    float total = 4.0 * (inner.x + inner.y + HALF_PI * radius);
                    float along = edgeAlong(local, halfSize, radius, total);
                    // Short stretches, each at its own speed, some going the other way
                    float blue = stretch(along, total, 0.0, 7.0, 72.0) +
                        0.8 * stretch(along, total, 0.55, -4.0, 88.0) +
                        0.7 * stretch(along, total, 0.2, 9.0, 52.0);
                    float purple = 0.9 * stretch(along, total, 0.3, 5.0, 64.0) +
                        0.8 * stretch(along, total, 0.8, -3.0, 80.0);
                    float stretches = blue + purple;

                    float down = clamp(xy.y / size.y, 0.0, 1.0);
                    // As bright near either side
                    float fromSide = min(xy.x, size.x - xy.x);
                    float nearSide = exp(-max(fromSide, 0.0) / 120.0);
                    float base = 0.3 + 0.45 * down * down + 0.175 * nearSide;
                    float intensity = base * (0.25 + 1.5 * stretches);

                    // Between the stretches the edge keeps a little of both colours
                    float3 stretchColor = (blueColor * blue + purpleColor * purple +
                        0.06 * (blueColor + purpleColor)) / (stretches + 0.12);
                    float core = exp(-inset * inset / (2.0 * 0.9 * 0.9));
                    float bloom = exp(-inset / 4.5);
                    float haze = 0.4 * exp(-inset / 13.0);
                    float fade = 1.0 - smoothstep(0.6 * DEPTH, DEPTH, inset);
                    float glow = (bloom + haze) * intensity;
                    float coreAlpha = clamp(core * intensity, 0.0, 1.0);
                    float glowAlpha = clamp(glow * fade, 0.0, 0.9);
                    // The core whitens the brighter it is, and so does the bloom at its brightest
                    float coreWhite = clamp(0.5 + 0.4 * intensity, 0.0, 0.92);
                    float3 coreColor = mix(stretchColor, float3(1.0), coreWhite);
                    float glowWhite = clamp((glow - 0.9) * 0.5, 0.0, 0.5);
                    float3 glowColor = mix(stretchColor, float3(1.0), glowWhite);
                    color = coreColor * coreAlpha + glowColor * glowAlpha * (1.0 - coreAlpha);
                    alpha = coreAlpha + glowAlpha * (1.0 - coreAlpha);
                }
                if (fromBottom < lightsHeight) {
                    // Large faint lights a little inside the screen, swaying under the edge's light, each a few times
                    // a period, at half strength under and around the composer. The two side ones mirror each other in
                    // place, size and strength, so neither side is favoured.
                    float2 first = float2(
                        size.x * (0.28 + 0.19 * sway(2.0, 0.0)),
                        size.y - lightsHeight * (0.45 + 0.08 * sway(4.0, 1.0))
                    );
                    float2 second = float2(
                        size.x * (0.72 + 0.19 * sway(2.0, 2.0)),
                        size.y - lightsHeight * (0.38 + 0.08 * sway(6.0, 2.5))
                    );
                    float2 third = float2(
                        size.x * (0.5 + 0.32 * sway(4.0, 4.0)),
                        size.y - lightsHeight * (0.58 + 0.06 * sway(2.0, 3.0))
                    );
                    float firstLight = glowLight(xy, first, 0.52 * lightsHeight);
                    float secondLight = glowLight(xy, second, 0.52 * lightsHeight);
                    float thirdLight = glowLight(xy, third, 0.62 * lightsHeight);
                    float blueLight = 0.21 * firstLight + 0.15 * thirdLight;
                    float purpleLight = 0.21 * secondLight;
                    float fade = 1.0 - smoothstep(0.5 * lightsHeight, lightsHeight, fromBottom);
                    float lightsAlpha = 0.5 * clamp((blueLight + purpleLight) * fade, 0.0, 0.35);
                    float3 lightsColor = (blueColor * blueLight + purpleColor * purpleLight) /
                        max(blueLight + purpleLight, 0.0001);
                    color += lightsColor * lightsAlpha * (1.0 - alpha);
                    alpha += lightsAlpha * (1.0 - alpha);
                }
                return half4(float4(color, alpha) * (opacity * edge));
            }
        """
    }
}
