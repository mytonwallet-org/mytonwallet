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
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class ScamLabelSpan(private val text: String) : ReplacementSpan() {
    private val paddingTopPx = 0.5f.dp
    private val paddingRightPx = 3.dp
    private val paddingBottomPx = 1.dp
    private val paddingLeftPx = 3.dp
    private val borderRadiusPx = 3f.dp
    private val borderWidthPx = 1.2f.dp
    private val textSizePx = 11f.sp
    private val textColor = WColor.Red.color
    private val textTypeface = WFont.Medium.typeface

    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = borderWidthPx
        color = textColor
    }

    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = textColor
        textSize = textSizePx
        typeface = Typeface.create(textTypeface, Typeface.BOLD)
    }
    private val textWidthPx = textPaint.measureText(text)
    private val textHeightPx = textPaint.fontMetrics.let { it.descent - it.ascent }
    private val labelWidthPx = (textWidthPx + paddingLeftPx + paddingRightPx).toInt()
    private val labelHeightPx = (textHeightPx + paddingTopPx + paddingBottomPx).toInt()

    override fun getSize(
        paint: Paint,
        text: CharSequence?,
        start: Int,
        end: Int,
        fm: Paint.FontMetricsInt?
    ): Int {
        val heightPx = labelHeightPx
        fm?.let {
            it.ascent = -heightPx + paddingBottomPx
            it.descent = paddingBottomPx
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
        paint: Paint
    ) {
        val widthPx = labelWidthPx
        val heightPx = labelHeightPx
        val rectTop = (top + bottom - heightPx) / 2f
        val halfStroke = borderWidthPx / 2f
        val rect = RectF(
            x + halfStroke,
            rectTop + halfStroke,
            x + widthPx - halfStroke,
            rectTop + heightPx - halfStroke
        )
        canvas.drawRoundRect(rect, borderRadiusPx, borderRadiusPx, strokePaint)

        val contentWidth = widthPx - paddingLeftPx - paddingRightPx
        val contentHeight = heightPx - paddingTopPx - paddingBottomPx
        val textX = x + paddingLeftPx + (contentWidth - textWidthPx) / 2f
        val fm = textPaint.fontMetrics
        val textHeight = fm.descent - fm.ascent
        val textBaseline =
            rectTop + paddingTopPx + (contentHeight - textHeight) / 2f - fm.ascent
        canvas.drawText(this.text, textX, textBaseline, textPaint)
    }
}
