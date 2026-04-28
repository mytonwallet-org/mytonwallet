package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.graphics.Color
import java.util.ArrayList

open class ChartData() {
    var x: LongArray = longArrayOf()

    var xPercentage: FloatArray = floatArrayOf()

    var daysLookup: Array<String> = emptyArray()

    var lines: ArrayList<Line> = ArrayList()

    var maxValue: Long = 0L

    var minValue: Long = Long.MAX_VALUE

    var oneDayPercentage: Float = 0f

    var xTickFormatter: Int = 0

    var xTooltipFormatter: Int = 0

    var yRate: Float = 0f

    var yTickFormatter: Int = 0

    var yTooltipFormatter: Int = 0

    protected var timeStep: Long = 0L

    constructor(model: ChartModel) : this() {
        x = model.x.copyOf()
        lines = ArrayList(model.lines.size)
        model.lines.forEach { modelLine ->
            val line = Line(
                y = modelLine.y.copyOf(),
                id = modelLine.id,
                name = modelLine.name,
                color = modelLine.color,
                colorDark = modelLine.colorDark,
            )
            line.maxValue = line.y.maxOrNull() ?: 0L
            line.minValue = line.y.minOrNull() ?: Long.MAX_VALUE
            lines.add(line)
        }
        xTickFormatter = getFormatter(model.xTickFormatter)
        yTickFormatter = getFormatter(model.yTickFormatter)
        xTooltipFormatter = getFormatter(model.xTooltipFormatter)
        yTooltipFormatter = getFormatter(model.yTooltipFormatter)
        timeStep = if (x.size > 1) x[1] - x[0] else 86_400_000L
        measure()
    }

    open fun getFormatter(value: String?): Int {
        if (value.isNullOrEmpty()) return 0
        if (value.contains("TON")) return FORMATTER_TON
        if (value.contains("XTR")) return FORMATTER_XTR
        return 0
    }

    protected open fun measure() {
        val count = x.size
        if (count == 0) return
        maxValue = 0L
        minValue = Long.MAX_VALUE

        val start = x[0]
        val end = x[count - 1]
        xPercentage = FloatArray(count)
        if (count == 1) {
            xPercentage[0] = 1f
        } else {
            for (index in 0 until count) {
                xPercentage[index] = (x[index] - start).toFloat() / (end - start).toFloat()
            }
        }

        for (line in lines) {
            if (line.maxValue > maxValue) maxValue = line.maxValue
            if (line.minValue < minValue) minValue = line.minValue
            line.segmentTree = SegmentTree(line.y)
        }

        daysLookup = Array(((end - start) / timeStep).toInt() + 10) { "" }
        for (index in daysLookup.indices) {
            daysLookup[index] = if (timeStep == 1L) {
                String.format(java.util.Locale.ENGLISH, "%02d:00", index)
            } else {
                ChartFormatters.formatDate(
                    if (timeStep < 86_400_000L) "HH:mm" else "MMM d",
                    start + index * timeStep
                )
            }
        }
        oneDayPercentage = if (x.last() == x.first()) 0f else timeStep / (x.last() - x.first()).toFloat()
    }

    fun getDayString(index: Int): String {
        return daysLookup[((x[index] - x[0]) / timeStep).toInt()]
    }

    fun findStartIndex(v: Float): Int {
        if (v == 0f) return 0
        if (xPercentage.size < 2) return 0
        var left = 0
        var right = xPercentage.lastIndex
        while (left <= right) {
            val middle = (right + left) shr 1
            if (v < xPercentage[middle] && (middle == 0 || v > xPercentage[middle - 1])) return middle
            if (v == xPercentage[middle]) return middle
            if (v < xPercentage[middle]) right = middle - 1 else left = middle + 1
        }
        return left
    }

    fun findEndIndex(leftStart: Int, v: Float): Int {
        if (v == 1f) return xPercentage.lastIndex
        var left = leftStart
        var right = xPercentage.lastIndex
        while (left <= right) {
            val middle = (right + left) shr 1
            if (v > xPercentage[middle] && (middle == xPercentage.lastIndex || v < xPercentage[middle + 1])) return middle
            if (v == xPercentage[middle]) return middle
            if (v < xPercentage[middle]) right = middle - 1 else left = middle + 1
        }
        return right
    }

    fun findIndex(leftStart: Int, rightStart: Int, v: Float): Int {
        if (v <= xPercentage[leftStart]) return leftStart
        if (v >= xPercentage[rightStart]) return rightStart
        var left = leftStart
        var right = rightStart
        while (left <= right) {
            val middle = (right + left) shr 1
            if (v > xPercentage[middle] && (middle == xPercentage.lastIndex || v < xPercentage[middle + 1])) return middle
            if (v == xPercentage[middle]) return middle
            if (v < xPercentage[middle]) right = middle - 1 else left = middle + 1
        }
        return right
    }

    class Line(
        var y: LongArray = longArrayOf(),
        var segmentTree: SegmentTree? = null,
        var id: String = "",
        var name: String = "",
        var maxValue: Long = 0L,
        var minValue: Long = Long.MAX_VALUE,
        var color: Int = Color.BLACK,
        var colorDark: Int = Color.WHITE,
    )

    companion object {
        const val FORMATTER_TON = 1
        const val FORMATTER_XTR = 2
    }
}
