package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Shader
import android.graphics.drawable.Drawable

class StickyBottomGradientDrawable(
    private val colors: IntArray
) : Drawable() {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var positions: FloatArray = FloatArray(colors.size)
    private var shader: LinearGradient? = null

    fun setStops(newPositions: FloatArray) {
        if (newPositions.size != positions.size)
            return
        var changed = false
        for (i in newPositions.indices) {
            if (positions[i] != newPositions[i]) {
                positions[i] = newPositions[i]
                changed = true
            }
        }
        if (changed) {
            rebuildShader()
            invalidateSelf()
        }
    }

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        rebuildShader()
    }

    private fun rebuildShader() {
        val b = bounds
        if (b.width() <= 0 || b.height() <= 0) {
            shader = null
            paint.shader = null
            return
        }
        shader = LinearGradient(
            0f, b.top.toFloat(), 0f, b.bottom.toFloat(),
            colors, positions, Shader.TileMode.CLAMP
        )
        paint.shader = shader
    }

    override fun draw(canvas: Canvas) {
        if (paint.shader == null) rebuildShader()
        canvas.drawRect(bounds, paint)
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
        invalidateSelf()
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
        invalidateSelf()
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
