package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import org.mytonwallet.app_air.uicomponents.extensions.setRounding
import org.mytonwallet.app_air.uicomponents.image.Content

class ContentGradientDrawable(
    orientation: Orientation,
    colors: IntArray,
    private val content: Drawable?
) : GradientDrawable(orientation, colors) {

    private var rounding: Content.Rounding = Content.Rounding.Default
    private var lastRatioSize = -1

    fun setContentRounding(rounding: Content.Rounding) {
        this.rounding = rounding
        lastRatioSize = -1
        setRounding(rounding)
        lastRatioSize = minOf(bounds.width(), bounds.height())
    }

    override fun setBounds(left: Int, top: Int, right: Int, bottom: Int) {
        super.setBounds(left, top, right, bottom)
        if (rounding is Content.Rounding.RadiusRatio) {
            val size = minOf(right - left, bottom - top)
            if (size != lastRatioSize) {
                lastRatioSize = size
                setRounding(rounding)
            }
        }
        content?.let {
            val w = it.minimumWidth
            val h = it.minimumHeight
            val x = (left + right - w) / 2
            val y = (top + bottom - h) / 2
            it.setBounds(x, y, x + w, y + h)
        }
    }

    override fun draw(canvas: Canvas) {
        super.draw(canvas)
        content?.draw(canvas)
    }
}
