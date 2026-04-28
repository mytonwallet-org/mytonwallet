package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import androidx.core.graphics.ColorUtils
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round

class StackBarChartView(
    context: Context
) : BaseChartView<StackBarChartData, StackBarViewData>(context) {

    private var yMaxPoints: LongArray? = null

    init {
        superDraw = true
        useAlphaSignature = true
    }

    override fun createLineViewData(line: ChartData.Line): StackBarViewData =
        StackBarViewData(line, style)

    override fun drawChart(canvas: Canvas) {
        val data = chartData ?: return
        val fullWidth = chartWidth / (pickerDelegate.pickerEnd - pickerDelegate.pickerStart)
        val offset = fullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING
        val p: Float
        val lineWidth: Float
        if (data.xPercentage.size < 2) {
            p = 1f
            lineWidth = 1f
        } else {
            p = data.xPercentage[1] * fullWidth
            lineWidth = data.xPercentage[1] * (fullWidth - p)
        }
        val additionalPoints = (HORIZONTAL_PADDING / p).toInt() + 1
        val localStart = max(0, startXIndex - additionalPoints - 2)
        val localEnd = min(data.xPercentage.size - 1, endXIndex + additionalPoints + 2)

        lines.forEach { it.linesPathBottomSize = 0 }

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

            TRANSITION_MODE_ALPHA_ENTER -> transitionAlpha = transitionParams?.progress ?: 1f
        }

        val selected = selectedIndex >= 0 && legendShowing
        for (i in localStart..localEnd) {
            var stackOffset = 0f
            if (selectedIndex == i && selected) continue
            for (line in lines) {
                if (!line.enabled && line.alpha == 0f) continue
                val y = line.line.y
                val xPoint = p / 2 + data.xPercentage[i] * (fullWidth - p) - offset
                val yPercentage = y[i] / currentMaxHeight
                val height =
                    yPercentage * (measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT) * line.alpha
                val yPoint = measuredHeight - chartBottom - height
                line.linesPath[line.linesPathBottomSize++] = xPoint
                line.linesPath[line.linesPathBottomSize++] = yPoint - stackOffset
                line.linesPath[line.linesPathBottomSize++] = xPoint
                line.linesPath[line.linesPathBottomSize++] =
                    measuredHeight - chartBottom - stackOffset.toFloat()
                stackOffset += height
            }
        }

        for (line in lines) {
            val paint: Paint = if (selected || postTransition) line.unselectedPaint else line.paint
            if (selected) {
                line.unselectedPaint.color =
                    ColorUtils.blendARGB(line.lineColor, line.blendColor, selectionA)
            }
            if (postTransition) {
                line.unselectedPaint.color =
                    ColorUtils.blendARGB(line.lineColor, line.blendColor, 1f)
            }
            paint.alpha = (255 * transitionAlpha).toInt()
            paint.strokeWidth = lineWidth
            canvas.drawLines(line.linesPath, 0, line.linesPathBottomSize, paint)
        }

        if (selected) {
            var stackOffset = 0f
            for (line in lines) {
                if (!line.enabled && line.alpha == 0f) continue
                val y = line.line.y
                val xPoint = p / 2 + data.xPercentage[selectedIndex] * (fullWidth - p) - offset
                val yPercentage = y[selectedIndex] / currentMaxHeight
                val height =
                    yPercentage * (measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT) * line.alpha
                val yPoint = measuredHeight - chartBottom - height
                line.paint.strokeWidth = lineWidth
                line.paint.alpha = (255 * transitionAlpha).toInt()
                canvas.drawLine(
                    xPoint,
                    yPoint - stackOffset,
                    xPoint,
                    measuredHeight - chartBottom - stackOffset,
                    line.paint
                )
                stackOffset += height
            }
        }
        canvas.restore()
    }

    override fun selectXOnChart(x: Int, y: Int) {
        val data = chartData ?: return
        val oldSelectedIndex = selectedIndex
        val offset = chartFullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING
        val p = if (data.xPercentage.size < 2) 1f else data.xPercentage[1] * chartFullWidth
        val xP = (offset + x) / (chartFullWidth - p)
        selectedCoordinate = xP
        when {
            xP < 0 -> {
                selectedIndex = 0
                selectedCoordinate = 0f
            }

            xP > 1 -> {
                selectedIndex = data.x.size - 1
                selectedCoordinate = 1f
            }

            else -> {
                selectedIndex = data.findIndex(startXIndex, endXIndex, xP)
                if (selectedIndex > endXIndex) selectedIndex = endXIndex
                if (selectedIndex < startXIndex) selectedIndex = startXIndex
            }
        }
        if (oldSelectedIndex != selectedIndex) {
            legendShowing = true
            animateLegend(true)
            moveLegend(offset)
            notifyDateSelectionChanged()
            invalidate()
            runSmoothHaptic()
        }
    }

    override fun drawPickerChart(canvas: Canvas) {
        val data = chartData ?: return
        val n = data.xPercentage.size
        val nl = lines.size
        lines.forEach { it.linesPathBottomSize = 0 }
        val step = max(1, round(n / 200f).toInt())
        if (yMaxPoints == null || yMaxPoints!!.size < nl) {
            yMaxPoints = LongArray(nl)
        }
        val yMax = yMaxPoints!!

        for (i in 0 until n) {
            var stackOffset = 0f
            val xPoint = data.xPercentage[i] * pickerWidth
            for (k in 0 until nl) {
                val line = lines[k]
                if (!line.enabled && line.alpha == 0f) continue
                val y = line.line.y[i]
                if (y > yMax[k]) yMax[k] = y
            }
            if (i % step == 0) {
                for (k in 0 until nl) {
                    val line = lines[k]
                    if (!line.enabled && line.alpha == 0f) continue
                    val h = if (ANIMATE_PICKER_SIZES) pickerMaxHeight else data.maxValue.toFloat()
                    val yPercentage = yMax[k] / h * line.alpha
                    val yPoint = yPercentage * pikerHeight
                    line.linesPath[line.linesPathBottomSize++] = xPoint
                    line.linesPath[line.linesPathBottomSize++] = pikerHeight - yPoint - stackOffset
                    line.linesPath[line.linesPathBottomSize++] = xPoint
                    line.linesPath[line.linesPathBottomSize++] = pikerHeight - stackOffset
                    stackOffset += yPoint
                    yMax[k] = 0
                }
            }
        }

        val p = if (data.xPercentage.size < 2) 1f else data.xPercentage[1] * pickerWidth
        for (line in lines) {
            line.paint.strokeWidth = p * step
            line.paint.alpha = 255
            canvas.drawLines(line.linesPath, 0, line.linesPathBottomSize, line.paint)
        }
    }

    override fun onCheckChanged() {
        val data = chartData ?: return
        val n = data.lines[0].y.size
        val k = data.lines.size
        data.ySum = LongArray(n)
        for (i in 0 until n) {
            data.ySum[i] = 0
            for (j in 0 until k) {
                if (lines[j].enabled) {
                    data.ySum[i] += data.lines[j].y[i]
                }
            }
        }
        data.ySumSegmentTree = SegmentTree(data.ySum)
        super.onCheckChanged()
    }

    override fun drawSelection(canvas: Canvas) {
    }

    override fun findMaxValue(startXIndex: Int, endXIndex: Int): Long =
        chartData?.findMax(startXIndex, endXIndex) ?: 0

    override fun updatePickerMinMaxHeight() {
        if (!ANIMATE_PICKER_SIZES) return
        val data = chartData ?: return
        var maxValue = 0L
        for (i in data.x.indices) {
            var h = 0L
            for (line in lines) {
                if (line.enabled) h += line.line.y[i]
            }
            if (h > maxValue) maxValue = h
        }
        if (maxValue > 0 && maxValue.toFloat() != animatedToPickerMaxHeight) {
            animatedToPickerMaxHeight = maxValue.toFloat()
            pickerAnimator?.cancel()
            pickerAnimator = createAnimator(
                pickerMaxHeight,
                animatedToPickerMaxHeight,
                ValueAnimator.AnimatorUpdateListener { animation ->
                    pickerMaxHeight = animation.animatedValue as Float
                    invalidatePickerChart = true
                    invalidate()
                }).apply { start() }
        }
    }

    override fun initPickerMaxHeight() {
        super.initPickerMaxHeight()
        pickerMaxHeight = 0f
        val data = chartData ?: return
        for (i in data.x.indices) {
            var h = 0L
            for (line in lines) {
                if (line.enabled) h += line.line.y[i]
            }
            if (h > pickerMaxHeight) pickerMaxHeight = h.toFloat()
        }
    }

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
