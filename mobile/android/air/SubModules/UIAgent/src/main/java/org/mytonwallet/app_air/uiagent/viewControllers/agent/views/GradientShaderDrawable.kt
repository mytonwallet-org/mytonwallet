package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Shader
import android.graphics.drawable.Drawable

class GradientShaderDrawable(
    private val colors: IntArray,
    private val positions: FloatArray
) : Drawable() {

    private val paint = Paint()
    private var lastHeight = -1

    override fun draw(canvas: Canvas) {
        val h = bounds.height()
        if (h != lastHeight) {
            lastHeight = h
            paint.shader = LinearGradient(
                0f, 0f, 0f, h.toFloat(),
                colors, positions, Shader.TileMode.CLAMP
            )
        }
        canvas.drawRect(bounds, paint)
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
    }

    @Deprecated("Deprecated in Java", ReplaceWith("PixelFormat.TRANSLUCENT", "android.graphics.PixelFormat"))
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
