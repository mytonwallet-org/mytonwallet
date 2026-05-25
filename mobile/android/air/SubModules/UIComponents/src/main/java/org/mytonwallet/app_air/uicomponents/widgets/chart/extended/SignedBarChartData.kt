package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

class SignedBarChartData(model: ChartModel) : ChartData(model) {
    var posSum: LongArray = longArrayOf()
    var negSum: LongArray = longArrayOf()
    var posSumSegmentTree: SegmentTree? = null
    var negSumSegmentTree: SegmentTree? = null

    init {
        recomputeSums(lines.map { true })
    }

    fun recomputeSums(enabled: List<Boolean>) {
        val n = if (lines.isEmpty()) 0 else lines[0].y.size
        posSum = LongArray(n)
        negSum = LongArray(n)
        for (i in 0 until n) {
            var pos = 0L
            var neg = 0L
            lines.forEachIndexed { index, line ->
                if (enabled.getOrElse(index) { true }) {
                    val v = line.y[i]
                    if (v >= 0) pos += v else neg += v
                }
            }
            posSum[i] = pos
            negSum[i] = neg
        }
        posSumSegmentTree = SegmentTree(posSum)
        negSumSegmentTree = SegmentTree(negSum)
    }

    fun findPositiveMax(start: Int, end: Int): Long = posSumSegmentTree?.rMaxQ(start, end) ?: 0L
    fun findNegativeMin(start: Int, end: Int): Long = negSumSegmentTree?.rMinQ(start, end) ?: 0L
}
