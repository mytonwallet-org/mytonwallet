package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.text.TextPaint

interface ChartValueFormatter {
    fun formatAxisValue(value: Long, paint: TextPaint): CharSequence

    fun formatLegendValue(value: Long, paint: TextPaint): CharSequence

    fun formatZeroAxisValue(paint: TextPaint): CharSequence = formatAxisValue(0L, paint)
}
