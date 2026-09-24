package org.mytonwallet.app_air.uicomponents.commonViews

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

internal class CardLinearShineMotion {
    var position = 1.0
        private set
    var isAnimating = false
        private set

    private var direction = 1.0
    private var progress = 0.0
    private var rate = 1.0
    private var targetRate = 1.0
    private var pendingSweep: Pair<Double, Double>? = null
    private var lastTriggerDirection: Double? = null
    private var movement = 0.0
    private var previousPitch = 0.0
    private var previousRoll = 0.0
    private var idleTime = 0.0

    fun reset() {
        position = 1.0
        isAnimating = false
        direction = 1.0
        progress = 0.0
        rate = 1.0
        targetRate = 1.0
        pendingSweep = null
        lastTriggerDirection = null
        movement = 0.0
        previousPitch = 0.0
        previousRoll = 0.0
        idleTime = 0.0
    }

    fun copyFrom(other: CardLinearShineMotion) {
        position = other.position
        isAnimating = other.isAnimating
        direction = other.direction
        progress = other.progress
        rate = other.rate
        targetRate = other.targetRate
        pendingSweep = other.pendingSweep
        lastTriggerDirection = other.lastTriggerDirection
        movement = other.movement
        previousPitch = other.previousPitch
        previousRoll = other.previousRoll
        idleTime = other.idleTime
    }

    fun rebase(pitch: Double, roll: Double) {
        previousPitch = pitch
        previousRoll = roll
        movement = 0.0
        lastTriggerDirection = null
        idleTime = 0.0
    }

    fun press() {
        if (isAnimating) return
        movement = 0.0
        lastTriggerDirection = null
        idleTime = 0.0
        start(if (position >= 0) 1.0 else -1.0, 0.0)
    }

    fun advance(pitch: Double, roll: Double, dt: Double) {
        if (dt <= 0) return
        val pitchDelta = pitch - previousPitch
        val rollDelta = roll - previousRoll
        previousPitch = pitch
        previousRoll = roll
        val delta = pitchDelta * 0.89 - rollDelta * 0.68
        val speed = hypot(pitchDelta * 0.89, rollDelta * 0.68) / dt
        advanceAnimation(dt, speed)
        idleTime = if (hypot(pitchDelta, rollDelta) / dt < 0.035) idleTime + dt else 0.0
        if (idleTime >= 0.5) {
            movement = 0.0
            lastTriggerDirection = null
            return
        }
        movement += delta
        if (lastTriggerDirection != null && movement * lastTriggerDirection!! > 0) movement = 0.0
        val nextDirection = if (movement > 0) 1.0 else -1.0
        val threshold = 25.0 * Math.PI / 180
        if (abs(movement) + 1e-12 < threshold) return
        movement = 0.0
        lastTriggerDirection = nextDirection
        if (isAnimating) {
            if (pendingSweep == null) {
                pendingSweep = nextDirection to speed
            }
        } else {
            start(nextDirection, speed)
        }
    }

    private fun start(direction: Double, speed: Double) {
        this.direction = direction
        position = direction
        progress = 0.0
        rate = animationRate(speed)
        targetRate = rate
        isAnimating = true
    }

    private fun animationRate(speed: Double) = 1 + 1.5 * min(1.0, max(0.0, (speed - 0.35) / 2.15))

    private fun advanceAnimation(dt: Double, speed: Double) {
        if (!isAnimating) return
        targetRate = max(targetRate, animationRate(speed))
        val decay = exp(-dt / 0.08)
        progress += targetRate * dt + (rate - targetRate) * 0.08 * (1 - decay)
        rate = targetRate + (rate - targetRate) * decay
        if (progress >= 1) {
            position = -direction
            isAnimating = false
            pendingSweep?.let { (nextDirection, nextSpeed) ->
                pendingSweep = null
                start(nextDirection, nextSpeed)
            }
        } else {
            val eased = progress * progress * (3 - 2 * progress)
            position = direction * (1 - 2 * eased)
        }
    }
}
