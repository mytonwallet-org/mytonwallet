package org.mytonwallet.app_air.uicomponents.diamond

import kotlin.math.PI
import kotlin.math.abs
import kotlin.random.Random

internal class BlueDiamondMotion {
    var yaw = 0f
        private set
    var pitch = 0f
        private set
    private var animationStart = 0f
    private var fromYaw = 0f
    private var fromPitch = 0f
    private var toYaw = 0f
    private var toPitch = 0f
    private var phase = Phase.IDLE
    private var isPressed = false

    fun update(time: Float) {
        val elapsed = (time - animationStart).coerceAtLeast(0f)
        when (phase) {
            Phase.IDLE -> if (!isPressed && time >= 0.5f) {
                yaw =
                    fromYaw + 2 * PI.toFloat() * (((elapsed - 0.5f).coerceAtLeast(0f) / 10.54f) % 1)
            }

            Phase.TAP -> {
                val progress = (elapsed / 0.22f).coerceAtMost(1f)
                val shifted = progress - 1
                val ratio = 1 + shifted * shifted * shifted * shifted * shifted
                yaw = fromYaw + (toYaw - fromYaw) * ratio
                pitch = fromPitch + (toPitch - fromPitch) * ratio
                if (progress == 1f) release(time)
            }

            Phase.RELEASE -> {
                val progress = (elapsed / 0.6f).coerceAtMost(1f)
                val shifted = progress - 1
                val ratio = -shifted * shifted * (3 * shifted + 2)
                yaw = fromYaw * ratio
                pitch = fromPitch * ratio
                if (progress == 1f) {
                    phase = Phase.IDLE
                    fromYaw = yaw
                    animationStart = time - 0.5f
                }
            }

            Phase.DRAG -> Unit
        }
    }

    fun press() {
        isPressed = true
        phase = Phase.DRAG
    }

    fun drag(dx: Float, dy: Float) {
        yaw += dx * 0.5f * PI.toFloat() / 180
        pitch += dy * 0.05f * PI.toFloat() / 180
    }

    fun release(time: Float, tapX: Float? = null, tapY: Float? = null) {
        isPressed = false
        fromYaw = yaw
        fromPitch = pitch
        animationStart = time
        if (tapX != null && tapY != null && abs(yaw) <= 10 * PI.toFloat() / 180) {
            toYaw = tapX * (40 + Random.nextFloat() * 30) * PI.toFloat() / 180
            toPitch = tapY * (40 + Random.nextFloat() * 30) * PI.toFloat() / 180
            phase = Phase.TAP
        } else {
            phase = Phase.RELEASE
        }
    }

    private enum class Phase { IDLE, TAP, RELEASE, DRAG }
}
