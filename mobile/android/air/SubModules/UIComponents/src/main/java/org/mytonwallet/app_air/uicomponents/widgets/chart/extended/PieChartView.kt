package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.TextPaint
import android.view.HapticFeedbackConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlin.math.sin
import kotlin.math.sqrt

class PieChartView(
    context: Context
) : StackLinearChartView<PieChartViewData>(context) {
    private var values: FloatArray? = null
    private var darawingValuesPercentage: FloatArray? = null
    private var sum = 0f
    private var isEmpty = false
    private var currentSelection = -1
    private val rectF = RectF()
    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private var MIN_TEXT_SIZE = 9.dp.toFloat()
    private var MAX_TEXT_SIZE = 13.dp.toFloat()
    private val lookupTable = Array(101) { "" }
    private lateinit var pieLegendView: PieLegendView
    private var emptyDataAlpha = 1f
    private var oldW = 0
    private var lastStartIndex = -1
    private var lastEndIndex = -1

    init {
        for (i in 1..100) {
            lookupTable[i] = "$i%"
        }
        textPaint.textAlign = Paint.Align.CENTER
        textPaint.color = Color.WHITE
        textPaint.typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        canCaptureChartSelection = true
    }

    override fun drawChart(canvas: Canvas) {
        val data = chartData ?: return
        val valuesPercentage = darawingValuesPercentage ?: return
        var transitionAlpha = 255

        canvas.save()
        if (transitionMode == TRANSITION_MODE_CHILD) {
            val progress = transitionParams?.progress ?: 1f
            transitionAlpha = (progress * progress * 255).toInt()
        }

        if (isEmpty) {
            if (emptyDataAlpha != 0f) {
                emptyDataAlpha -= 0.12f
                if (emptyDataAlpha < 0f) emptyDataAlpha = 0f
                invalidate()
            }
        } else if (emptyDataAlpha != 1f) {
            emptyDataAlpha += 0.12f
            if (emptyDataAlpha > 1f) emptyDataAlpha = 1f
            invalidate()
        }

        transitionAlpha = (transitionAlpha * emptyDataAlpha).toInt()
        val sc = 0.4f + emptyDataAlpha * 0.6f
        canvas.scale(sc, sc, chartArea.centerX(), chartArea.centerY())

        val radius = (min(chartArea.width(), chartArea.height()) * 0.45f).toInt()
        rectF.set(
            chartArea.centerX() - radius,
            chartArea.centerY() + 16.dp - radius,
            chartArea.centerX() + radius,
            chartArea.centerY() + 16.dp + radius
        )

        var a = -90f
        var localSum = 0f
        for (line in lines) {
            localSum += line.drawingPart * line.alpha
        }
        if (localSum == 0f) {
            canvas.restore()
            return
        }

        for ((i, line) in lines.withIndex()) {
            if (line.alpha <= 0f && !line.enabled) continue
            line.paint.alpha = transitionAlpha
            val currentPercent = line.drawingPart / localSum * line.alpha
            valuesPercentage[i] = currentPercent
            if (currentPercent == 0f) continue
            canvas.save()
            val textAngle = a + currentPercent / 2f * 360f
            if (line.selectionA > 0f) {
                val ai = INTERPOLATOR.getInterpolation(line.selectionA)
                canvas.translate(
                    (cos(Math.toRadians(textAngle.toDouble())) * 8.dp * ai).toFloat(),
                    (sin(Math.toRadians(textAngle.toDouble())) * 8.dp * ai).toFloat()
                )
            }
            line.paint.style = Paint.Style.FILL_AND_STROKE
            line.paint.strokeWidth = 1f
            line.paint.isAntiAlias = !USE_LINES
            if (transitionMode != TRANSITION_MODE_CHILD) {
                canvas.drawArc(rectF, a, currentPercent * 360f, true, line.paint)
                line.paint.style = Paint.Style.STROKE
                canvas.restore()
            }
            line.paint.alpha = 255
            a += currentPercent * 360f
        }

        a = -90f
        for ((i, line) in lines.withIndex()) {
            if (line.alpha <= 0f && !line.enabled) continue
            val currentPercent = line.drawingPart * line.alpha / localSum
            canvas.save()
            val textAngle = a + currentPercent / 2f * 360f
            if (line.selectionA > 0f) {
                val ai = INTERPOLATOR.getInterpolation(line.selectionA)
                canvas.translate(
                    (cos(Math.toRadians(textAngle.toDouble())) * 8.dp * ai).toFloat(),
                    (sin(Math.toRadians(textAngle.toDouble())) * 8.dp * ai).toFloat()
                )
            }
            val percent = (100f * currentPercent).toInt()
            if (currentPercent >= 0.02f && percent > 0 && percent <= 100) {
                val rText = (rectF.width() * 0.42f * sqrt(1f - currentPercent))
                textPaint.textSize = MIN_TEXT_SIZE + currentPercent * MAX_TEXT_SIZE
                textPaint.alpha = (transitionAlpha * line.alpha).toInt()
                canvas.drawText(
                    lookupTable[percent],
                    (rectF.centerX() + rText * cos(Math.toRadians(textAngle.toDouble()))).toFloat(),
                    (rectF.centerY() + rText * sin(Math.toRadians(textAngle.toDouble()))).toFloat() - ((textPaint.descent() + textPaint.ascent()) / 2),
                    textPaint
                )
            }
            canvas.restore()
            line.paint.alpha = 255
            a += currentPercent * 360f
        }

        canvas.restore()
    }

    override fun drawPickerChart(canvas: Canvas) {
        val data = chartData ?: return
        val n = data.xPercentage.size
        val nl = lines.size
        lines.forEach { it.linesPathBottomSize = 0 }
        val p = (1f / data.xPercentage.size) * pickerWidth

        for (i in 0 until n) {
            var stackOffset = 0f
            val xPoint = p / 2 + data.xPercentage[i] * (pickerWidth - p)
            var localSum = 0f
            var drawingLinesCount = 0
            var allDisabled = true
            for (line in lines) {
                if (!line.enabled && line.alpha == 0f) continue
                val v = line.line.y[i] * line.alpha
                localSum += v
                if (v > 0) {
                    drawingLinesCount++
                    if (line.enabled) allDisabled = false
                }
            }
            for (line in lines) {
                if (!line.enabled && line.alpha == 0f) continue
                val y = line.line.y
                val yPercentage = when {
                    valueMode == ValueMode.RELATIVE && drawingLinesCount == 1 && y[i] == 0L -> 0f
                    valueMode == ValueMode.RELATIVE && drawingLinesCount == 1 -> line.alpha
                    valueMode == ValueMode.RELATIVE && localSum == 0f -> 0f
                    valueMode == ValueMode.RELATIVE && allDisabled -> (y[i] / localSum) * line.alpha * line.alpha
                    valueMode == ValueMode.RELATIVE -> (y[i] / localSum) * line.alpha
                    pickerMaxHeight <= 0f -> 0f
                    else -> y[i] * line.alpha / pickerMaxHeight
                }
                val yPoint = yPercentage * pikerHeight
                line.linesPath[line.linesPathBottomSize++] = xPoint
                line.linesPath[line.linesPathBottomSize++] = pikerHeight - yPoint - stackOffset
                line.linesPath[line.linesPathBottomSize++] = xPoint
                line.linesPath[line.linesPathBottomSize++] = pikerHeight - stackOffset
                stackOffset += yPoint
            }
        }

        for (line in lines) {
            line.paint.strokeWidth = p
            line.paint.alpha = 255
            line.paint.isAntiAlias = false
            canvas.drawLines(line.linesPath, 0, line.linesPathBottomSize, line.paint)
        }
    }

    override fun drawBottomLine(canvas: Canvas) {
    }

    override fun drawSelection(canvas: Canvas) {
    }

    override fun drawHorizontalLines(canvas: Canvas, a: ChartHorizontalLinesData) {
    }

    override fun drawSignaturesToHorizontalLines(canvas: Canvas, a: ChartHorizontalLinesData) {
    }

    override fun drawBottomSignature(canvas: Canvas) {
    }

    override fun setData(chartData: StackLinearChartData?): Boolean {
        val updated = super.setData(chartData)
        if (chartData != null) {
            values = FloatArray(chartData.lines.size)
            darawingValuesPercentage = FloatArray(chartData.lines.size)
            onPickerDataChanged(false, true, false)
        }
        return updated
    }

    override fun createLineViewData(line: ChartData.Line): PieChartViewData =
        PieChartViewData(line, style)

    override fun selectXOnChart(x: Int, y: Int) {
        val data = chartData ?: return
        if (isEmpty) return
        val theta = atan2(
            (chartArea.centerY() + 16.dp - y).toDouble(),
            (chartArea.centerX() - x).toDouble()
        )
        var a = (Math.toDegrees(theta) - 90).toFloat()
        if (a < 0) a += 360f
        a /= 360f

        val percentages = darawingValuesPercentage ?: return
        var p = 0f
        var newSelection = -1
        var selectionStartA = 0f
        var selectionEndA = 0f
        for (i in lines.indices) {
            val line = lines[i]
            if (!line.enabled && line.alpha == 0f) continue
            if (a > p && a < p + percentages[i]) {
                newSelection = i
                selectionStartA = p
                selectionEndA = p + percentages[i]
                break
            }
            p += percentages[i]
        }

        if (currentSelection != newSelection && newSelection >= 0) {
            currentSelection = newSelection
            invalidate()
            pieLegendView.visibility = VISIBLE
            val l = lines[newSelection]
            val percentagePrefix = if (valueMode == ValueMode.RELATIVE) {
                formatLegendPercentage(percentages[newSelection])
            } else {
                null
            }
            pieLegendView.setData(
                l.line.name,
                values?.get(currentSelection)?.roundToLong() ?: 0L,
                l.lineColor,
                percentagePrefix
            )
            pieLegendView.measure(
                MeasureSpec.makeMeasureSpec(measuredWidth, MeasureSpec.AT_MOST),
                MeasureSpec.makeMeasureSpec(measuredHeight, MeasureSpec.AT_MOST)
            )

            val r = rectF.width() / 2
            var xl = min(
                rectF.centerX() + r * cos(Math.toRadians((selectionEndA * 360f - 90f).toDouble())),
                rectF.centerX() + r * cos(Math.toRadians((selectionStartA * 360f - 90f).toDouble()))
            ).toInt()

            if (xl < 0) xl = 0
            if (xl + pieLegendView.measuredWidth > measuredWidth - 16.dp) {
                xl -= xl + pieLegendView.measuredWidth - (measuredWidth - 16.dp)
            }

            var yl = min(
                rectF.centerY() + r * sin(Math.toRadians((selectionStartA * 360f - 90f).toDouble())),
                rectF.centerY() + r * sin(Math.toRadians((selectionEndA * 360f - 90f).toDouble()))
            ).toInt()
            yl = min(rectF.centerY().toInt(), yl)
            yl -= 50.dp

            val tooltipSafeInset = 8.dp
            val minLegendY = tooltipSafeInset
            val maxLegendY = (measuredHeight - pieLegendView.measuredHeight - tooltipSafeInset)
                .coerceAtLeast(minLegendY)
            yl = yl.coerceIn(minLegendY, maxLegendY)

            pieLegendView.translationX = xl.toFloat()
            pieLegendView.translationY = yl.toFloat()
            performHapticFeedback(HapticFeedbackConstants.TEXT_HANDLE_MOVE)
        }
        moveLegend()
    }

    override fun onDraw(canvas: Canvas) {
        if (chartData != null) {
            for ((i, line) in lines.withIndex()) {
                if (i == currentSelection) {
                    if (line.selectionA < 1f) {
                        line.selectionA += 0.1f
                        if (line.selectionA > 1f) line.selectionA = 1f
                        invalidate()
                    }
                } else if (line.selectionA > 0f) {
                    line.selectionA -= 0.1f
                    if (line.selectionA < 0f) line.selectionA = 0f
                    invalidate()
                }
            }
        }
        super.onDraw(canvas)
    }

    override fun onActionUp() {
        currentSelection = -1
        pieLegendView.visibility = GONE
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        if (measuredWidth != oldW) {
            oldW = measuredWidth
            val r = (min(chartArea.width(), chartArea.height()) * 0.45f).toInt()
            MIN_TEXT_SIZE = (r / 13).toFloat()
            MAX_TEXT_SIZE = (r / 7).toFloat()
        }
    }

    override fun updatePicker(chartData: ChartData, d: Long) {
        val n = chartData.x.size
        val startOfDay = d - d % 86400000L
        var startIndex = 0
        for (i in 0 until n) {
            if (startOfDay >= chartData.x[i]) startIndex = i
        }
        val p = if (chartData.xPercentage.size < 2) 0.5f else 1f / chartData.x.size
        when {
            startIndex == 0 -> {
                pickerDelegate.pickerStart = 0f
                pickerDelegate.pickerEnd = p
                return
            }

            startIndex >= chartData.x.size - 1 -> {
                pickerDelegate.pickerStart = 1f - p
                pickerDelegate.pickerEnd = 1f
                return
            }

            else -> {
                pickerDelegate.pickerStart = p * startIndex
                pickerDelegate.pickerEnd = pickerDelegate.pickerStart + p
                if (pickerDelegate.pickerEnd > 1f) pickerDelegate.pickerEnd = 1f
            }
        }
        onPickerDataChanged(true, true, false)
    }

    override fun createLegendView(): LegendSignatureView {
        pieLegendView = PieLegendView(context).apply {
            this.style = this@PieChartView.style
        }
        return pieLegendView
    }

    override fun onPickerDataChanged(animated: Boolean, force: Boolean, useAniamtor: Boolean) {
        super.onPickerDataChanged(animated, force, useAniamtor)
        val data = chartData ?: return
        if (data.xPercentage.isEmpty()) return
        updateCharValues(pickerDelegate.pickerStart, pickerDelegate.pickerEnd, force)
    }

    private fun updateCharValues(startPercentage: Float, endPercentage: Float, force: Boolean) {
        val data = chartData ?: return
        val localValues = values ?: return
        val n = data.xPercentage.size
        val nl = lines.size

        var startIndex = -1
        var endIndex = -1
        for (j in 0 until n) {
            if (data.xPercentage[j] >= startPercentage && startIndex == -1) {
                startIndex = j
            }
            if (data.xPercentage[j] <= endPercentage) {
                endIndex = j
            }
        }
        if (endIndex < startIndex) {
            startIndex = endIndex
        }
        if (!force && lastEndIndex == endIndex && lastStartIndex == startIndex) {
            return
        }
        lastEndIndex = endIndex
        lastStartIndex = startIndex

        isEmpty = true
        sum = 0f
        for (i in 0 until nl) {
            localValues[i] = 0f
        }

        for (j in startIndex..endIndex) {
            for (i in 0 until nl) {
                localValues[i] += data.lines[i].y[j]
                sum += data.lines[i].y[j]
                if (isEmpty && lines[i].enabled && data.lines[i].y[j] > 0) {
                    isEmpty = false
                }
            }
        }

        if (!force) {
            for (i in 0 until nl) {
                val line = lines[i]
                line.animator?.cancel()
                val animateTo = if (sum == 0f) 0f else localValues[i] / sum
                line.animator = createAnimator(
                    line.drawingPart,
                    animateTo,
                    ValueAnimator.AnimatorUpdateListener { animation ->
                        line.drawingPart = animation.animatedValue as Float
                        invalidate()
                    }).apply { start() }
            }
        } else {
            for (i in 0 until nl) {
                lines[i].drawingPart = if (sum == 0f) 0f else localValues[i] / sum
            }
        }
    }

    override fun onPickerJumpTo(start: Float, end: Float, force: Boolean) {
        if (chartData == null) return
        if (force) {
            updateCharValues(start, end, false)
        } else {
            updateIndexes()
            invalidate()
        }
    }

    override fun fillTransitionParams(params: TransitionParams) {
        val percentages = darawingValuesPercentage ?: return
        var p = 0f
        for (i in percentages.indices) {
            p += percentages[i]
            params.angle[i] = p * 360f - 180f
        }
    }

    private fun formatLegendPercentage(ratio: Float): String {
        val percent = 100f * ratio
        return if (percent < 10f && percent != 0f) {
            String.format(java.util.Locale.ENGLISH, "%.1f%%", percent)
        } else {
            "${percent.roundToInt()}%"
        }
    }
}
