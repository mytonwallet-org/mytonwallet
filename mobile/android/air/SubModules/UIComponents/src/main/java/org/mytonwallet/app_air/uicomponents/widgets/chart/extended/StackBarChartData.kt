package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

class StackBarChartData(model: ChartModel) : ChartData(model) {
    var ySum: LongArray = longArrayOf()

    var ySumSegmentTree: SegmentTree? = null

    init {
        init()
    }

    fun init() {
        val n = lines[0].y.size
        ySum = LongArray(n)
        for (i in 0 until n) {
            for (line in lines) {
                ySum[i] += line.y[i]
            }
        }
        ySumSegmentTree = SegmentTree(ySum)
    }

    fun findMax(start: Int, end: Int): Long = ySumSegmentTree?.rMaxQ(start, end) ?: 0L
}
