package org.mytonwallet.app_air.uicomponents.extensions

import android.graphics.Paint.FontMetrics
import android.text.TextPaint
import org.mytonwallet.app_air.uicomponents.helpers.FontManager

fun FontMetrics.getCenterAlignBaseline(y: Float): Float = y - (ascent + descent) / 2f

fun TextPaint.getLtrBaselineSpacingOffset(subtitlePaint: TextPaint): Float {
    val titleMetrics = fontMetricsInt
    val subtitleMetrics = subtitlePaint.fontMetricsInt
    val ltrTitleMetrics = TextPaint(this).apply {
        typeface = FontManager.ltrVariant(typeface)
    }.fontMetricsInt
    val ltrSubtitleMetrics = TextPaint(subtitlePaint).apply {
        typeface = FontManager.ltrVariant(typeface)
    }.fontMetricsInt

    val baselineDistance = titleMetrics.bottom - subtitleMetrics.top
    val ltrBaselineDistance = ltrTitleMetrics.bottom - ltrSubtitleMetrics.top
    return (ltrBaselineDistance - baselineDistance).toFloat()
}
