package org.mytonwallet.app_air.walletcontext.utils

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.Drawable
import android.text.style.ImageSpan
import androidx.core.graphics.withSave

class MarginImageSpan(
    drawable: Drawable,
    private val marginTopPx: Int = 0,
    private val marginRightPx: Int = 0,
) : ImageSpan(drawable) {

    override fun draw(
        canvas: Canvas,
        text: CharSequence,
        start: Int,
        end: Int,
        x: Float,
        top: Int,
        y: Int,
        bottom: Int,
        paint: Paint
    ) {
        canvas.withSave {

            val transY = (y + paint.fontMetricsInt.descent - drawable.bounds.bottom) + marginTopPx
            translate(x, transY.toFloat())

            drawable.draw(this)
        }
    }

    override fun getSize(
        paint: Paint,
        text: CharSequence?,
        start: Int,
        end: Int,
        fm: Paint.FontMetricsInt?
    ): Int {
        val size = super.getSize(paint, text, start, end, fm) + marginRightPx

        if (fm != null) {
            val d = drawable.bounds
            val height = d.bottom - d.top

            val offset = marginTopPx

            fm.ascent = minOf(fm.ascent, -height + offset)
            fm.top = fm.ascent
        }

        return size
    }
}
