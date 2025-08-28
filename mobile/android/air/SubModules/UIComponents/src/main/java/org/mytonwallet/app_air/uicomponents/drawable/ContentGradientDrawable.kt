package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable

class ContentGradientDrawable(
    orientation: Orientation,
    colors: IntArray,
    private val content: Drawable?
) : GradientDrawable(orientation, colors) {

    override fun setBounds(left: Int, top: Int, right: Int, bottom: Int) {
        super.setBounds(left, top, right, bottom)
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
