package org.mytonwallet.app_air.walletcontext.helpers

import android.animation.TimeInterpolator
import android.graphics.Path
import android.view.animation.PathInterpolator
import androidx.core.view.animation.PathInterpolatorCompat
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

        fun spring(dampingRatio: Float = 0.72f, stiffness: Float = 11f): TimeInterpolator {
            val omegaD = stiffness * sqrt(1f - dampingRatio * dampingRatio)
            return TimeInterpolator { t ->
                if (t >= 1f) {
                    1f
                } else {
                    val decay = exp(-dampingRatio * stiffness * t)
                    val oscillation =
                        cos(omegaD * t) + (dampingRatio * stiffness / omegaD) * sin(omegaD * t)
                    1f - decay * oscillation
                }
            }
        }

        fun easeOut(progress: Float): Float = 1 - (1 - progress).pow(3f)

        fun easeOutQuad(progress: Float): Float = 1 - (1 - progress).pow(2f)
    }
}
