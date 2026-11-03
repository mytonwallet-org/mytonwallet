package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * A damped oscillator stepped in closed form. `response` is its undamped period in seconds and `damping` its damping
 * ratio, as in Telegram's chat list swipe, whose motion this file ports.
 */
internal class AgentThreadSwipeSpring(var response: Double = 0.5, var damping: Double = 1.0) {
    var value = 0.0
    var velocity = 0.0
    var target = 0.0

    val isAtRest: Boolean get() = abs(value - target) < 0.001 && abs(velocity) < 0.01

    fun snap(to: Double) {
        value = to
        target = to
        velocity = 0.0
    }

    fun advance(deltaSeconds: Double) {
        if (deltaSeconds <= 0 || !deltaSeconds.isFinite()) return
        if (isAtRest) {
            snap(target)
            return
        }
        val frequency = 2 * PI / max(0.01, response)
        val ratio = max(0.01, damping)
        val offset = value - target
        val speed = velocity
        when {
            abs(ratio - 1) < 0.00001 -> {
                val decay = exp(-frequency * deltaSeconds)
                val slope = speed + frequency * offset
                value = target + (offset + slope * deltaSeconds) * decay
                velocity = (speed - frequency * slope * deltaSeconds) * decay
            }

            ratio < 1 -> {
                val decayRate = frequency * ratio
                val dampedFrequency = frequency * sqrt(1 - ratio * ratio)
                val decay = exp(-decayRate * deltaSeconds)
                val cosine = cos(dampedFrequency * deltaSeconds)
                val sine = sin(dampedFrequency * deltaSeconds)
                value =
                    target +
                    decay *
                    (offset * cosine + (speed + decayRate * offset) / dampedFrequency * sine)
                velocity = decay *
                    (
                        speed * cosine -
                            (decayRate * speed + frequency * frequency * offset) / dampedFrequency *
                            sine
                        )
            }

            else -> {
                val spread = sqrt(ratio * ratio - 1)
                val slowRate = -frequency * (ratio - spread)
                val fastRate = -frequency * (ratio + spread)
                val slowPart = (speed - fastRate * offset) / (slowRate - fastRate)
                val fastPart = offset - slowPart
                val slowDecay = exp(slowRate * deltaSeconds)
                val fastDecay = exp(fastRate * deltaSeconds)
                value = target + slowPart * slowDecay + fastPart * fastDecay
                velocity = slowPart * slowRate * slowDecay + fastPart * fastRate * fastDecay
            }
        }
    }
}

/** The geometry a swipe is measured against. Distances run from the row's trailing edge toward its leading edge. */
internal data class AgentThreadSwipeParameters(
    val width: Double = 0.0,
    val buttonWidth: Double = 48.0,
    val spacing: Double = 8.0,
    // From the row's trailing edge to the outermost action
    val outerInset: Double = 14.0,
    // From the innermost action to the row's content once open
    val innerInset: Double = 10.0,
    val count: Int = 0,
    val density: Double = 2.0
) {
    /** The distance at which every action is uncovered */
    val openDistance: Double
        get() = if (count == 0) {
            0.0
        } else {
            outerInset + innerInset + count * buttonWidth + (count - 1) * spacing
        }

    /** The distance that arms the outermost, destructive action: nearly the whole row */
    val confirmationDistance: Double
        get() {
            val scale = max(1.0, density)
            return (max(openDistance, width - 29) * scale).roundToInt() / scale
        }

    /** A finger this close to the leading edge arms the action before the confirmation distance */
    val edgeZone: Double
        get() = when {
            width >= 414 -> 90.0
            width == 375.0 -> 75.0
            else -> 50.0
        }

    fun computeEdgeFraction(velocity: Double): Double {
        val lower = if (width >= 414) 0.5 else 0.66
        val upper = if (width >= 414) 0.75 else 0.8
        return min(upper, max(lower, abs(velocity) / 2500))
    }

    /** Finger travel past the confirmation distance, or against the reveal, moves the row less than the finger */
    fun applyResistance(distance: Double, isInverse: Boolean = false): Double {
        val exponent = if (isInverse) 1 / 0.7 else 0.7
        return when {
            distance < 0 -> -(-distance).pow(exponent)

            distance > confirmationDistance ->
                confirmationDistance + (distance - confirmationDistance).pow(exponent)

            else -> distance
        }
    }
}

internal data class AgentThreadSwipeButtonGeometry(
    // Distance of the center from the row's trailing edge. Index zero is the outermost action.
    val center: Double,
    val width: Double,
    val scale: Double,
    val opacity: Double
) {
    companion object {
        fun calculate(
            reveal: Double,
            parameters: AgentThreadSwipeParameters
        ): List<AgentThreadSwipeButtonGeometry> {
            val p = parameters
            val distance = max(0.0, reveal)
            return (0 until p.count).map { index ->
                val outside = p.outerInset + index * (p.buttonWidth + p.spacing)
                val end = outside + p.buttonWidth + p.innerInset
                val start = end - p.buttonWidth + 2 * p.spacing
                var scale = min(1.0, max(0.0, (distance - start) / max(1.0, end - start)))
                var opacity = scale
                var width = p.buttonWidth
                var center = outside + width / 2
                if (index == 0) {
                    // The outermost action stretches over everything revealed past the open distance
                    width += max(0.0, distance - p.openDistance)
                    center = p.outerInset + width / 2
                }
                if (distance > p.openDistance + 0.001) {
                    scale = 1.0
                    if (index == 0) {
                        opacity = 1.0
                    } else {
                        center += distance - p.openDistance
                        // The other actions fade from full opacity at the open distance to 30% where the swipe arms
                        val armSpan = max(1.0, p.confirmationDistance - p.openDistance)
                        val stretch = (distance - p.openDistance) / armSpan
                        opacity = 1 - min(1.0, stretch) * 0.7
                    }
                }
                AgentThreadSwipeButtonGeometry(
                    center,
                    width,
                    scale,
                    if (opacity < 0.01) 0.0 else opacity
                )
            }
        }
    }
}

/**
 * Telegram's chat list swipe for a row whose outermost action is destructive: the row follows the finger, past the
 * actions with resistance, and a swipe across nearly the whole row arms that action, which then runs on release
 */
internal class AgentThreadSwipeMotion {
    enum class State { CLOSED, DRAGGING, SETTLING_OPEN, SETTLING_CLOSED, OPEN }

    var parameters = AgentThreadSwipeParameters()
        private set
    var state = State.CLOSED
        private set
    var isArmed = false
        private set

    /** The revealed distance */
    val body = AgentThreadSwipeSpring()

    /** The rounding and opacity of the card the row becomes */
    val surface = AgentThreadSwipeSpring(response = 0.66, damping = 0.95)

    /** Moves the armed action's icon to the end that follows the finger */
    val expansion = AgentThreadSwipeSpring()
    var scales: List<AgentThreadSwipeSpring> = emptyList()
        private set
    var opacities: List<AgentThreadSwipeSpring> = emptyList()
        private set
    private var initial = 0.0
    private var confirmationAdjustment = 0.0
    private var isContinuingSpring = false

    val isAtRest: Boolean
        get() = body.isAtRest && surface.isAtRest && expansion.isAtRest &&
            scales.all { it.isAtRest } && opacities.all { it.isAtRest }

    val buttonGeometry: List<AgentThreadSwipeButtonGeometry>
        get() = AgentThreadSwipeButtonGeometry.calculate(body.value, parameters)

    fun configure(parameters: AgentThreadSwipeParameters) {
        this.parameters = parameters
        if (scales.size != parameters.count) {
            scales = List(parameters.count) {
                AgentThreadSwipeSpring(response = 0.5, damping = 0.7)
            }
            opacities = List(parameters.count) { AgentThreadSwipeSpring() }
        }
        retargetButtons()
    }

    fun begin() {
        // A row grabbed while it settles stops where it is and follows the finger from there
        body.snap(body.value)
        body.response = DRAGGING_RESPONSE
        isContinuingSpring = false
        initial = parameters.applyResistance(body.value, isInverse = true)
        confirmationAdjustment = 0.0
        isArmed = false
        state = State.DRAGGING
        surface.target = 1.0
    }

    fun change(
        translation: Double,
        velocity: Double,
        distanceFromCommitEdge: Double,
        isReducedMotion: Boolean
    ) {
        if (state != State.DRAGGING) return
        var proposed = initial + translation + confirmationAdjustment
        val confirmation = parameters.confirmationDistance
        var isArmedNow = proposed >= confirmation
        if (!isArmedNow && proposed > confirmation * parameters.computeEdgeFraction(velocity) &&
            distanceFromCommitEdge < parameters.edgeZone
        ) {
            isArmedNow = true
            if (confirmationAdjustment == 0.0) {
                confirmationAdjustment = confirmation - proposed
                proposed = confirmation
            }
        }
        isArmed = isArmedNow
        // Once armed, the row moves on a spring for the rest of the touch, also after disarming
        if (isArmedNow && !isReducedMotion) isContinuingSpring = true
        val target = parameters.applyResistance(proposed)
        if (isContinuingSpring && !isReducedMotion) {
            body.target = target
        } else {
            body.snap(target)
        }
        retargetButtons()
        // The actions pop in as the finger uncovers them, with the row rather than after it
        scales.forEach { it.snap(it.target) }
        opacities.forEach { it.snap(it.target) }
        if (isReducedMotion) snapToTargets()
    }

    /** Settles open or closed and reports whether the release runs the armed action */
    fun end(
        translation: Double,
        velocity: Double,
        isCancelled: Boolean,
        isAnimated: Boolean
    ): Boolean {
        if (state != State.DRAGGING) return false
        val shouldCommit = !isCancelled && isArmed
        val shouldOpen = shouldCommit || if (abs(velocity) > 50) {
            velocity > 50
        } else {
            initial + translation > parameters.openDistance / 2
        }
        settle(if (shouldOpen) parameters.openDistance else 0.0, velocity, isAnimated)
        return shouldCommit
    }

    fun settle(target: Double, velocity: Double, isAnimated: Boolean) {
        state = if (target > 0) State.SETTLING_OPEN else State.SETTLING_CLOSED
        isArmed = false
        isContinuingSpring = false
        body.response = SETTLING_RESPONSE
        body.target = target
        body.velocity = computeTransferredVelocity(velocity, body.value, target)
        surface.target = if (target > 0) 1.0 else 0.0
        retargetButtons()
        if (!isAnimated) {
            snapToTargets()
            finishSettling()
        }
    }

    fun advance(deltaSeconds: Double) {
        if (state != State.DRAGGING || isArmed || isContinuingSpring) body.advance(deltaSeconds)
        surface.advance(deltaSeconds)
        retargetButtons()
        expansion.advance(deltaSeconds)
        scales.forEach { it.advance(deltaSeconds) }
        opacities.forEach { it.advance(deltaSeconds) }
        if (isAtRest) {
            snapToTargets()
            finishSettling()
        }
    }

    fun reset() {
        body.snap(0.0)
        body.response = SETTLING_RESPONSE
        surface.snap(0.0)
        expansion.snap(0.0)
        state = State.CLOSED
        isArmed = false
        isContinuingSpring = false
        retargetButtons()
        scales.forEach { it.snap(it.target) }
        opacities.forEach { it.snap(it.target) }
    }

    private fun snapToTargets() {
        body.snap(body.target)
        surface.snap(surface.target)
        expansion.snap(expansion.target)
        scales.forEach { it.snap(it.target) }
        opacities.forEach { it.snap(it.target) }
    }

    private fun retargetButtons() {
        expansion.target = if (isArmed) 1.0 else 0.0
        val geometry = AgentThreadSwipeButtonGeometry.calculate(body.target, parameters)
        scales.forEachIndexed { index, spring -> spring.target = geometry[index].scale }
        opacities.forEachIndexed { index, spring ->
            spring.target = geometry[index].opacity
            spring.response = if (state == State.DRAGGING) 0.25 else 0.5
        }
    }

    private fun finishSettling() {
        state = when (state) {
            State.SETTLING_OPEN -> State.OPEN
            State.SETTLING_CLOSED -> State.CLOSED
            else -> state
        }
    }

    companion object {
        // The spring that carries the row while the finger holds it: quick, so a jump to the armed distance catches
        // up with the finger at once
        private const val DRAGGING_RESPONSE = 0.18
        private const val SETTLING_RESPONSE = 0.5

        /**
         * A release's velocity carries into the settle only toward its target, and at most as fast as the critically
         * damped settle starts by itself, so the row lands on its target without passing it, as iOS's does
         */
        private fun computeTransferredVelocity(
            velocity: Double,
            position: Double,
            target: Double
        ): Double {
            val remaining = target - position
            if (abs(remaining) <= 0.000001) return 0.0
            return min(SETTLING_FREQUENCY, max(0.0, velocity / remaining)) * remaining
        }

        private const val SETTLING_FREQUENCY = 2 * PI / SETTLING_RESPONSE
    }
}
