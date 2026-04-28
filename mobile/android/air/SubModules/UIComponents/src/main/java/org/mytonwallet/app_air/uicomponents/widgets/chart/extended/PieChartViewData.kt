package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.Animator

class PieChartViewData(
    line: ChartData.Line,
    style: ChartStyle,
) : StackLinearViewData(line, style) {
    var selectionA = 0f

    var drawingPart = 0f

    var animator: Animator? = null
}
