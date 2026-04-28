package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import org.mytonwallet.app_air.uicomponents.extensions.dp
import kotlin.math.abs
import kotlin.math.atan
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

@Suppress("UNCHECKED_CAST")
open class StackLinearChartView<T : StackLinearViewData>(
    context: Context
) : BaseChartView<StackLinearChartData, T>(context) {
    enum class ValueMode {
        ABSOLUTE,
        RELATIVE,
    }

    private val matrix = Matrix()
    private val mapPoints = FloatArray(2)
    private val ovalPath = Path()
    private var skipPoints: BooleanArray? = null
    private var startFromY: FloatArray? = null

    var animatePickerDuringLineAnimation: Boolean = false

    var valueMode: ValueMode = ValueMode.RELATIVE
        set(value) {
            if (field == value) return
            field = value
            chartData?.let {
                onPickerDataChanged(false, true, false)
                updatePickerMinMaxHeight()
            }
            invalidatePickerChart = true
            invalidate()
        }

    init {
        superDraw = true
        useAlphaSignature = true
        drawPointOnSelection = false
    }

    override fun createLineViewData(line: ChartData.Line): T = StackLinearViewData(line, style) as T

    override fun shouldAnimatePickerDuringLineAnimation(): Boolean =
        animatePickerDuringLineAnimation

    override fun drawChart(canvas: Canvas) {
        val data = chartData ?: return
        val fullWidth = chartWidth / (pickerDelegate.pickerEnd - pickerDelegate.pickerStart)
        val offset = fullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING
        val cX = chartArea.centerX()
        val cY = chartArea.centerY() + 16.dp

        for (line in lines) {
            line.chartPath.reset()
            line.chartPathPicker.reset()
        }

        canvas.save()
        if (skipPoints == null || skipPoints!!.size < data.lines.size) {
            skipPoints = BooleanArray(data.lines.size)
            startFromY = FloatArray(data.lines.size)
        }
        val localSkipPoints = skipPoints!!
        val localStartFromY = startFromY!!

        var transitionAlpha = 255
        var transitionProgressHalf = 0f
        if (transitionMode == TRANSITION_MODE_PARENT) {
            val params = transitionParams ?: return
            transitionProgressHalf = params.progress / 0.6f
            if (transitionProgressHalf > 1f) transitionProgressHalf = 1f
            ovalPath.reset()
            val radiusStart = max(chartArea.width(), chartArea.height())
            val radiusEnd = min(chartArea.width(), chartArea.height()) * 0.45f
            val radius = radiusEnd + ((radiusStart - radiusEnd) / 2f) * (1 - params.progress)
            val rectF = RectF(cX - radius, cY - radius, cX + radius, cY + radius)
            ovalPath.addRoundRect(rectF, radius, radius, Path.Direction.CW)
            canvas.clipPath(ovalPath)
        } else if (transitionMode == TRANSITION_MODE_ALPHA_ENTER) {
            transitionAlpha = ((transitionParams?.progress ?: 1f) * 255).toInt()
        }

        var dX = 0f
        var dY = 0f
        var x1 = 0f
        var y1 = 0f

        val p = if (data.xPercentage.size < 2) 1f else data.xPercentage[1] * fullWidth
        val additionalPoints = (HORIZONTAL_PADDING / p).toInt() + 1
        val localStart = max(0, startXIndex - additionalPoints - 1)
        val localEnd = min(data.xPercentage.size - 1, endXIndex + additionalPoints + 1)

        var startXPoint = 0f
        var endXPoint = 0f
        val chartHeight = measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT

        for (i in localStart..localEnd) {
            var stackOffset = 0f
            var sum = 0f
            var lastEnabled = 0
            var drawingLinesCount = 0
            for ((k, line) in lines.withIndex()) {
                if (!line.enabled && line.alpha == 0f) continue
                val value = getLineValue(line.line, i)
                if (value > 0) {
                    sum += value * line.alpha
                    drawingLinesCount++
                }
                lastEnabled = k
            }

            for ((k, line) in lines.withIndex()) {
                if (!line.enabled && line.alpha == 0f) continue
                val yPercentage = resolveLineHeightRatio(
                    value = getLineValue(line.line, i),
                    alpha = line.alpha,
                    sum = sum,
                    drawingLinesCount = drawingLinesCount,
                    maxHeight = currentMaxHeight
                )

                var xPoint = data.xPercentage[i] * fullWidth - offset
                val nextXPoint =
                    if (i == localEnd) measuredWidth.toFloat() else data.xPercentage[i + 1] * fullWidth - offset
                val height = yPercentage * chartHeight
                var yPoint = measuredHeight - chartBottom - height - stackOffset
                localStartFromY[k] = yPoint

                var angle = 0f
                var yPointZero = (measuredHeight - chartBottom).toFloat()
                var xPointZero = xPoint
                if (i == localEnd) {
                    endXPoint = xPoint
                } else if (i == localStart) {
                    startXPoint = xPoint
                }

                if (transitionMode == TRANSITION_MODE_PARENT && k != lastEnabled) {
                    val params = transitionParams ?: return
                    if (xPoint < cX) {
                        x1 = params.startX[k]
                        y1 = params.startY[k]
                    } else {
                        x1 = params.endX[k]
                        y1 = params.endY[k]
                    }
                    dX = cX - x1
                    dY = cY - y1
                    val yTo = dY * (xPoint - x1) / dX + y1
                    yPoint = yPoint * (1f - transitionProgressHalf) + yTo * transitionProgressHalf
                    yPointZero =
                        yPointZero * (1f - transitionProgressHalf) + yTo * transitionProgressHalf
                    val angleK = dY / dX
                    angle = if (angleK > 0) Math.toDegrees(-atan(angleK.toDouble()))
                        .toFloat() else Math.toDegrees(atan(abs(angleK).toDouble())).toFloat()
                    angle -= 90f

                    if (xPoint >= cX) {
                        mapPoints[0] = xPoint
                        mapPoints[1] = yPoint
                        matrix.reset()
                        matrix.postRotate(params.progress * angle, cX, cY)
                        matrix.mapPoints(mapPoints)
                        xPoint = mapPoints[0]
                        yPoint = mapPoints[1]
                        if (xPoint < cX) xPoint = cX

                        mapPoints[0] = xPointZero
                        mapPoints[1] = yPointZero
                        matrix.reset()
                        matrix.postRotate(params.progress * angle, cX, cY)
                        matrix.mapPoints(mapPoints)
                        yPointZero = mapPoints[1]
                        if (xPointZero < cX) xPointZero = cX
                    } else if (nextXPoint >= cX) {
                        xPointZero =
                            xPoint * (1f - transitionProgressHalf) + cX * transitionProgressHalf
                        xPoint = xPointZero
                        yPointZero =
                            yPoint * (1f - transitionProgressHalf) + cY * transitionProgressHalf
                        yPoint = yPointZero
                    } else {
                        mapPoints[0] = xPoint
                        mapPoints[1] = yPoint
                        matrix.reset()
                        matrix.postRotate(
                            params.progress * angle + params.progress * params.angle[k],
                            cX,
                            cY
                        )
                        matrix.mapPoints(mapPoints)
                        xPoint = mapPoints[0]
                        yPoint = mapPoints[1]

                        mapPoints[0] =
                            if (nextXPoint >= cX) xPointZero * (1f - params.progress) + cX * params.progress else xPointZero
                        mapPoints[1] = yPointZero
                        matrix.reset()
                        matrix.postRotate(
                            params.progress * angle + params.progress * params.angle[k],
                            cX,
                            cY
                        )
                        matrix.mapPoints(mapPoints)
                        xPointZero = mapPoints[0]
                        yPointZero = mapPoints[1]
                    }
                }

                if (i == localStart) {
                    var localX = 0f
                    var localY = measuredHeight.toFloat()
                    if (transitionMode == TRANSITION_MODE_PARENT && k != lastEnabled) {
                        val params = transitionParams ?: return
                        mapPoints[0] = localX - cX
                        mapPoints[1] = localY
                        matrix.reset()
                        matrix.postRotate(
                            params.progress * angle + params.progress * params.angle[k],
                            cX,
                            cY
                        )
                        matrix.mapPoints(mapPoints)
                        localX = mapPoints[0]
                        localY = mapPoints[1]
                    }
                    line.chartPath.moveTo(localX, localY)
                    localSkipPoints[k] = false
                }

                val transitionProgress = transitionParams?.progress ?: 0f
                if (
                    yPercentage == 0f &&
                    i > 0 &&
                    getLineValue(line.line, i - 1) == 0L &&
                    i < localEnd &&
                    getLineValue(line.line, i + 1) == 0L &&
                    transitionMode != TRANSITION_MODE_PARENT
                ) {
                    if (!localSkipPoints[k]) {
                        if (k == lastEnabled) line.chartPath.lineTo(
                            xPointZero,
                            yPointZero * (1f - transitionProgress)
                        )
                        else line.chartPath.lineTo(xPointZero, yPointZero)
                    }
                    localSkipPoints[k] = true
                } else {
                    if (localSkipPoints[k]) {
                        if (k == lastEnabled) line.chartPath.lineTo(
                            xPointZero,
                            yPointZero * (1f - transitionProgress)
                        )
                        else line.chartPath.lineTo(xPointZero, yPointZero)
                    }
                    if (k == lastEnabled) line.chartPath.lineTo(
                        xPoint,
                        yPoint * (1f - transitionProgress)
                    )
                    else line.chartPath.lineTo(xPoint, yPoint)
                    localSkipPoints[k] = false
                }

                if (i == localEnd) {
                    var localX = measuredWidth.toFloat()
                    var localY = measuredHeight.toFloat()
                    if (transitionMode == TRANSITION_MODE_PARENT && k != lastEnabled) {
                        val params = transitionParams ?: return
                        mapPoints[0] = localX + cX
                        mapPoints[1] = localY
                        matrix.reset()
                        matrix.postRotate(params.progress * params.angle[k], cX, cY)
                        matrix.mapPoints(mapPoints)
                        localX = mapPoints[0]
                        localY = mapPoints[1]
                    } else {
                        line.chartPath.lineTo(localX, localY)
                    }

                    if (transitionMode == TRANSITION_MODE_PARENT && k != lastEnabled) {
                        val params = transitionParams ?: return
                        x1 = params.startX[k]
                        y1 = params.startY[k]
                        dX = cX - x1
                        dY = cY - y1
                        val angleK = dY / dX
                        angle = if (angleK > 0) Math.toDegrees(-atan(angleK.toDouble()))
                            .toFloat() else Math.toDegrees(atan(abs(angleK).toDouble())).toFloat()
                        angle -= 90f

                        localX = params.startX[k]
                        localY = params.startY[k]
                        mapPoints[0] = localX
                        mapPoints[1] = localY
                        matrix.reset()
                        matrix.postRotate(
                            params.progress * angle + params.progress * params.angle[k],
                            cX,
                            cY
                        )
                        matrix.mapPoints(mapPoints)
                        localX = mapPoints[0]
                        localY = mapPoints[1]

                        val endQuarter: Int
                        val startQuarter: Int
                        if (abs(xPoint - localX) < 0.001f && ((localY < cY && yPoint < cY) || (localY > cY && yPoint > cY))) {
                            if (params.angle[k] == -180f) {
                                endQuarter = 0
                                startQuarter = 0
                            } else {
                                endQuarter = 0
                                startQuarter = 3
                            }
                        } else {
                            endQuarter = quarterForPoint(xPoint, yPoint)
                            startQuarter = quarterForPoint(localX, localY)
                        }

                        for (q in endQuarter..startQuarter) {
                            when (q) {
                                0 -> line.chartPath.lineTo(measuredWidth.toFloat(), 0f)
                                1 -> line.chartPath.lineTo(
                                    measuredWidth.toFloat(),
                                    measuredHeight.toFloat()
                                )

                                2 -> line.chartPath.lineTo(0f, measuredHeight.toFloat())
                                else -> line.chartPath.lineTo(0f, 0f)
                            }
                        }
                    }
                }

                stackOffset += height
            }
        }

        canvas.save()
        canvas.clipRect(
            startXPoint,
            SIGNATURE_TEXT_HEIGHT.toFloat(),
            endXPoint,
            (measuredHeight - chartBottom).toFloat()
        )
        for (k in lines.size - 1 downTo 0) {
            val line = lines[k]
            line.paint.alpha = transitionAlpha
            canvas.drawPath(line.chartPath, line.paint)
            line.paint.alpha = 255
        }
        canvas.restore()
        canvas.restore()
    }

    private fun quarterForPoint(x: Float, y: Float): Int {
        val cX = chartArea.centerX()
        val cY = chartArea.centerY() + 16.dp
        return when {
            x >= cX && y <= cY -> 0
            x >= cX && y >= cY -> 1
            x < cX && y >= cY -> 2
            else -> 3
        }
    }

    override fun drawPickerChart(canvas: Canvas) {
        val data = chartData ?: return
        val n = data.x.size
        if (n <= 0) {
            return
        }
        val pointWidth =
            if (n <= 1) pickerWidth.coerceAtLeast(1f) else data.xPercentage[1] * pickerWidth
        lines.forEach { it.chartPathPicker.reset() }

        for (i in 0 until n) {
            var stackOffset = 0f
            var sum = 0f
            var lastEnabled = 0
            var drawingLinesCount = 0
            for ((k, line) in lines.withIndex()) {
                if (!line.enabled && line.alpha == 0f) continue
                val value = getLineValue(line.line, i)
                if (value > 0) {
                    sum += value * line.alpha
                    drawingLinesCount++
                }
                lastEnabled = k
            }
            val xPoint = if (n <= 1) {
                pickerWidth / 2f
            } else {
                pointWidth / 2f + data.xPercentage[i] * (pickerWidth - pointWidth)
            }
            for ((k, line) in lines.withIndex()) {
                if (!line.enabled && line.alpha == 0f) continue
                val yPercentage = resolveLineHeightRatio(
                    value = getLineValue(line.line, i),
                    alpha = line.alpha,
                    sum = sum,
                    drawingLinesCount = drawingLinesCount,
                    maxHeight = pickerMaxHeight
                )
                val height = yPercentage * pikerHeight
                val yPoint = pikerHeight - height - stackOffset
                if (i == 0) {
                    line.chartPathPicker.moveTo(0f, pikerHeight.toFloat())
                    if (n == 1) {
                        line.chartPathPicker.lineTo(0f, yPoint)
                    }
                }
                line.chartPathPicker.lineTo(xPoint, yPoint)
                stackOffset += height
                if (i == n - 1) {
                    if (n == 1) {
                        line.chartPathPicker.lineTo(pickerWidth, yPoint)
                    }
                    line.chartPathPicker.lineTo(pickerWidth, pikerHeight.toFloat())
                    line.chartPathPicker.close()
                }
            }
        }

        for (k in lines.size - 1 downTo 0) {
            val line = lines[k]
            line.paint.alpha = 255
            line.paint.isAntiAlias = true
            line.paint.style = Paint.Style.FILL
            canvas.drawPath(line.chartPathPicker, line.paint)
            line.paint.style = Paint.Style.FILL
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

    override fun findMaxValue(startXIndex: Int, endXIndex: Int): Long {
        if (valueMode == ValueMode.RELATIVE) {
            return 100
        }
        return findStackedMaxValue(startXIndex, endXIndex, simplified = false)
    }

    override fun getMinDistance(): Float = 0.1f

    override fun initPickerMaxHeight() {
        if (valueMode == ValueMode.RELATIVE) {
            pickerMaxHeight = 100f
            pickerMinHeight = 0f
            return
        }
        pickerMaxHeight = findStackedMaxValue(
            0,
            (chartData?.simplifiedSize ?: 1) - 1,
            simplified = true
        ).toFloat()
        if (pickerMaxHeight <= 0f) {
            pickerMaxHeight = 1f
        }
        pickerMinHeight = 0f
    }

    override fun updatePickerMinMaxHeight() {
        if (valueMode == ValueMode.RELATIVE) {
            pickerMaxHeight = 100f
            pickerMinHeight = 0f
            invalidatePickerChart = true
            invalidate()
            return
        }
        if (!ANIMATE_PICKER_SIZES) {
            return
        }

        val maxValue = findStackedMaxValue(
            0,
            (chartData?.simplifiedSize ?: 1) - 1,
            simplified = true
        ).toFloat()
            .coerceAtLeast(1f)
        if (maxValue == animatedToPickerMaxHeight && animatedToPickerMinHeight == 0f) {
            return
        }

        animatedToPickerMaxHeight = maxValue
        animatedToPickerMinHeight = 0f
        pickerAnimator?.cancel()
        pickerAnimator = createAnimator(
            pickerMaxHeight,
            animatedToPickerMaxHeight,
            ValueAnimator.AnimatorUpdateListener { animation ->
                pickerMaxHeight = animation.animatedValue as Float
                invalidatePickerChart = true
                invalidate()
            }
        ).apply { start() }
    }

    override fun fillTransitionParams(params: TransitionParams) {
        val data = chartData ?: return
        val fullWidth = chartWidth / (pickerDelegate.pickerEnd - pickerDelegate.pickerStart)
        val offset = fullWidth * pickerDelegate.pickerStart - HORIZONTAL_PADDING
        val p = if (data.xPercentage.size < 2) 1f else data.xPercentage[1] * fullWidth
        val additionalPoints = (HORIZONTAL_PADDING / p).toInt() + 1
        val localStart = max(0, startXIndex - additionalPoints - 1)
        val localEnd = min(data.xPercentage.size - 1, endXIndex + additionalPoints + 1)

        params.startX = FloatArray(data.lines.size)
        params.startY = FloatArray(data.lines.size)
        params.endX = FloatArray(data.lines.size)
        params.endY = FloatArray(data.lines.size)
        params.angle = FloatArray(data.lines.size)

        for (j in 0..1) {
            val i = if (j == 1) localEnd else localStart
            var stackOffset = 0
            var sum = 0f
            var drawingLinesCount = 0
            for (line in lines) {
                if (!line.enabled && line.alpha == 0f) continue
                val value = getLineValue(line.line, i)
                if (value > 0) {
                    sum += value * line.alpha
                    drawingLinesCount++
                }
            }
            for ((k, line) in lines.withIndex()) {
                if (!line.enabled && line.alpha == 0f) continue
                val yPercentage = when {
                    valueMode == ValueMode.RELATIVE && drawingLinesCount == 1 && getLineValue(
                        line.line,
                        i
                    ) == 0L -> 0f

                    valueMode == ValueMode.RELATIVE && drawingLinesCount == 1 -> line.alpha
                    valueMode == ValueMode.RELATIVE && sum == 0f -> 0f
                    valueMode == ValueMode.RELATIVE -> getLineValue(line.line, i) * line.alpha / sum
                    currentMaxHeight <= 0f -> 0f
                    else -> getLineValue(line.line, i) * line.alpha / currentMaxHeight
                }
                val xPoint = data.xPercentage[i] * fullWidth - offset
                val height = yPercentage * (measuredHeight - chartBottom - SIGNATURE_TEXT_HEIGHT)
                val yPoint = measuredHeight - chartBottom - height - stackOffset
                stackOffset += height.toInt()
                if (j == 0) {
                    params.startX[k] = xPoint
                    params.startY[k] = yPoint
                } else {
                    params.endX[k] = xPoint
                    params.endY[k] = yPoint
                }
            }
        }
    }

    private fun findStackedMaxValue(startIndex: Int, endIndex: Int, simplified: Boolean): Long {
        val data = chartData ?: return 0L
        val size = if (simplified) data.simplifiedSize else data.x.size
        if (size <= 0) return 0L

        val safeStart = max(0, startIndex)
        val safeEnd = min(size - 1, endIndex)
        if (safeEnd < safeStart) return 0L

        var maxValue = 0f
        for (i in safeStart..safeEnd) {
            var sum = 0f
            for ((lineIndex, line) in lines.withIndex()) {
                if (!line.enabled) continue
                val value = if (simplified) getSimplifiedValue(
                    data,
                    lineIndex,
                    i
                ) else getLineValue(line.line, i)
                sum += value.toFloat()
            }
            if (sum > maxValue) {
                maxValue = sum
            }
        }
        return maxValue.roundToLong()
    }

    private fun getLineValue(line: ChartData.Line, index: Int): Long {
        return if (index in line.y.indices) line.y[index] else 0L
    }

    private fun getSimplifiedValue(data: StackLinearChartData, lineIndex: Int, index: Int): Long {
        if (lineIndex !in data.simplifiedY.indices) return 0L
        val values = data.simplifiedY[lineIndex]
        return if (index in values.indices) values[index] else 0L
    }

    private fun resolveLineHeightRatio(
        value: Long,
        alpha: Float,
        sum: Float,
        drawingLinesCount: Int,
        maxHeight: Float
    ): Float {
        return when {
            valueMode == ValueMode.RELATIVE && drawingLinesCount == 1 && value == 0L -> 0f
            valueMode == ValueMode.RELATIVE && drawingLinesCount == 1 -> alpha
            valueMode == ValueMode.RELATIVE && sum == 0f -> 0f
            valueMode == ValueMode.RELATIVE -> value * alpha / sum
            maxHeight <= 0f -> 0f
            else -> value * alpha / maxHeight
        }
    }
}
