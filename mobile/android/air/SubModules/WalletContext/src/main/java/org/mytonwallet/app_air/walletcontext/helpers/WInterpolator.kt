package org.mytonwallet.app_air.walletcontext.helpers

import android.graphics.Path
import android.view.animation.PathInterpolator
import androidx.core.view.animation.PathInterpolatorCompat
import kotlin.math.pow

class WInterpolator {
    companion object {
        val emphasizedAccelerate = PathInterpolator(0.3f, 0f, 0.8f, 0.15f)
        val emphasizedDecelerate = PathInterpolator(0.05f, 0.7f, 0.1f, 1f)
        val emphasized =
            PathInterpolatorCompat.create(Path().apply {
                moveTo(0f, 0f)
                cubicTo(0.05f, 0f, 0.133333f, 0.06f, 0.166666f, 0.4f)
                cubicTo(0.208333f, 0.82f, 0.25f, 1f, 1f, 1f)
            })

        fun easeOut(progress: Float): Float {
            return 1 - (1 - progress).pow(3f)
        }

    }
}
