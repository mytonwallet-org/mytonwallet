package org.mytonwallet.app_air.walletcontext.utils

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.drawable.Drawable
import android.text.style.ImageSpan
import androidx.core.graphics.withSave
import kotlin.math.roundToInt

class VerticalImageSpan(
    drawable: Drawable,
    private val shouldFlipForRTL: Boolean = false,
    private val startPadding: Int = 0,
    private val endPadding: Int = 0,
    private val verticalAlignment: VerticalAlignment = VerticalAlignment.ASCENT_DESCENT,
    private val verticalOffsetEm: Float = 0f,
    private val isRTL: Boolean = false
) : ImageSpan(drawable) {

    constructor(drawable: Drawable, isRTL: Boolean) : this(
        drawable,
        shouldFlipForRTL = isRTL,
        isRTL = isRTL
    )

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
            val drHeight = rect.bottom - rect.top
            val drawableTop = getDrawableTop(paint)
            val drawableBottom = drawableTop + drHeight

            fontMetricsInt.ascent = drawableTop
            fontMetricsInt.top = drawableTop
            fontMetricsInt.bottom = drawableBottom
            fontMetricsInt.descent = drawableBottom
        }
        return rect.right + startPadding + endPadding
    }

    private fun getDrawableTop(paint: Paint): Int {
        val fontMetrics = paint.fontMetricsInt
        val centerY = when (verticalAlignment) {
            VerticalAlignment.ASCENT_DESCENT ->
                fontMetrics.descent - (fontMetrics.descent - fontMetrics.ascent) / 2

            VerticalAlignment.TOP_BOTTOM ->
                fontMetrics.bottom - (fontMetrics.bottom - fontMetrics.top) / 2
        }
        val verticalOffset = (paint.textSize * verticalOffsetEm).roundToInt()
        return centerY - drawable.bounds.height() / 2 + verticalOffset
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
            val leftPadding = if (isRTL) endPadding else startPadding
            translate(x + leftPadding, (y + getDrawableTop(paint)).toFloat())

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
        ASCENT_DESCENT,
        TOP_BOTTOM
    }
}
