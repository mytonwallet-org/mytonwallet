package org.mytonwallet.app_air.uicomponents.helpers.spans

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.style.ReplacementSpan
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.sp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface

class ChainBadgeSpan(
    private val text: String,
    private val textColorInt: Int,
    private val backgroundColorInt: Int,
) : ReplacementSpan() {
    private val paddingHorizontalPx = 4.dp
    private val paddingVerticalPx = 1.dp
    private val textSizePx = 10f.sp

    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = backgroundColorInt
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = textColorInt
        textSize = textSizePx
        typeface = WFont.Medium.typeface
    }
    private val textWidthPx = textPaint.measureText(text)
    private val textHeightPx = textPaint.fontMetrics.let { it.descent - it.ascent }
    private val labelWidthPx = (textWidthPx + paddingHorizontalPx * 2).toInt()
    private val labelHeightPx = (textHeightPx + paddingVerticalPx * 2).toInt()

    override fun getSize(
        paint: Paint,
        text: CharSequence?,
        start: Int,
        end: Int,
        fm: Paint.FontMetricsInt?,
    ): Int {
        fm?.let {
            it.ascent = -labelHeightPx + paddingVerticalPx
            it.descent = paddingVerticalPx
            it.top = it.ascent
            it.bottom = it.descent
        }
        return labelWidthPx
    }

    override fun draw(
        canvas: Canvas,
        text: CharSequence?,
        start: Int,
        end: Int,
        x: Float,
        top: Int,
        y: Int,
        bottom: Int,
        paint: Paint,
    ) {
        val rectTop = (top + bottom - labelHeightPx) / 2f
        val rect = RectF(x, rectTop, x + labelWidthPx, rectTop + labelHeightPx)
        val pillRadius = labelHeightPx / 2f
        canvas.drawRoundRect(rect, pillRadius, pillRadius, backgroundPaint)
        val fm = textPaint.fontMetrics
        val textBaseline =
            rectTop + paddingVerticalPx + (textHeightPx - (fm.descent - fm.ascent)) / 2f - fm.ascent
        canvas.drawText(this.text, x + paddingHorizontalPx, textBaseline, textPaint)
    }
}
