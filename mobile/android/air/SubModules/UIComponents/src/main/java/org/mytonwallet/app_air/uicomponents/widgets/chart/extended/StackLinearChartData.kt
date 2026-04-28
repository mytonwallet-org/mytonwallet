package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import java.util.ArrayList
import java.util.Arrays
import kotlin.math.max
import kotlin.math.roundToInt

class StackLinearChartData : ChartData {
    var ySum: LongArray = longArrayOf()

    var ySumSegmentTree: SegmentTree? = null

    var simplifiedY: Array<LongArray> = emptyArray()

    var simplifiedSize: Int = 0

    constructor(model: ChartModel, isLanguages: Boolean) : super(model) {
        if (isLanguages) {
            val totalCount = LongArray(lines.size)
            val emptyCount = IntArray(lines.size)
            var total = 0L
            for (k in lines.indices) {
                val n = x.size
                for (i in 0 until n) {
                    val value = lines[k].y[i]
                    totalCount[k] += value
                    if (value == 0L) emptyCount[k]++
                }
                total += totalCount[k]
            }

            val removed = ArrayList<Line>()
            for (k in lines.indices) {
                if (total != 0L && totalCount[k] / total.toDouble() < 0.01 && emptyCount[k] > x.size / 2f) {
                    removed.add(lines[k])
                }
            }
            lines.removeAll(removed)
        }
        val n = lines[0].y.size
        ySum = LongArray(n)
        for (i in 0 until n) {
            for (line in lines) {
                ySum[i] += line.y[i]
            }
        }
        ySumSegmentTree = SegmentTree(ySum)
        measure()
    }

    constructor(data: ChartData, d: Long) : super() {
        val index = Arrays.binarySearch(data.x, d)
        var startIndex = index - 4
        var endIndex = index + 4
        if (startIndex < 0) {
            endIndex += -startIndex
            startIndex = 0
        }
        if (endIndex > data.x.size - 1) {
            startIndex -= endIndex - data.x.size
            endIndex = data.x.size - 1
        }
        if (startIndex < 0) startIndex = 0

        val n = endIndex - startIndex + 1
        x = LongArray(n)
        xPercentage = FloatArray(n)
        lines = ArrayList()
        for (source in data.lines) {
            lines.add(
                Line(
                    y = LongArray(n),
                    id = source.id,
                    name = source.name,
                    color = source.color,
                    colorDark = source.colorDark,
                )
            )
        }
        var output = 0
        for (sourceIndex in startIndex..endIndex) {
            x[output] = data.x[sourceIndex]
            for (lineIndex in lines.indices) {
                lines[lineIndex].y[output] = data.lines[lineIndex].y[sourceIndex]
            }
            output++
        }
        timeStep = 86_400_000L
        measure()
    }

    override fun measure() {
        super.measure()
        simplifiedSize = 0
        val n = xPercentage.size
        val nl = lines.size
        val step = max(1, (n / 140f).roundToInt())
        val maxSize = max(1, n / step)
        simplifiedY = Array(nl) { LongArray(maxSize) }
        val maxima = LongArray(nl)
        for (i in 0 until n) {
            for (k in 0 until nl) {
                val value = lines[k].y[i]
                if (value > maxima[k]) maxima[k] = value
            }
            if (i % step == 0) {
                for (k in 0 until nl) {
                    simplifiedY[k][simplifiedSize] = maxima[k]
                    maxima[k] = 0
                }
                simplifiedSize++
                if (simplifiedSize >= maxSize) break
            }
        }
    }
}
