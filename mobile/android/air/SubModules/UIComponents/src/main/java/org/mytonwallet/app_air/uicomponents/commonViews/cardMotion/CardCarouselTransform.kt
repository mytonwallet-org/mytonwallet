package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

import android.graphics.Matrix
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/** Cover flow is independent of the inner finger-driven press projection. */
class CardCarouselTransform {
    val projection = Matrix()
    val inverse = Matrix()
    fun update(position: Double, width: Double, height: Double, enabled: Boolean): Double {
        if (width <= 0 || height <= 0 || !enabled ||
            abs(position) < 1e-8
        ) {
            projection.reset()
            inverse.reset()
            return 0.0
        }
        val angle =
            -position.times(1.7).coerceIn(-1.0, 1.0) * PI / 12
        val pivot =
            .6 * width * (if (position > 0) 1 else -1)
        val camera = 150 * width / 84
        val co = cos(angle)
        val si = sin(angle)
        val g = si / camera
        // CATransform3DTranslate -> Rotate -> Translate, expressed on the live plane.
        val a = co
        val d = pivot * (1 - co)
        val i = 1 - g * pivot
        val inner = if (position > 0) -width / 2 else width / 2
        val projected = (inner * a + d) / (inner * g + i)
        val correction = (inner - projected) * min(1.0, abs(position))
        val cx = width / 2
        val cy = height / 2.0
        val den = i - g * cx
        projection.setValues(
            floatArrayOf(
                (a + cx * g).toFloat(),
                0f,
                (d + cx * den - a * cx).toFloat(),
                (cy * g).toFloat(),
                1f,
                (
                    cy *
                        den -
                        cy
                    ).toFloat(),
                g.toFloat(), 0f, den.toFloat()
            )
        )
        projection.invert(inverse)
        return correction
    }
}
