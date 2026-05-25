package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import androidx.core.graphics.ColorUtils
import kotlin.math.max
import kotlin.math.round

class BarChartView(
    context: Context
) : BaseChartView<SignedBarChartData, BarViewData>(context) {
    init {
        superDraw = true
        useAlphaSignature = true
    }

    override fun init() {
        useMinHeight = true
        super.init()
    }

    override fun createLineViewData(line: ChartData.Line): BarViewData = BarViewData(line, style)

    private fun span(): Float {
        val s = currentMaxHeight - currentMinHeight
        return if (s == 0f) 1f else s
    }

    // Y position of the value 0 within the chart area, mapped against the current [min,max] range.
    private fun zeroLineY(): Float {
        val chartHeight = measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT
        val zeroPercentage = (0f - currentMinHeight) / span()
        return measuredHeight - chartBottom - zeroPercentage * chartHeight
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

        val p = if (data.xPercentage.size < 2) 1f else data.xPercentage[1] * fullWidth
        val chartHeight = measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT
        val zeroY = zeroLineY()

        lines.forEach { it.linesPathBottomSize = 0 }

        val selected = selectedIndex >= 0 && legendShowing
        for (i in start..end) {
            if (i == selectedIndex && selected) continue
            var positiveOffset = 0f
            var negativeOffset = 0f
            val xPoint = data.xPercentage[i] * fullWidth - offset
            for (line in lines) {
                if (!line.enabled && line.alpha == 0f) continue
                val value = line.line.y[i]
                val barHeight = value.toFloat() / span() * chartHeight * line.alpha
                val topY: Float
                val bottomY: Float
                if (value >= 0) {
                    bottomY = zeroY - positiveOffset
                    topY = bottomY - barHeight
                    positiveOffset += barHeight
                } else {
                    bottomY = zeroY + negativeOffset
                    topY = bottomY - barHeight // barHeight is negative -> draws downward
                    negativeOffset += -barHeight
                }
                line.linesPath[line.linesPathBottomSize++] = xPoint
                line.linesPath[line.linesPathBottomSize++] = topY
                line.linesPath[line.linesPathBottomSize++] = xPoint
                line.linesPath[line.linesPathBottomSize++] = bottomY
            }
        }

        for (line in lines) {
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
            canvas.drawLines(line.linesPath, 0, line.linesPathBottomSize, paint)
        }

        if (selected) {
            var positiveOffset = 0f
            var negativeOffset = 0f
            val xPoint = data.xPercentage[selectedIndex] * fullWidth - offset
            for (line in lines) {
                if (!line.enabled && line.alpha == 0f) continue
                val value = line.line.y[selectedIndex]
                val barHeight = value.toFloat() / span() * chartHeight * line.alpha
                val topY: Float
                val bottomY: Float
                if (value >= 0) {
                    bottomY = zeroY - positiveOffset
                    topY = bottomY - barHeight
                    positiveOffset += barHeight
                } else {
                    bottomY = zeroY + negativeOffset
                    topY = bottomY - barHeight
                    negativeOffset += -barHeight
                }
                line.paint.strokeWidth = p
                line.paint.alpha = (255 * transitionAlpha).toInt()
                canvas.drawLine(xPoint, topY, xPoint, bottomY, line.paint)
                line.paint.alpha = 255
            }
        }

        canvas.restore()
        canvas.restore()
    }

    override fun drawPickerChart(canvas: Canvas) {
        val data = chartData ?: return
        val n = data.xPercentage.size
        val nl = lines.size
        lines.forEach { it.linesPathBottomSize = 0 }
        val step = max(1, round(n / 200f).toInt())

        val maxH = if (ANIMATE_PICKER_SIZES) pickerMaxHeight else data.maxValue.toFloat()
        val minH = if (ANIMATE_PICKER_SIZES) pickerMinHeight else data.minValue.toFloat()
        val pickerSpan = if (maxH - minH == 0f) 1f else maxH - minH
        val zeroY = pikerHeight - ((0f - minH) / pickerSpan) * pikerHeight

        for (i in 0 until n) {
            if (i % step != 0) continue
            var positiveOffset = 0f
            var negativeOffset = 0f
            val xPoint = data.xPercentage[i] * pickerWidth
            for (k in 0 until nl) {
                val line = lines[k]
                if (!line.enabled && line.alpha == 0f) continue
                val value = line.line.y[i]
                val barHeight = value.toFloat() / pickerSpan * pikerHeight * line.alpha
                val topY: Float
                val bottomY: Float
                if (value >= 0) {
                    bottomY = zeroY - positiveOffset
                    topY = bottomY - barHeight
                    positiveOffset += barHeight
                } else {
                    bottomY = zeroY + negativeOffset
                    topY = bottomY - barHeight
                    negativeOffset += -barHeight
                }
                line.linesPath[line.linesPathBottomSize++] = xPoint
                line.linesPath[line.linesPathBottomSize++] = topY
                line.linesPath[line.linesPathBottomSize++] = xPoint
                line.linesPath[line.linesPathBottomSize++] = bottomY
            }
        }

        val p = if (data.xPercentage.size < 2) 1f else data.xPercentage[1] * pickerWidth
        for (line in lines) {
            line.paint.strokeWidth = p * step + 2
            line.paint.alpha = 255
            canvas.drawLines(line.linesPath, 0, line.linesPathBottomSize, line.paint)
        }
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

    override fun onCheckChanged() {
        chartData?.recomputeSums(lines.map { it.enabled })
        super.onCheckChanged()
    }

    override fun findMaxValue(startXIndex: Int, endXIndex: Int): Long =
        chartData?.findPositiveMax(startXIndex, endXIndex) ?: 0L

    override fun findMinValue(startXIndex: Int, endXIndex: Int): Long =
        chartData?.findNegativeMin(startXIndex, endXIndex) ?: 0L

    override fun initPickerMaxHeight() {
        val data = chartData ?: return
        pickerMaxHeight = 0f
        pickerMinHeight = 0f
        for (i in data.x.indices) {
            var pos = 0L
            var neg = 0L
            lines.forEachIndexed { index, line ->
                if (line.enabled) {
                    val v = line.line.y[i]
                    if (v >= 0) pos += v else neg += v
                }
            }
            if (pos > pickerMaxHeight) pickerMaxHeight = pos.toFloat()
            if (neg < pickerMinHeight) pickerMinHeight = neg.toFloat()
        }
        if (pickerMaxHeight == pickerMinHeight) {
            pickerMaxHeight++
            pickerMinHeight--
        }
    }

    override fun updatePickerMinMaxHeight() {
        if (!ANIMATE_PICKER_SIZES) return
        val data = chartData ?: return
        var maxValue = 0L
        var minValue = 0L
        for (i in data.x.indices) {
            var pos = 0L
            var neg = 0L
            for (line in lines) {
                if (line.enabled) {
                    val v = line.line.y[i]
                    if (v >= 0) pos += v else neg += v
                }
            }
            if (pos > maxValue) maxValue = pos
            if (neg < minValue) minValue = neg
        }
        if (maxValue.toFloat() != animatedToPickerMaxHeight || minValue.toFloat() != animatedToPickerMinHeight) {
            animatedToPickerMaxHeight = maxValue.toFloat()
            animatedToPickerMinHeight = minValue.toFloat()
            pickerAnimator?.cancel()
            val animatorSet = android.animation.AnimatorSet()
            val animators = mutableListOf<android.animation.Animator>(
                createAnimator(
                    pickerMaxHeight,
                    animatedToPickerMaxHeight,
                    ValueAnimator.AnimatorUpdateListener { animation ->
                        pickerMaxHeight = animation.animatedValue as Float
                        invalidatePickerChart = true
                        invalidate()
                    })
            )
            animators += createAnimator(
                pickerMinHeight,
                animatedToPickerMinHeight,
                ValueAnimator.AnimatorUpdateListener { animation ->
                    pickerMinHeight = animation.animatedValue as Float
                    invalidatePickerChart = true
                    invalidate()
                })
            animatorSet.playTogether(animators)
            pickerAnimator = animatorSet
            pickerAnimator?.start()
        }
    }

    override fun drawSelection(canvas: Canvas) {
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
