package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

data class ChartBottomSignatureData(
    val step: Int,
    val stepMax: Int,
    val stepMin: Int,
    var alpha: Int = 0,
    var fixedAlpha: Int = 255,
)
