package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.graphics.Canvas
import android.graphics.RectF
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import org.mytonwallet.app_air.uicomponents.extensions.dp
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToLong

class ChartHorizontalLinesData(
    newMaxHeight: Long,
    newMinHeight: Long,
    useMinHeight: Boolean,
    k: Float,
    formatter: Int,
    private val valueFormatter: ChartValueFormatter? = null,
    firstTextPaint: TextPaint,
    secondTextPaint: TextPaint
) {
    var values: LongArray
    var valuesStr: Array<CharSequence?>
    var valuesStr2: Array<CharSequence?>? = null
    private var layouts: Array<StaticLayout?>
    private var layouts2: Array<StaticLayout?>? = null
    var alpha: Int = 0
    var fixedAlpha: Int = 255
    private var formatterTON: DecimalFormat? = null

    init {
        val tickValues = computeAxisTickValues(newMaxHeight, newMinHeight, useMinHeight)
        val step = tickValues.step
        val n = tickValues.count
        values = LongArray(n)
        valuesStr = arrayOfNulls(n)
        layouts = arrayOfNulls(n)
        if (k > 0f) {
            valuesStr2 = arrayOfNulls(n)
            layouts2 = arrayOfNulls(n)
        }

        if (!useMinHeight) {
            val skipFloatValues = step / k < 1
            for (i in 1 until n) {
                values[i] = tickValues.min + i * step
                valuesStr[i] = format(0, firstTextPaint, values[i], formatter)
                if (k > 0f) {
                    val value2 = values[i] / k
                    valuesStr2!![i] = if (skipFloatValues) {
                        if (value2 - value2.toLong() < 0.01f || formatter == ChartData.FORMATTER_TON || formatter == ChartData.FORMATTER_XTR) {
                            format(1, secondTextPaint, value2.toLong(), formatter)
                        } else {
                            ""
                        }
                    } else {
                        format(1, secondTextPaint, value2.toLong(), formatter)
                    }
                }
            }
        } else {
            val skipFloatValues = step / k < 1f
            for (i in 0 until n) {
                values[i] = tickValues.min + i * step
                valuesStr[i] = format(0, firstTextPaint, values[i], formatter)
                if (k > 0f) {
                    val value2 = values[i] / k
                    valuesStr2!![i] = if (skipFloatValues) {
                        if (value2 - value2.toLong() < 0.01f || formatter == ChartData.FORMATTER_TON || formatter == ChartData.FORMATTER_XTR) {
                            format(1, secondTextPaint, value2.toLong(), formatter)
                        } else {
                            ""
                        }
                    } else {
                        format(1, secondTextPaint, value2.toLong(), formatter)
                    }
                }
            }
        }
    }

    fun format(a: Int, paint: TextPaint, v: Long, formatter: Int): CharSequence {
        if (formatter == ChartData.FORMATTER_TON) {
            if (a == 1) return "≈" + ChartFormatters.formatCurrency(v, "USD")
            if (formatterTON == null) {
                val symbols = DecimalFormatSymbols(Locale.US)
                symbols.decimalSeparator = '.'
                formatterTON = DecimalFormat("#.##", symbols).apply {
                    minimumFractionDigits = 2
                    maximumFractionDigits = 6
                    isGroupingUsed = false
                }
            }
            formatterTON!!.maximumFractionDigits = if (v > 1_000_000_000L) 2 else 6
            return ChannelMonetizationLayout.replaceTON("TON " + formatterTON!!.format(v / 1_000_000_000.0), paint, .8f, -0.66f.dp, false)
        } else if (formatter == ChartData.FORMATTER_XTR) {
            if (a == 1) return "≈" + ChartFormatters.formatCurrency(v, "USD")
            return "XTR " + ChartFormatters.formatNumber(v)
        }
        if (valueFormatter != null) {
            return valueFormatter.formatAxisValue(v, paint)
        }
        return ChartFormatters.compactWholeNumber(v)
    }

    fun drawText(canvas: Canvas, a: Int, i: Int, x: Float, y: Float, paint: TextPaint) {
        val layout = getLayout(a, i, paint)
        canvas.save()
        canvas.translate(x, y + paint.ascent())
        layout.draw(canvas)
        canvas.restore()
    }

    fun getTextBounds(outRect: RectF, a: Int, i: Int, x: Float, y: Float, paint: TextPaint): Boolean {
        val layout = getLayout(a, i, paint)
        var left = Float.POSITIVE_INFINITY
        var right = Float.NEGATIVE_INFINITY
        for (lineIndex in 0 until layout.lineCount) {
            left = min(left, layout.getLineLeft(lineIndex))
            right = max(right, layout.getLineRight(lineIndex))
        }
        if (!left.isFinite() || !right.isFinite() || right <= left) {
            outRect.setEmpty()
            return false
        }
        val top = y + paint.ascent()
        outRect.set(x + left, top, x + right, top + layout.height)
        return true
    }

    private fun getLayout(a: Int, i: Int, paint: TextPaint): StaticLayout {
        val layoutArray = if (a == 0) layouts else layouts2!!
        var layout = layoutArray[i]
        if (layout == null) {
            val string = if (a == 0) valuesStr[i] else valuesStr2!![i]
            layout = StaticLayout(
                string ?: "",
                paint,
                ChartFormatters.screenWidthPx,
                Layout.Alignment.ALIGN_NORMAL,
                1f,
                0f,
                false
            )
            layoutArray[i] = layout
        }
        return layout
    }

    companion object {
        fun lookupHeight(maxValue: Long): Long {
            return computeAxisTickValues(maxValue, 0L, false).max
        }

        internal data class AxisTickValues(
            val min: Long,
            val max: Long,
            val step: Long,
            val count: Int,
        )

        internal fun computeAxisTickValues(
            maxValue: Long,
            minValue: Long,
            useMinHeight: Boolean,
        ): AxisTickValues {
            return if (useMinHeight) {
                computeRangedAxisTickValues(maxValue, minValue)
            } else {
                computeZeroBasedAxisTickValues(maxValue)
            }
        }

        private fun computeZeroBasedAxisTickValues(maxValue: Long): AxisTickValues {
            val adjustedMax = max(0L, maxValue)
            return when {
                adjustedMax < 6L -> {
                    val count = max(2L, adjustedMax + 1).toInt()
                    AxisTickValues(0L, (count - 1).toLong(), 1L, count)
                }

                adjustedMax / 2L < 6L -> {
                    val count = (adjustedMax / 2L + 1 + if (adjustedMax % 2L != 0L) 1 else 0).toInt()
                    AxisTickValues(0L, (count - 1) * 2L, 2L, count)
                }

                else -> {
                    val step = computeNiceStep(adjustedMax / 5.0)
                    val maxTick = ceilToStep(adjustedMax, step)
                    AxisTickValues(0L, maxTick, step, (maxTick / step + 1).toInt())
                }
            }
        }

        private fun computeRangedAxisTickValues(
            maxValue: Long,
            minValue: Long,
        ): AxisTickValues {
            var adjustedMinValue = minValue
            val diff = maxValue - adjustedMinValue
            return when {
                diff == 0L -> {
                    adjustedMinValue--
                    AxisTickValues(adjustedMinValue, adjustedMinValue + 2L, 1L, 3)
                }

                diff < 6L -> {
                    val count = max(2L, diff + 1).toInt()
                    AxisTickValues(adjustedMinValue, adjustedMinValue + count - 1L, 1L, count)
                }

                diff / 2L < 6L -> {
                    val count = (diff / 2L + diff % 2L + 1).toInt()
                    AxisTickValues(adjustedMinValue, adjustedMinValue + (count - 1) * 2L, 2L, count)
                }

                else -> {
                    val step = computeNiceStep(diff / 5.0)
                    val minTick = floorToStep(adjustedMinValue, step)
                    val maxTick = ceilToStep(maxValue, step)
                    AxisTickValues(
                        minTick,
                        maxTick,
                        step,
                        ((maxTick - minTick) / step + 1).toInt()
                    )
                }
            }
        }

        private fun computeNiceStep(rawStep: Double): Long {
            if (!rawStep.isFinite() || rawStep <= 1.0) {
                return 1L
            }

            val interval = roundToNextSignificant(rawStep)
            if (!interval.isFinite() || interval <= 1.0) {
                return 1L
            }

            val intervalMagnitude = 10.0.pow(floor(log10(interval)))
            val intervalSigDigit = (interval / intervalMagnitude).toInt()
            val adjustedInterval = if (intervalSigDigit > 5) {
                floor(10.0 * intervalMagnitude)
            } else {
                interval
            }

            return max(1L, ceil(adjustedInterval).toLong())
        }

        private fun roundToNextSignificant(value: Double): Double {
            if (!value.isFinite() || value == 0.0) {
                return 0.0
            }

            val absValue = kotlin.math.abs(value)
            val d = ceil(log10(absValue)).toInt()
            val pw = 1 - d
            val magnitude = 10.0.pow(pw.toDouble())
            val shifted = (value * magnitude).roundToLong()
            return shifted / magnitude
        }

        private fun ceilToStep(value: Long, step: Long): Long {
            if (step <= 0L) return value
            val remainder = value % step
            return if (remainder == 0L) value else value + step - remainder
        }

        private fun floorToStep(value: Long, step: Long): Long {
            if (step <= 0L) return value
            val remainder = value % step
            if (remainder == 0L) return value
            return if (value >= 0L) value - remainder else value - remainder - step
        }
    }
}
