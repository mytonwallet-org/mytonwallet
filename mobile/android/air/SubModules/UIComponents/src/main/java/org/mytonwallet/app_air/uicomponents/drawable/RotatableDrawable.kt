package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.drawable.Drawable

class RotatableDrawable(private val base: Drawable) : Drawable() {
    var rotation = 0f
        set(value) {
            field = value
            invalidateSelf()
        }

    init {
        base.setBounds(0, 0, base.intrinsicWidth, base.intrinsicHeight)
        bounds = base.bounds
    }

    override fun draw(canvas: Canvas) {
        val cx = bounds.exactCenterX()
        val cy = bounds.exactCenterY()
        canvas.save()
        canvas.rotate(rotation, cx, cy)
        base.draw(canvas)
        canvas.restore()
    }

    override fun setAlpha(alpha: Int) {
        base.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        base.colorFilter = colorFilter
    }

    override fun setTint(tintColor: Int) {
        base.setTint(tintColor)
    }

    @Deprecated("Deprecated")
    override fun getOpacity(): Int = base.opacity
    override fun getIntrinsicWidth() = base.intrinsicWidth
    override fun getIntrinsicHeight() = base.intrinsicHeight
}
