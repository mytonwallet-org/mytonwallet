package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import androidx.core.graphics.ColorUtils

class BarChartView(
    context: Context
) : org.mytonwallet.app_air.uicomponents.widgets.chart.extended.BaseChartView<org.mytonwallet.app_air.uicomponents.widgets.chart.extended.ChartData, org.mytonwallet.app_air.uicomponents.widgets.chart.extended.BarViewData>(context) {
    init {
        superDraw = true
        useAlphaSignature = true
    }

    override fun drawChart(canvas: Canvas) {
        val data = chartData ?: return
        val fullWidth = chartWidth / (pickerDelegate.pickerEnd - pickerDelegate.pickerStart)
        val offset = fullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING
        var start = startXIndex - 1
        if (start < 0) start = 0
        var end = endXIndex + 1
        if (end > data.lines[0].y.size - 1) end = data.lines[0].y.size - 1

        canvas.save()
        canvas.clipRect(chartStart, 0f, chartEnd, (measuredHeight - chartBottom).toFloat())

        var transitionAlpha = 1f
        canvas.save()
        when (transitionMode) {
            TRANSITION_MODE_PARENT -> {
                val params = transitionParams ?: return
                postTransition = true
                selectionA = 0f
                transitionAlpha = 1f - params.progress
                canvas.scale(1 + 2 * params.progress, 1f, params.pX, params.pY)
            }

            TRANSITION_MODE_CHILD -> {
                val params = transitionParams ?: return
                transitionAlpha = params.progress
                canvas.scale(params.progress, 1f, params.pX, params.pY)
            }
        }

        for (line in lines) {
            if (!line.enabled && line.alpha == 0f) continue
            val p = if (data.xPercentage.size < 2) 1f else data.xPercentage[1] * fullWidth
            val y = line.line.y
            var j = 0
            var selectedX = 0f
            var selectedY = 0f
            var selected = false
            val a = line.alpha
            for (i in start..end) {
                val xPoint = p / 2 + data.xPercentage[i] * fullWidth - offset
                val yPercentage = y[i] / currentMaxHeight * a
                val yPoint =
                    measuredHeight - chartBottom - yPercentage * (measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT)
                if (i == selectedIndex && legendShowing) {
                    selected = true
                    selectedX = xPoint
                    selectedY = yPoint
                    continue
                }
                line.linesPath[j++] = xPoint
                line.linesPath[j++] = yPoint
                line.linesPath[j++] = xPoint
                line.linesPath[j++] = (measuredHeight - chartBottom).toFloat()
            }

            val paint: Paint = if (selected || postTransition) line.unselectedPaint else line.paint
            paint.strokeWidth = p
            if (selected) {
                line.unselectedPaint.color =
                    ColorUtils.blendARGB(line.lineColor, line.blendColor, 1f - selectionA)
            }
            if (postTransition) {
                line.unselectedPaint.color =
                    ColorUtils.blendARGB(line.lineColor, line.blendColor, 0f)
            }
            paint.alpha = (255 * transitionAlpha).toInt()
            canvas.drawLines(line.linesPath, 0, j, paint)
            if (selected) {
                line.paint.strokeWidth = p
                line.paint.alpha = (255 * transitionAlpha).toInt()
                canvas.drawLine(
                    selectedX,
                    selectedY,
                    selectedX,
                    (measuredHeight - chartBottom).toFloat(),
                    line.paint
                )
                line.paint.alpha = 255
            }
        }

        canvas.restore()
        canvas.restore()
    }

    override fun drawPickerChart(canvas: Canvas) {
        val data = chartData ?: return
        for (line in lines) {
            if (!line.enabled && line.alpha == 0f) continue
            val n = data.xPercentage.size
            var j = 0
            val p = if (data.xPercentage.size < 2) 1f else data.xPercentage[1] * pickerWidth
            val y = line.line.y
            val a = line.alpha
            for (i in 0 until n) {
                if (y[i] < 0) continue
                val xPoint = data.xPercentage[i] * pickerWidth
                val h = if (ANIMATE_PICKER_SIZES) pickerMaxHeight else data.maxValue.toFloat()
                val yPercentage = y[i] / h * a
                val yPoint = (1f - yPercentage) * pikerHeight
                line.linesPath[j++] = xPoint
                line.linesPath[j++] = yPoint
                line.linesPath[j++] = xPoint
                line.linesPath[j++] = (measuredHeight - chartBottom).toFloat()
            }
            line.paint.strokeWidth = p + 2
            canvas.drawLines(line.linesPath, 0, j, line.paint)
        }
    }

    override fun drawSelection(canvas: Canvas) {
    }

    override fun createLineViewData(line: ChartData.Line): BarViewData = BarViewData(line, style)

    override fun onDraw(canvas: Canvas) {
        tick()
        drawChart(canvas)
        drawBottomLine(canvas)
        tmpN = horizontalLines.size
        for (i in 0 until tmpN) {
            tmpI = i
            drawHorizontalLines(canvas, horizontalLines[i])
            drawSignaturesToHorizontalLines(canvas, horizontalLines[i])
        }
        drawBottomSignature(canvas)
        drawPicker(canvas)
        drawSelection(canvas)
        super.onDraw(canvas)
    }

    override fun getMinDistance(): Float = 0.1f
}
