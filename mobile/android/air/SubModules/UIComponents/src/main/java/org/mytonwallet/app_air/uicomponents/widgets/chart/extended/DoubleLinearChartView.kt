package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import kotlin.math.max
import kotlin.math.min

class DoubleLinearChartView(
    context: Context
) : BaseChartView<DoubleLinearChartData, LineViewData>(context) {

    override fun init() {
        useMinHeight = true
        super.init()
    }

    override fun drawChart(canvas: Canvas) {
        val data = chartData ?: return
        val fullWidth = chartWidth / (pickerDelegate.pickerEnd - pickerDelegate.pickerStart)
        val offset = fullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING

        canvas.save()
        var transitionAlpha = 1f
        when (transitionMode) {
            TRANSITION_MODE_PARENT -> {
                val params = transitionParams ?: return
                transitionAlpha = if (params.progress > 0.5f) 0f else 1f - params.progress * 2f
                canvas.scale(1 + 2 * params.progress, 1f, params.pX, params.pY)
            }
            TRANSITION_MODE_CHILD -> {
                val params = transitionParams ?: return
                transitionAlpha = if (params.progress < 0.3f) 0f else params.progress
                canvas.save()
                canvas.scale(params.progress, params.progress, params.pX, params.pY)
            }
            TRANSITION_MODE_ALPHA_ENTER -> transitionAlpha = transitionParams?.progress ?: 1f
        }

        for ((k, line) in lines.withIndex()) {
            if (!line.enabled && line.alpha == 0f) continue
            var j = 0
            val y = line.line.y
            line.chartPath.reset()
            var first = true
            val p = if (data.xPercentage.size < 2) 1f else data.xPercentage[1] * fullWidth
            val additionalPoints = (HORIZONTAL_PADDING / p).toInt() + 1
            val localStart = max(0, startXIndex - additionalPoints)
            val localEnd = min(data.xPercentage.size - 1, endXIndex + additionalPoints)
            for (i in localStart..localEnd) {
                if (y[i] < 0) continue
                val xPoint = data.xPercentage[i] * fullWidth - offset
                val yPercentage = (y[i] * data.linesK[k] - currentMinHeight) / (currentMaxHeight - currentMinHeight)
                val padding = line.paint.strokeWidth / 2f
                val yPoint = measuredHeight - chartBottom - padding - yPercentage * (measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT - padding)
                if (USE_LINES) {
                    if (j == 0) {
                        line.linesPath[j++] = xPoint
                        line.linesPath[j++] = yPoint
                    } else {
                        line.linesPath[j++] = xPoint
                        line.linesPath[j++] = yPoint
                        line.linesPath[j++] = xPoint
                        line.linesPath[j++] = yPoint
                    }
                } else if (first) {
                    first = false
                    line.chartPath.moveTo(xPoint, yPoint)
                } else {
                    line.chartPath.lineTo(xPoint, yPoint)
                }
            }
            line.paint.strokeCap = if (endXIndex - startXIndex > 100) Paint.Cap.SQUARE else Paint.Cap.ROUND
            line.paint.alpha = (255 * line.alpha * transitionAlpha).toInt()
            if (!USE_LINES) canvas.drawPath(line.chartPath, line.paint) else canvas.drawLines(line.linesPath, 0, j, line.paint)
        }

        canvas.restore()
    }

    override fun drawPickerChart(canvas: Canvas) {
        val data = chartData ?: return
        for ((k, line) in lines.withIndex()) {
            if (!line.enabled && line.alpha == 0f) continue
            line.bottomLinePath.reset()
            val n = data.xPercentage.size
            var j = 0
            val y = line.line.y
            line.chartPath.reset()
            for (i in 0 until n) {
                if (y[i] < 0) continue
                val xPoint = data.xPercentage[i] * pickerWidth
                val h = if (ANIMATE_PICKER_SIZES) pickerMaxHeight else data.maxValue.toFloat()
                val yPercentage = y[i] * data.linesK[k] / h
                val yPoint = (1f - yPercentage) * pikerHeight
                if (USE_LINES) {
                    if (j == 0) {
                        line.linesPathBottom[j++] = xPoint
                        line.linesPathBottom[j++] = yPoint
                    } else {
                        line.linesPathBottom[j++] = xPoint
                        line.linesPathBottom[j++] = yPoint
                        line.linesPathBottom[j++] = xPoint
                        line.linesPathBottom[j++] = yPoint
                    }
                } else if (i == 0) {
                    line.bottomLinePath.moveTo(xPoint, yPoint)
                } else {
                    line.bottomLinePath.lineTo(xPoint, yPoint)
                }
            }
            line.linesPathBottomSize = j
            line.bottomLinePaint.alpha = (255 * line.alpha).toInt()
            if (USE_LINES) canvas.drawLines(line.linesPathBottom, 0, line.linesPathBottomSize, line.bottomLinePaint)
            else canvas.drawPath(line.bottomLinePath, line.bottomLinePaint)
        }
    }

    override fun drawSelection(canvas: Canvas) {
        val data = chartData ?: return
        if (selectedIndex < 0 || !legendShowing) return
        val alpha = (chartActiveLineAlpha * selectionA).toInt()
        val fullWidth = chartWidth / (pickerDelegate.pickerEnd - pickerDelegate.pickerStart)
        val offset = fullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING
        val xPoint = data.xPercentage[selectedIndex] * fullWidth - offset
        selectedLinePaint.alpha = alpha
        canvas.drawLine(xPoint, 0f, xPoint, chartArea.bottom, selectedLinePaint)
        for ((i, line) in lines.withIndex()) {
            if (!line.enabled && line.alpha == 0f) continue
            val yPercentage = (line.line.y[selectedIndex] * data.linesK[i] - currentMinHeight) / (currentMaxHeight - currentMinHeight)
            val yPoint = measuredHeight - chartBottom - yPercentage * (measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT)
            line.selectionPaint.alpha = (255 * line.alpha * selectionA).toInt()
            selectionBackgroundPaint.alpha = (255 * line.alpha * selectionA).toInt()
            canvas.drawPoint(xPoint, yPoint, line.selectionPaint)
            canvas.drawPoint(xPoint, yPoint, selectionBackgroundPaint)
        }
    }

    override fun drawSignaturesToHorizontalLines(canvas: Canvas, a: ChartHorizontalLinesData) {
        val data = chartData ?: return
        val n = a.values.size
        val rightIndex = if (data.linesK[0] == 1f) 1 else 0
        val leftIndex = (rightIndex + 1) % 2
        var additionalOutAlpha = 1f
        if (n > 2) {
            val v = (a.values[1] - a.values[0]) / (currentMaxHeight - currentMinHeight)
            if (v < 0.1f) additionalOutAlpha = v / 0.1f
        }
        val transitionAlpha = when (transitionMode) {
            TRANSITION_MODE_PARENT -> 1f - (transitionParams?.progress ?: 0f)
            TRANSITION_MODE_CHILD, TRANSITION_MODE_ALPHA_ENTER -> transitionParams?.progress ?: 1f
            else -> 1f
        }
        linePaint.alpha = (a.alpha * 0.1f * transitionAlpha).toInt()
        val chartHeight = measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT
        val textOffset = (SIGNATURE_TEXT_HEIGHT - signaturePaint.textSize).toInt()
        for (i in 0 until n) {
            val y = (measuredHeight - chartBottom) - chartHeight * ((a.values[i] - currentMinHeight) / (currentMaxHeight - currentMinHeight))
            if (a.valuesStr != null && lines.isNotEmpty()) {
                if (a.valuesStr2 == null || lines.size < 2) {
                    signaturePaint.color = style.signatureColor
                    signaturePaint.alpha = (a.alpha * signaturePaintAlpha * transitionAlpha * additionalOutAlpha).toInt()
                } else {
                    signaturePaint.color = lines[leftIndex].lineColor
                    signaturePaint.alpha = (a.alpha * lines[leftIndex].alpha * transitionAlpha * additionalOutAlpha).toInt()
                }
                drawHorizontalLineSignature(
                    canvas = canvas,
                    linesData = a,
                    axis = 0,
                    index = i,
                    x = HORIZONTAL_PADDING,
                    y = y - textOffset,
                    paint = signaturePaint,
                )
            }
            if (a.valuesStr2 != null && lines.size > 1) {
                signaturePaint2.color = lines[rightIndex].lineColor
                signaturePaint2.alpha = (a.alpha * lines[rightIndex].alpha * transitionAlpha * additionalOutAlpha).toInt()
                drawHorizontalLineSignature(
                    canvas = canvas,
                    linesData = a,
                    axis = 1,
                    index = i,
                    x = measuredWidth - HORIZONTAL_PADDING,
                    y = y - textOffset,
                    paint = signaturePaint2,
                )
            }
        }
    }

    override fun createLineViewData(line: ChartData.Line): LineViewData = LineViewData(line, false, style)

    override fun findMaxValue(startXIndex: Int, endXIndex: Int): Long {
        if (lines.isEmpty()) return 0
        var maxValue = 0L
        for (i in lines.indices) {
            val localMax = if (lines[i].enabled) (chartData!!.lines[i].segmentTree!!.rMaxQ(startXIndex, endXIndex) * chartData!!.linesK[i]).toLong() else 0L
            if (localMax > maxValue) maxValue = localMax
        }
        return maxValue
    }

    override fun findMinValue(startXIndex: Int, endXIndex: Int): Long {
        if (lines.isEmpty()) return 0
        var minValue = Long.MAX_VALUE
        for (i in lines.indices) {
            val localMin = if (lines[i].enabled) (chartData!!.lines[i].segmentTree!!.rMinQ(startXIndex, endXIndex) * chartData!!.linesK[i]).toLong() else Int.MAX_VALUE.toLong()
            if (localMin < minValue) minValue = localMin
        }
        return minValue
    }

    override fun updatePickerMinMaxHeight() {
        if (!ANIMATE_PICKER_SIZES) return
        if (lines[0].enabled) {
            super.updatePickerMinMaxHeight()
            return
        }
        var maxValue = 0L
        for (line in lines) {
            if (line.enabled && line.line.maxValue > maxValue) maxValue = line.line.maxValue
        }
        if (lines.size > 1) {
            maxValue = (maxValue * chartData!!.linesK[1]).toLong()
        }
        if (maxValue > 0 && maxValue.toFloat() != animatedToPickerMaxHeight) {
            animatedToPickerMaxHeight = maxValue.toFloat()
            pickerAnimator?.cancel()
            pickerAnimator = createAnimator(pickerMaxHeight, animatedToPickerMaxHeight, ValueAnimator.AnimatorUpdateListener { animation ->
                pickerMaxHeight = animation.animatedValue as Float
                invalidatePickerChart = true
                invalidate()
            }).apply { start() }
        }
    }

    override fun createHorizontalLinesData(newMaxHeight: Long, newMinHeight: Long, formatter: Int): ChartHorizontalLinesData {
        val data = chartData ?: return super.createHorizontalLinesData(newMaxHeight, newMinHeight, formatter)
        val k = if (data.linesK.size < 2) 1f else data.linesK[if (data.linesK[0] == 1f) 1 else 0]
        return ChartHorizontalLinesData(
            newMaxHeight,
            newMinHeight,
            useMinHeight,
            k,
            formatter,
            valueFormatter,
            signaturePaint,
            signaturePaint2
        )
    }
}
