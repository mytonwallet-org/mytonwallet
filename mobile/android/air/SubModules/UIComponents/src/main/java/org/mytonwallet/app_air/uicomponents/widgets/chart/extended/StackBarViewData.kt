package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.graphics.Paint
import androidx.core.graphics.ColorUtils
import org.mytonwallet.app_air.uicomponents.extensions.dp

class StackBarViewData(
    line: ChartData.Line,
    private val style: ChartStyle,
) : LineViewData(line, false, style) {
    val unselectedPaint = Paint()

    var blendColor: Int = 0

    init {
        paint.strokeWidth = 1f.dp
        paint.style = Paint.Style.STROKE
        unselectedPaint.style = Paint.Style.STROKE
        paint.isAntiAlias = false
    }

    override fun updateTheme() {
        super.updateTheme()
        blendColor = ColorUtils.blendARGB(
            style.backgroundColor,
            lineColor,
            0.3f
        )
    }
}
