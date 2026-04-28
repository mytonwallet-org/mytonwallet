package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

class DoubleLinearChartData(model: ChartModel) : ChartData(model) {
    var linesK: FloatArray = floatArrayOf()

    override fun measure() {
        super.measure()
        var max = 0L
        for (line in lines) {
            if (line.maxValue > max) {
                max = line.maxValue
            }
        }
        linesK = FloatArray(lines.size)
        for (index in lines.indices) {
            val value = lines[index].maxValue
            linesK[index] = if (max == value || value == 0L) 1f else max.toFloat() / value
        }
    }
}
