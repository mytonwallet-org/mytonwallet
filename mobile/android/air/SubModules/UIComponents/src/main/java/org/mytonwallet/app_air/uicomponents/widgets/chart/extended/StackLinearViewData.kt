package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.graphics.Paint

open class StackLinearViewData(
    line: ChartData.Line,
    style: ChartStyle,
) : LineViewData(line, false, style) {
    init {
        paint.style = Paint.Style.FILL
        if (BaseChartView.USE_LINES) {
            paint.isAntiAlias = false
        }
    }
}
