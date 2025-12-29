package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.drawable.Drawable
import androidx.core.graphics.withSave

class ScaledDrawable(
    private val drawable: Drawable,
    private val scaleX: Float,
    private val scaleY: Float
) : Drawable() {

    override fun draw(canvas: Canvas) {
        canvas.withSave {
            val centerX = bounds.exactCenterX()
            val centerY = bounds.exactCenterY()
            scale(scaleX, scaleY, centerX, centerY)
            drawable.bounds = bounds
            drawable.draw(this)
        }
    }

    override fun setAlpha(alpha: Int) {
        drawable.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        drawable.colorFilter = colorFilter
    }

    override fun getOpacity(): Int {
        return drawable.opacity
    }
}
