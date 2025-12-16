package org.mytonwallet.app_air.walletcontext.utils

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.drawable.Drawable
import android.text.style.ImageSpan
import androidx.core.graphics.withSave

class VerticalImageSpan(
    drawable: Drawable,
    private val shouldFlipForRTL: Boolean = false,
    private val startPadding: Int = 0,
    private val endPadding: Int = 0,
    private val verticalAlignment: VerticalAlignment = VerticalAlignment.ASCENT_DESCENT
) : ImageSpan(drawable) {

    constructor(drawable: Drawable, isRTL: Boolean) : this(drawable, shouldFlipForRTL = isRTL)

    constructor(drawable: Drawable, startPadding: Int, endPadding: Int) : this(
        drawable,
        shouldFlipForRTL = false,
        startPadding = startPadding,
        endPadding = endPadding
    )

    /**
     * update the text line height
     */
    override fun getSize(
        paint: Paint,
        text: CharSequence,
        start: Int,
        end: Int,
        fontMetricsInt: Paint.FontMetricsInt?
    ): Int {
        val drawable = drawable
        val rect: Rect = drawable.bounds
        if (fontMetricsInt != null) {
            val fmPaint = paint.fontMetricsInt
            val fontHeight = fmPaint.descent - fmPaint.ascent
            val drHeight = rect.bottom - rect.top
            val centerY = fmPaint.ascent + fontHeight / 2

            fontMetricsInt.ascent = centerY - drHeight / 2
            fontMetricsInt.top = fontMetricsInt.ascent
            fontMetricsInt.bottom = centerY + drHeight / 2
            fontMetricsInt.descent = fontMetricsInt.bottom
        }
        return rect.right + startPadding + endPadding
    }

    /**
     * see detail message in android.text.TextLine
     *
     * @param canvas the canvas, can be null if not rendering
     * @param text   the text to be draw
     * @param start  the text start position
     * @param end    the text end position
     * @param x      the edge of the replacement closest to the leading margin
     * @param top    the top of the line
     * @param y      the baseline
     * @param bottom the bottom of the line
     * @param paint  the work paint
     */
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
        val drawable = drawable
        canvas.withSave {
            val fmPaint = paint.fontMetricsInt
            val fontHeight: Int
            val centerY: Int
            if (verticalAlignment == VerticalAlignment.ASCENT_DESCENT) {
                fontHeight = fmPaint.descent - fmPaint.ascent
                centerY = y + fmPaint.descent - fontHeight / 2
            } else {
                fontHeight = fmPaint.bottom - fmPaint.top
                centerY = y + fmPaint.bottom - fontHeight / 2
            }
            val transY = centerY - (drawable.bounds.bottom - drawable.bounds.top) / 2
            translate(x + startPadding, transY.toFloat())

            if (shouldFlipForRTL) {
                val drawableWidth = drawable.bounds.width()
                translate(drawableWidth / 2f, drawable.bounds.height() / 2f)
                scale(-1f, 1f)
                translate(-drawableWidth / 2f, -drawable.bounds.height() / 2f)
            }

            drawable.draw(this)
        }
    }

    enum class VerticalAlignment {
        ASCENT_DESCENT, TOP_BOTTOM
    }
}
