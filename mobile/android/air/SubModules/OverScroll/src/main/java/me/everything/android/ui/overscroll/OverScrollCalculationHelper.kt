package me.everything.android.ui.overscroll

import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.pow

class OverScrollCalculationHelper {

    companion object {
        private const val DEFAULT_FRICTION = -4.2f
        private const val VELOCITY_THRESHOLD_MULTIPLIER = 1000f / 16f

        // set here friction that you set in .setFriction(1.1f) or 1 by default
        private const val FRICTION = 1.1f * DEFAULT_FRICTION
        private const val THRESHOLD_MULTIPLIER = 0.75f
        private const val VELOCITY_THRESHOLD = THRESHOLD_MULTIPLIER * VELOCITY_THRESHOLD_MULTIPLIER

        fun computeOverScrollTime(velocityY: Int): Double {
            return ln((VELOCITY_THRESHOLD / velocityY).toDouble()) * 1000.0 / FRICTION
        }

        fun computeOverScrollDistance(velocityY: Int): Float {
            val time = computeOverScrollTime(velocityY)
            val flingDistance = velocityY / FRICTION * (exp(FRICTION * time / 1000.0) - 1)
            return flingDistance.toFloat()
        }

        fun computeOverscrollVelocityAtDistance(velocityY: Float, y: Float): Float {
            if (velocityY == 0f || y == 0f) {
                return velocityY
            }
            return velocityY / (1 + (FRICTION * y / velocityY))
        }

        fun calculateBounceY(x: Double): Double {
            return x.pow(0.7)
        }

        fun calculateY(x: Double): Double {
            return (x + 0.263).pow(0.9) - 0.279
        }

        fun findXFromY(prevY: Double): Double {
            return (prevY + 0.279).pow(1.0 / 0.9) - 0.263
        }

    }

}
