package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import kotlin.math.max
import kotlin.math.min

class LinearChartView(
    context: Context
) : BaseChartView<ChartData, LineViewData>(context) {
    override fun init() {
        useMinHeight = true
        super.init()
    }

    override fun drawChart(canvas: Canvas) {
        val data = chartData ?: return
        val fullWidth = chartWidth / (pickerDelegate.pickerEnd - pickerDelegate.pickerStart)
        val offset = fullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING

        for (line in lines) {
            if (!line.enabled && line.alpha == 0f) {
                continue
            }

            var j = 0
            val p = if (data.xPercentage.size < 2) 0f else data.xPercentage[1] * fullWidth
            val y = line.line.y
            val additionalPoints = (HORIZONTAL_PADDING / p).toInt() + 1

            line.chartPath.reset()
            var first = true

            val localStart = max(0, startXIndex - additionalPoints)
            val localEnd = min(data.xPercentage.size - 1, endXIndex + additionalPoints)
            for (i in localStart..localEnd) {
                if (y[i] < 0) {
                    continue
                }
                val xPoint = data.xPercentage[i] * fullWidth - offset
                val yPercentage = (y[i] - currentMinHeight) / (currentMaxHeight - currentMinHeight)
                val padding = line.paint.strokeWidth / 2f
                val yPoint =
                    measuredHeight - chartBottom - padding - yPercentage * (measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT - padding)

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
                    canvas.scale(
                        params.progress,
                        if (params.needScaleY) params.progress else 1f,
                        params.pX,
                        params.pY
                    )
                }

                TRANSITION_MODE_ALPHA_ENTER -> transitionAlpha = transitionParams?.progress ?: 1f
            }
            line.paint.alpha = (255 * line.alpha * transitionAlpha).toInt()
            line.paint.strokeCap =
                if (endXIndex - startXIndex > 100) Paint.Cap.SQUARE else Paint.Cap.ROUND
            if (!USE_LINES) {
                canvas.drawPath(line.chartPath, line.paint)
            } else {
                canvas.drawLines(line.linesPath, 0, j, line.paint)
            }
            canvas.restore()
        }
    }

    override fun drawPickerChart(canvas: Canvas) {
        lines.forEach { line ->
            val data = chartData ?: return
            if (!line.enabled && line.alpha == 0f) {
                return@forEach
            }
            line.bottomLinePath.reset()
            val n = data.xPercentage.size
            var j = 0
            val y = line.line.y
            line.chartPath.reset()
            for (i in 0 until n) {
                if (y[i] < 0) {
                    continue
                }
                val xPoint = data.xPercentage[i] * pickerWidth
                val h = if (ANIMATE_PICKER_SIZES) pickerMaxHeight else data.maxValue.toFloat()
                val hMin = if (ANIMATE_PICKER_SIZES) pickerMinHeight else data.minValue.toFloat()
                val yPercentage = (y[i] - hMin) / (h - hMin)
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
            if (USE_LINES) {
                canvas.drawLines(
                    line.linesPathBottom,
                    0,
                    line.linesPathBottomSize,
                    line.bottomLinePaint
                )
            } else {
                canvas.drawPath(line.bottomLinePath, line.bottomLinePaint)
            }
        }
    }

    override fun createLineViewData(line: ChartData.Line): LineViewData =
        LineViewData(line, false, style)
}
