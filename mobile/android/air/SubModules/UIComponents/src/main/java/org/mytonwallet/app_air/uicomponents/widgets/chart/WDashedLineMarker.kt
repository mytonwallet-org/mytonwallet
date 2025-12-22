package org.mytonwallet.app_air.uicomponents.widgets.chart

import android.content.Context
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import com.github.mikephil.charting.components.MarkerView
import com.github.mikephil.charting.data.Entry
import com.github.mikephil.charting.highlight.Highlight
import com.github.mikephil.charting.utils.MPPointF
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class WDashedLineMarker(context: Context?) : MarkerView(context, R.layout.frame),
    WThemedView {
    private val linePaint = Paint()
    private val circlePaint = Paint().apply {
        style = Paint.Style.FILL_AND_STROKE
    }
    private val innerCirclePaint = Paint().apply {
        style = Paint.Style.FILL_AND_STROKE
    }

    init {
        linePaint.style = Paint.Style.STROKE
        linePaint.strokeWidth = 2f
        linePaint.setPathEffect(DashPathEffect(floatArrayOf(10f, 10f), 0f))
        updateTheme()
    }

    override fun refreshContent(e: Entry, highlight: Highlight) {
        super.refreshContent(e, highlight)
    }

    override fun draw(canvas: Canvas, posX: Float, posY: Float) {
        canvas.drawLine(posX, 0f, posX, chartView.height.toFloat() - 12.dp, linePaint)

        canvas.drawCircle(posX, posY, 10f, circlePaint)
        canvas.drawCircle(posX, posY, 6f, innerCirclePaint)

        super.draw(canvas, posX, posY)
    }

    override fun getOffset(): MPPointF {
        return MPPointF(-width / 2f, -height.toFloat())
    }

    override val isTinted = true
    override fun updateTheme() {
        linePaint.color = WColor.Tint.color
        circlePaint.color = WColor.Background.color
        innerCirclePaint.color = WColor.Tint.color
    }
}
