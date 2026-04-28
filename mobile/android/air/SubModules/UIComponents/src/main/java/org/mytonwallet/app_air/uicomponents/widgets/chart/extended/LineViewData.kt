package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.ValueAnimator
import android.graphics.Paint
import android.graphics.Path
import org.mytonwallet.app_air.uicomponents.extensions.dp

open class LineViewData(
    val line: ChartData.Line,
    bar: Boolean,
    private val style: ChartStyle,
) {
    val bottomLinePaint = Paint(Paint.ANTI_ALIAS_FLAG)

    val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    val selectionPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    val bottomLinePath = Path()

    val chartPath = Path()

    val chartPathPicker = Path()

    var animatorIn: ValueAnimator? = null

    var animatorOut: ValueAnimator? = null

    var linesPathBottomSize: Int = 0

    var linesPath: FloatArray = FloatArray(if (bar) 8 * line.y.size else line.y.size shl 2)

    var linesPathBottom: FloatArray = FloatArray(if (bar) 8 * line.y.size else line.y.size shl 2)

    var lineColor: Int = 0

    var enabled: Boolean = true

    var alpha: Float = 1f

    init {
        paint.strokeWidth = 2f.dp
        paint.style = Paint.Style.STROKE
        if (!BaseChartView.USE_LINES) {
            paint.strokeJoin = Paint.Join.ROUND
        }
        paint.color = line.color

        bottomLinePaint.strokeWidth = 1f.dp
        bottomLinePaint.style = Paint.Style.STROKE
        bottomLinePaint.color = line.color

        selectionPaint.strokeWidth = 10f.dp
        selectionPaint.style = Paint.Style.STROKE
        selectionPaint.strokeCap = Paint.Cap.ROUND
        selectionPaint.color = line.color
    }

    open fun updateTheme() {
        lineColor = style.resolveLineColor(line)
        paint.color = lineColor
        bottomLinePaint.color = lineColor
        selectionPaint.color = lineColor
    }
}
