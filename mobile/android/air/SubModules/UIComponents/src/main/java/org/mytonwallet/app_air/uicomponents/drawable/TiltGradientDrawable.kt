package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Shader
import android.graphics.drawable.Drawable
import kotlin.math.cos
import kotlin.math.sin

class TiltGradientDrawable(
    private val colors: IntArray
) : Drawable() {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    var angle: Float = 0f
        set(value) {
            field = value
            invalidateSelf()
        }

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        updateShader()
    }

    private fun updateShader() {
        val rad = Math.toRadians(angle.toDouble() + 18)
        val w = bounds.width().toFloat()
        val h = bounds.height().toFloat()

        val x0 = w * 0.45f
        val y0 = h * 0.2f

        val x1 = (x0 + cos(rad) * w * 0.17)
        val y1 = (y0 - sin(rad) * h * 0.1)

        paint.shader = LinearGradient(
            x0, y0, x1.toFloat(), y1.toFloat(),
            colors,
            null,
            Shader.TileMode.CLAMP
        )
    }

    override fun draw(canvas: Canvas) {
        canvas.drawRect(bounds, paint)
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
    }

    override fun getOpacity(): Int = PixelFormat.OPAQUE
}
