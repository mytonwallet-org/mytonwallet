package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt
import kotlin.math.tanh

internal fun unit(v: Double) = v.coerceIn(0.0, 1.0)
internal fun smooth(v: Double): Double {
    val t = unit(v)
    return t * t * (3 - 2 * t)
}
internal fun quintic(v: Double): Double {
    val t = unit(v)
    return t * t * t * (t * (t * 6 - 15) + 10)
}
internal fun fract(v: Double) = v - floor(v)
internal fun mix(a: Double, b: Double, t: Double) = a + (b - a) * t

internal class CriticalSpring(private val count: Int) {
    val value = DoubleArray(count)
    private val velocity = DoubleArray(count)
    fun reset() {
        value.fill(0.0)
        velocity.fill(0.0)
    }
    fun advance(target: DoubleArray, rate: Double, dt: Double) {
        val decay = exp(-rate * dt)
        for (i in 0 until count) {
            val offset = value[i] - target[i]
            val term = velocity[i] + rate * offset
            value[i] = target[i] + (offset + term * dt) * decay
            velocity[i] = (velocity[i] - rate * term * dt) * decay
        }
    }
}

internal class TouchGlow {
    private val value = doubleArrayOf(.5, .5, 0.0)
    private val velocity = DoubleArray(3)
    private val target = doubleArrayOf(.5, .5, 0.0)
    private var held = 0.0
    private var appearance = 0.0
    private var remainder = 0.0
    var following = false
        private set
    val x get() = ((value[0] - .5) * 2 * 1.15).coerceIn(-1.0, 1.0)
    val y get() = ((value[1] - .5) * 2 * 1.15).coerceIn(-1.0, 1.0)
    val opacity get() = unit(value[2]) * appearance
    fun press(x: Double, y: Double, began: Boolean) {
        if (began || !following) {
            held = 0.0
            appearance = 0.0
            value[2] = 0.0
            velocity[2] = 0.0
        }
        following = true
        target[0] = (x.coerceIn(-1.0, 1.0) + 1) / 2
        target[1] = (y.coerceIn(-1.0, 1.0) + 1) / 2
        target[2] =
            1.0
    }
    fun release() {
        following = false
        target[0] = .5
        target[1] = .5
        target[2] = 0.0
    }
    fun reset() {
        release()
        target.copyInto(value)
        velocity.fill(0.0)
        held = 0.0
        appearance = 0.0
        remainder =
            0.0
    }
    fun advance(dt: Double) {
        remainder += min(.1, dt)
        val step = 1.0 / 60
        while (remainder + 1e-12 >= step) {
            remainder = max(0.0, remainder - step)
            if (following) {
                held += step
                appearance = smooth((held - .15) / .67)
            }
            for (i in 0..2) {
                velocity[i] =
                    (velocity[i] + (target[i] - value[i]) * (if (following) .066 else .01)) *
                    (if (following) .75 else .94)
                value[i] += velocity[i]
            }
        }
        if ((!following || appearance == 1.0) &&
            (0..2).all { abs(value[it] - target[it]) <= .0002 && abs(velocity[it]) <= .0002 }
        ) {
            target.copyInto(value)
            velocity.fill(0.0)
        }
    }
}

internal data class Attitude(val x: Double, val y: Double, val z: Double, val w: Double) {
    fun inverse() = Attitude(-x, -y, -z, w)
    operator fun times(b: Attitude) = Attitude(
        w * b.x + x * b.w + y * b.z - z * b.y,
        w * b.y - x * b.z + y * b.w + z * b.x,
        w * b.z + x * b.y - y * b.x + z * b.w,
        w * b.w - x * b.x - y * b.y - z * b.z
    )
    fun positive() = if (w < 0) Attitude(-x, -y, -z, -w) else this
}

internal class CardSurfaceMotion(val shineEnabled: Boolean = false) {
    val glow = TouchGlow()
    private val gyro = CriticalSpring(2)
    private var reference: Attitude? = null
    private var rotation = -1
    private val targetGyro = DoubleArray(2)
    private var gramTarget = 0.0
    private var gramFadeTarget = 0.0
    private var gram = 0.0
    private var gramFade = 0.0
    var lightX = 0.0
        private set
    var lightY = 0.0
        private set
    var activity = 0.0
        private set
    private var holdRemaining = 0.0
    private var fadeElapsed = 0.0
    private var fadeStart = 0.0
    var pressed = false
        private set
    var touchX = 0.0
        private set
    var touchY = 0.0
        private set
    var pressX = 0.0
    var pressY = 0.0
    var engagement = 0.0
    var lineTime = 0.0
        private set
    var blobTime = 0.0
        private set
    private var boost = 0.0
    fun press(x: Double, y: Double, began: Boolean) {
        touchX = x.coerceIn(-1.0, 1.0)
        touchY = y.coerceIn(-1.0, 1.0)
        pressed = true
        glow.press(touchX, touchY, began)
    }
    fun release() {
        pressed = false
        glow.release()
    }
    fun clearTouch() {
        release()
        glow.reset()
        pressX = 0.0
        pressY = 0.0
        engagement = 0.0
        activity = 0.0
        holdRemaining = 0.0
        fadeElapsed = 0.0
    }
    fun resetInput() {
        release()
        glow.reset()
        gyro.reset()
        reference = null
        rotation = -1
        lightX = 0.0
        lightY = 0.0
        activity = 0.0
        holdRemaining = 0.0
        fadeElapsed = 0.0
        gram = 0.0
        gramFade = 0.0
        gramTarget = 0.0
        gramFadeTarget = 0.0
        targetGyro.fill(0.0)
        pressX = 0.0
        pressY = 0.0
        engagement = 0.0
    }
    fun advance(
        dt: Double,
        sample: Attitude?,
        orientation: Int,
        angularSpeed: Double,
        advanceBackgroundClock: Boolean = true
    ) {
        if (sample != null) {
            if (reference == null || rotation != orientation) {
                reference = sample
                rotation = orientation
            }
            val q = (reference!!.inverse() * sample).positive()
            val horizontal =
                2 * asin(q.y.coerceIn(-1.0, 1.0))
            val vertical = 2 * asin(q.x.coerceIn(-1.0, 1.0))
            val (roll, pitch) = when (orientation) {
                1 -> Pair(vertical, -horizontal)
                2 -> Pair(-horizontal, -vertical)
                3 -> Pair(-vertical, horizontal)
                else -> Pair(horizontal, vertical)
            }
            targetGyro[0] = tanh(roll * 1.5 / .65)
            targetGyro[1] = tanh(pitch * 1.5 / .65)
            val radius = sqrt(q.x * q.x + q.y * q.y + q.z * q.z)
            val angle =
                2 * atan2(radius, max(0.0, q.w))
            val k = if (radius > 1e-9) angle / radius else 0.0
            val vx = q.x * k
            val vy = q.y * k
            val vz = q.z * k
            val (ax, ay) = when (orientation) {
                1 -> Pair(-vy, vx)
                2 -> Pair(-vx, -vy)
                3 -> Pair(vy, -vx)
                else -> Pair(vx, vy)
            }
            gramFadeTarget = smooth((angle - 100 * PI / 180) / (60 * PI / 180))
            gramTarget =
                (ay - ax - vz) * (1 - gramFadeTarget)
        }
        gyro.advance(targetGyro, 18.0, dt)
        val lightAmount = 1 - exp(-dt / .12)
        lightX += ((if (pressed) touchX else gyro.value[0]) - lightX) * lightAmount
        lightY += ((if (pressed) touchY else gyro.value[1]) - lightY) * lightAmount
        val tau = .15 - .08 * min(1.0, abs(gramTarget - gram) / (12 * PI / 180))
        val gramAmount = 1 - exp(-dt / tau)
        gram += (gramTarget - gram) * gramAmount
        gramFade += (gramFadeTarget - gramFade) * gramAmount
        val touchActivity = if (shineEnabled) unit(engagement) else 0.0
        val targetActivity = max(smooth((angularSpeed - .08) / .52), touchActivity)
        if (targetActivity > 0) {
            holdRemaining = 1.0
            fadeElapsed = 0.0
            if (targetActivity >
                activity
            ) {
                activity +=
                    (targetActivity - activity) * (
                        1 - exp(
                            -dt / (if (touchActivity > 0) .08 else .16)
                        )
                        )
            }
        } else if (activity > 0) {
            val fading = max(0.0, dt - holdRemaining)
            holdRemaining = max(0.0, holdRemaining - dt)
            if (fading >
                0
            ) {
                if (fadeElapsed ==
                    0.0
                ) {
                    fadeStart = activity
                }
                fadeElapsed = min(2.0, fadeElapsed + fading)
                activity =
                    fadeStart * (1 - smooth(fadeElapsed / 2))
            }
        }
        glow.advance(dt)
        if (advanceBackgroundClock) advanceClock(dt, engagement, activity)
    }

    fun advanceClock(dt: Double, press: Double, activity: Double) {
        val targetBoost = unit(max(press, activity))
        val response = if (targetBoost >
            boost
        ) {
            .12
        } else {
            .65
        }
        val decay = exp(-dt / response)
        val integrated =
            targetBoost * dt + (boost - targetBoost) * response * (1 - decay)
        lineTime += dt * 1.55
        blobTime += dt + 2 * integrated
        boost = targetBoost + (boost - targetBoost) * decay
    }
    fun gramAngle(aspect: Double) = PI * tanh((gram + (-aspect * pressX + pressY) * PI / 3) / PI)
    val gramEnergy get() = 1 - unit(gramFade)
}
