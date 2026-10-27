package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.sin

/** Critically damped card pose in normalized touch coordinates and seconds. */
internal class CardPressMotion {
    private val value = DoubleArray(3)
    private val velocity = DoubleArray(3)
    private val target = DoubleArray(3)

    val engagement: Float get() = value[2].toFloat()
    val lightX: Float get() = (sin(value[0] * ANGLE) / LIGHT_REFERENCE).toFloat()
    val lightY: Float
        get() = (sin(value[1] * ANGLE) * cos(value[0] * ANGLE) / LIGHT_REFERENCE).toFloat()

    val isSettled: Boolean
        get() = value.indices.all {
            abs(value[it] - target[it]) < 0.00015 && abs(velocity[it]) < 0.002
        }

    fun press(x: Double, y: Double) {
        val clampedX = x.coerceIn(-1.0, 1.0)
        val clampedY = y.coerceIn(-1.0, 1.0)
        val length = max(1.0, hypot(clampedX, clampedY))
        target[0] = clampedX / length
        target[1] = clampedY / length
        target[2] = 1.0
    }

    fun release() {
        target.fill(0.0)
    }

    fun reset() {
        value.fill(0.0)
        velocity.fill(0.0)
        target.fill(0.0)
    }

    fun advance(dt: Double) {
        if (dt <= 0.0) return
        val frequency = if (target[2] > 0.0) 28.0 else 13.9529
        val decay = exp(-frequency * dt)
        for (axis in value.indices) {
            val offset = value[axis] - target[axis]
            val term = velocity[axis] + frequency * offset
            value[axis] = target[axis] + (offset + term * dt) * decay
            velocity[axis] = (velocity[axis] - term * frequency * dt) * decay
        }
        if (isSettled) {
            target.copyInto(value)
            velocity.fill(0.0)
        }
    }

    /** Projects the card plane after rotation, Z push, perspective and XY scale. */
    fun writeProjection(
        width: Int,
        height: Int,
        density: Float,
        out: FloatArray,
        cardWidth: Int = width
    ) {
        if (value.all { it == 0.0 }) {
            out.fill(0f)
            out[0] = 1f
            out[4] = 1f
            out[8] = 1f
            return
        }
        val rx = -value[1] * ANGLE
        val ry = value[0] * ANGLE
        val sinX = sin(rx)
        val cosX = cos(rx)
        val sinY = sin(ry)
        val cosY = cos(ry)
        val scale = 1.0 - 0.015 * value[2]
        val camera = max(650.0 * density, cardWidth * 2.5)
        val a = scale * cosY
        val d = scale * sinY * sinX
        val e = scale * cosX
        val g = scale * sinY * cosX / camera
        val h = -scale * sinX / camera
        val i = 1.0 + 6.0 * value[2] * density / camera
        val cx = width / 2.0
        val cy = height / 2.0
        val denominator = i - g * cx - h * cy
        out[0] = (a + cx * g).toFloat()
        out[1] = (cx * h).toFloat()
        out[2] = (cx * denominator - a * cx).toFloat()
        out[3] = (d + cy * g).toFloat()
        out[4] = (e + cy * h).toFloat()
        out[5] = (cy * denominator - d * cx - e * cy).toFloat()
        out[6] = g.toFloat()
        out[7] = h.toFloat()
        out[8] = denominator.toFloat()
    }

    private companion object {
        const val ANGLE = 12.0 * Math.PI / 180.0
        val LIGHT_REFERENCE = sin(Math.PI / 15.0)
    }
}
