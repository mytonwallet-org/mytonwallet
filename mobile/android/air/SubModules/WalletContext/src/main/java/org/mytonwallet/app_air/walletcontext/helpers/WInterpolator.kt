package org.mytonwallet.app_air.walletcontext.helpers

import android.animation.TimeInterpolator
import android.graphics.Path
import android.view.animation.PathInterpolator
import androidx.core.view.animation.PathInterpolatorCompat
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

class WInterpolator {
    companion object {
        val emphasizedAccelerate = PathInterpolator(0.3f, 0f, 0.8f, 0.15f)
        val emphasizedDecelerate = PathInterpolator(0.05f, 0.7f, 0.1f, 1f)
        val easeInOut = PathInterpolator(0.42f, 0f, 0.58f, 1f)
        val emphasized =
            PathInterpolatorCompat.create(
                Path().apply {
                    moveTo(0f, 0f)
                    cubicTo(0.05f, 0f, 0.133333f, 0.06f, 0.166666f, 0.4f)
                    cubicTo(0.208333f, 0.82f, 0.25f, 1f, 1f, 1f)
                }
            )

        // A smooth, nearly critically damped response without visible overshoot.
        val smooth = spring(dampingRatio = 0.99f)

        /**
         * A spring released from 0 toward 1 at rest, with [stiffness] as its natural frequency per the animation's
         * duration: it swings past 1 below a [dampingRatio] of 1 and creeps up to 1 from it on
         */
        fun spring(dampingRatio: Float = 0.72f, stiffness: Float = 11f): TimeInterpolator =
            TimeInterpolator { t -> springProgress(t, dampingRatio, stiffness) }

        fun easeOut(progress: Float): Float = 1 - (1 - progress).pow(3f)

        fun easeOutQuad(progress: Float): Float = 1 - (1 - progress).pow(2f)
    }
}

// Damping ratios this close to 1 take the critically damped form, where the others divide by nearly 0
private const val CRITICAL_DAMPING_TOLERANCE = 1e-4

/**
 * Where [WInterpolator.spring] is at [t] of its duration, from 0 to 1. A spring without a swing is still short of 1 as
 * its duration ends, so its whole way is scaled to end exactly there instead of jumping to it on the last frame.
 */
internal fun springProgress(t: Float, dampingRatio: Float, stiffness: Float): Float {
    if (t >= 1f) return 1f
    val zeta = dampingRatio.toDouble()
    val omega = stiffness.toDouble()
    val progress = 1 - springRemainder(t.toDouble(), zeta, omega)
    if (zeta < 1 - CRITICAL_DAMPING_TOLERANCE) return progress.toFloat()
    val end = 1 - springRemainder(1.0, zeta, omega)
    return if (end > 0) (progress / end).toFloat() else progress.toFloat()
}

// How far the spring has still to go at [time] of its duration, from 1 at the start
private fun springRemainder(time: Double, zeta: Double, omega: Double): Double = when {
    abs(zeta - 1) < CRITICAL_DAMPING_TOLERANCE -> (1 + omega * time) * exp(-omega * time)

    zeta < 1 -> {
        val omegaD = omega * sqrt(1 - zeta * zeta)
        exp(-zeta * omega * time) *
            (cos(omegaD * time) + zeta * omega / omegaD * sin(omegaD * time))
    }

    // Two decays without a swing: a slow one that settles it and a fast one that starts it at rest
    else -> {
        val split = omega * sqrt(zeta * zeta - 1)
        val slow = zeta * omega - split
        val fast = zeta * omega + split
        (fast * exp(-slow * time) - slow * exp(-fast * time)) / (fast - slow)
    }
}
