package org.mytonwallet.app_air.uicomponents.drawable.counter

import android.graphics.Canvas
import android.text.TextPaint
import kotlin.math.roundToInt
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt

class CounterTextPartImpl(private val text: String, val paint: TextPaint) : CounterTextPart {
    private val width = (paint.measureText(text)).ceilToInt()
    private val height = (paint.fontMetrics.descent - paint.fontMetrics.ascent).toInt()

    override fun hashCode(): Int = text.hashCode()

    override fun equals(other: Any?): Boolean = (other as? CounterTextPartImpl)?.let {
        it.text == text
    } ?: false

    override fun draw(
        c: Canvas,
        startX: Int,
        endX: Int,
        endXBottomPadding: Int,
        startY: Int,
        alpha: Float
    ) {
        paint.alpha = (alpha * 255).roundToInt()
        c.drawText(text, startX.toFloat(), startY.toFloat(), paint)
    }

    override fun getWidth(): Int = width

    override fun getHeight(): Int = height

    override fun getText(): String = text
}
