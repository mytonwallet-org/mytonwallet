package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import androidx.annotation.ColorInt

data class ChartModel(
    val x: LongArray,
    val lines: List<Line>,
    val xTickFormatter: String? = null,
    val xTooltipFormatter: String? = null,
    val yTickFormatter: String? = null,
    val yTooltipFormatter: String? = null,
) {
    data class Line(
        val id: String,
        val name: String,
        val y: LongArray,
        @ColorInt val color: Int,
        @ColorInt val colorDark: Int = ChartFormatters.defaultDarkLineColor(color),
    )
}
