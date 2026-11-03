package org.mytonwallet.app_air.uicomponents.widgets.particles

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.view.View
import androidx.core.graphics.PathParser
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.random.Random
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.xmlpull.v1.XmlPullParser

class WelcomeParticleView(context: Context) : View(context) {
    var particleColor: Int = 0xFF0098EA.toInt()
        set(value) {
            field = value
            paint.color = value
            invalidate()
        }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val starPath = loadStarPath(context)
    private val particles = placements.indices.map {
        Particle(it.toFloat() / placements.size)
    }.toMutableList()
    private var lastTime = 0L
    private var timeUntilNext = 0f
    private var nextIndex = 0
    private var speed = 1f
    private var density = 1f
    private var isPressedOnLogo = false
    private var isHoveredOnLogo = false
    private var boostUntil = 0L
    private var framePosted = false
    private val animationFrame = object : Runnable {
        override fun run() {
            framePosted = false
            if (!canAnimate()) {
                lastTime = 0
                return
            }
            val now = SystemClock.uptimeMillis()
            val elapsed = if (lastTime == 0L) 0f else min(0.05f, (now - lastTime) / 1000f)
            lastTime = now
            advance(elapsed, now)
            invalidate()
            updatePlayback()
        }
    }

    var isRenderingEnabled = true
        set(value) {
            field = value
            resetInteraction()
            updatePlayback()
            invalidate()
        }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        particleColor = particleColor
    }

    fun setInteraction(pressed: Boolean, hovered: Boolean) {
        if (pressed && !isPressedOnLogo) {
            boostUntil = SystemClock.uptimeMillis() + 180
            if (animationsAllowed()) emitBurst()
        }
        isPressedOnLogo = pressed
        isHoveredOnLogo = hovered
        invalidate()
    }

    fun boost() {
        boostUntil = SystemClock.uptimeMillis() + 180
        invalidate()
    }

    private fun emitBurst() {
        repeat(5) {
            val particle = Particle(0f, isBurst = true)
            val index = particles.indexOfFirst { it.isWaiting }
            if (index >= 0) {
                particles[index] = particle
            } else if (particles.size < placements.size * 3) {
                particles.add(particle)
            }
        }
    }

    override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        super.onWindowFocusChanged(hasWindowFocus)
        if (!hasWindowFocus) resetInteraction()
        updatePlayback()
        invalidate()
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        resetInteraction()
        updatePlayback()
        if (visibility == VISIBLE) invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updatePlayback()
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        if (isAttachedToWindow) updatePlayback()
    }

    override fun onDetachedFromWindow() {
        resetInteraction()
        removeCallbacks(animationFrame)
        framePosted = false
        super.onDetachedFromWindow()
    }

    private fun resetInteraction() {
        isPressedOnLogo = false
        isHoveredOnLogo = false
        boostUntil = 0
        speed = 1f
        density = 1f
        lastTime = 0
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val animated = animationsAllowed()

        val density = resources.displayMetrics.density
        canvas.save()
        canvas.translate(width / 2f - 161 * density, height / 2f - 102 * density)
        canvas.scale(density, density)
        repeat(if (animated) particles.size else placements.size) { index ->
            val point = placements[index % placements.size]
            val particle = particles[index]
            val progress = particle.progress
            val distance = particle.radius + 131.5f * particle.travel * progress *
                (1 + 3 * exp(-3 * progress))
            val x = if (animated) 161 + cos(particle.angle) * distance else point[0] + point[2] / 2
            val y = if (animated) 112 + sin(particle.angle) * distance else point[1] + point[2] / 2
            val edgeFade = if (animated) {
                (minOf(x + 32, 354 - x, y + 32, 236 - y) / 50).coerceIn(0f, 1f)
            } else {
                1f
            }
            val size = point[2]
            canvas.save()
            canvas.translate(x, y)
            canvas.scale(size / 10, size / 10)
            canvas.translate(-5f, -5f)
            paint.alpha =
                (
                    255 * 0.8f * min(
                        1f,
                        (if (animated) particle.baseOpacity else point[3])
                    ) * (if (animated) particle.opacity else 1f) * edgeFade
                    ).toInt()
            canvas.drawPath(starPath, paint)
            canvas.restore()
        }
        canvas.restore()
        updatePlayback()
    }

    private fun animationsAllowed(): Boolean {
        val systemAnimations = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ValueAnimator.areAnimatorsEnabled()
        } else {
            Settings.Global.getFloat(
                context.contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE,
                1f
            ) >
                0
        }
        return systemAnimations && WGlobalStorage.getAreAnimationsActive()
    }

    private fun canAnimate() = isRenderingEnabled && isAttachedToWindow && isShown &&
        windowVisibility == VISIBLE && animationsAllowed()

    private fun updatePlayback() {
        if (canAnimate()) {
            if (!framePosted) {
                framePosted = true
                postOnAnimation(animationFrame)
            }
        } else {
            removeCallbacks(animationFrame)
            framePosted = false
            lastTime = 0
        }
    }

    private fun advance(elapsed: Float, now: Long) {
        val target = if (isPressedOnLogo ||
            now < boostUntil
        ) {
            6f
        } else if (isHoveredOnLogo) {
            3f
        } else {
            1f
        }
        val smoothing = if (target > speed) 0.18f else 0.55f
        speed += (target - speed) * (1 - exp(-elapsed / smoothing))
        if (kotlin.math.abs(target - speed) < 0.005f) speed = target
        val targetDensity = if (isPressedOnLogo ||
            now < boostUntil
        ) {
            3f
        } else if (isHoveredOnLogo) {
            2f
        } else {
            1f
        }
        density += (targetDensity - density) * (1 - exp(-elapsed / smoothing))
        val targetCount = (placements.size * density.coerceIn(1f, 3f)).roundToInt()
        while (particles.size < targetCount) {
            particles.add(Particle(0f).apply { isWaiting = true })
        }
        particles.forEach { it.advance(elapsed, speed) }
        timeUntilNext -= elapsed
        if (timeUntilNext > 0) return
        if (particles.count { !it.isWaiting } >= targetCount) {
            timeUntilNext = 0f
            return
        }
        for (offset in particles.indices) {
            val index = (nextIndex + offset) % particles.size
            if (!particles[index].isWaiting) continue
            particles[index] = Particle(0f)
            nextIndex = (index + 1) % particles.size
            timeUntilNext = (timeUntilNext + (2.6f / speed + 1) / targetCount).coerceAtLeast(0f)
            return
        }
    }

    private class Particle(phase: Float, val isBurst: Boolean = false) {
        val angle = Random.nextFloat() * Math.PI.toFloat() * 2
        val radius = if (isBurst) 5 + Random.nextFloat() * 45 else 55 + Random.nextFloat() * 15
        val travel = (0.5f + Random.nextFloat() * 0.5f) * if (isBurst) 1f else 0.45f
        val baseOpacity = 0.1f + Random.nextFloat() * 0.6f
        val duration = if (isBurst) 3f else 3 + Random.nextFloat() * 2
        var progress = phase
        var opacity = if (phase > 0.65f) {
            1 - ease((phase - 0.65f) / 0.35f)
        } else {
            ease(phase * 4 / 0.25f)
        }
        var isWaiting = false
        private var fadeInAge = min(phase * 4, 0.25f)
        private var fadeOutAge: Float? = if (phase > 0.65f) (phase - 0.65f) / 0.35f else null
        private var fadeOutOpacity = 1f
        private var fadeOutStart = 0.65f
        private var fadeOutSlope = 1f

        fun advance(elapsed: Float, speed: Float) {
            if (isWaiting) return
            val age = fadeOutAge
            if (age != null) {
                val nextAge = age + elapsed
                fadeOutAge = nextAge
                val time = min(1f, nextAge)
                val travel = time + (fadeOutSlope - 1) * time * (1 - time).pow(2)
                progress = fadeOutStart + (1 - fadeOutStart) * travel
                opacity = fadeOutOpacity * (1 - ease(time))
                if (time == 1f) {
                    progress = 0f
                    fadeInAge = 0f
                    fadeOutAge = null
                    isWaiting = true
                }
            } else {
                progress = min(1f, progress + elapsed * speed / duration)
                fadeInAge += elapsed
                opacity = ease(fadeInAge / if (isBurst) 0.05f else 0.25f)
                if (progress >= 0.65f) {
                    fadeOutAge = 0f
                    fadeOutOpacity = opacity
                    fadeOutStart = progress
                    fadeOutSlope = min(3f, speed / (duration * (1 - progress)))
                }
            }
        }
    }

    companion object {
        private fun loadStarPath(context: Context): Path {
            context.resources.getXml(R.drawable.particle_welcome).use { parser ->
                while (parser.eventType != XmlPullParser.END_DOCUMENT) {
                    if (parser.eventType == XmlPullParser.START_TAG && parser.name == "path") {
                        return requireNotNull(
                            PathParser.createPathFromPathData(
                                parser.getAttributeValue(
                                    "http://schemas.android.com/apk/res/android",
                                    "pathData"
                                )
                            )
                        )
                    }
                    parser.next()
                }
            }
            error("Missing welcome particle path")
        }

        private fun ease(progress: Float): Float =
            (1 - cos(Math.PI.toFloat() * min(1f, progress))) / 2

        private val placements = arrayOf(
            floatArrayOf(27f, 65f, 10f, 0.3f), floatArrayOf(51f, 165f, 10f, 0.2f),
            floatArrayOf(288f, 64f, 10f, 0.3f), floatArrayOf(227f, 34f, 10f, 0.1f),
            floatArrayOf(303f, 131f, 6f, 0.2f), floatArrayOf(308f, 29f, 6f, 0.3f),
            floatArrayOf(54f, 0f, 6f, 0.4f), floatArrayOf(316f, 151f, 6f, 0.1f),
            floatArrayOf(310f, 198f, 6f, 0.4f), floatArrayOf(21f, 149f, 6f, 0.4f),
            floatArrayOf(65f, 119f, 6f, 0.2f), floatArrayOf(0f, 107f, 6f, 0.1f),
            floatArrayOf(67f, 41f, 15f, 0.4f), floatArrayOf(135f, 10f, 15f, 0.15f),
            floatArrayOf(10f, 11f, 15f, 0.1f), floatArrayOf(246f, 89f, 15f, 0.3f),
            floatArrayOf(262f, 137f, 15f, 0.2f), floatArrayOf(189f, 20f, 10f, 0.3f)
        )
    }
}
