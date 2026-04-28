package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

data class TransitionParams(
    var pickerStartOut: Float = 0f,
    var pickerEndOut: Float = 0f,
    var xPercentage: Float = 0f,
    var date: Long = 0L,
    var pX: Float = 0f,
    var pY: Float = 0f,
    var needScaleY: Boolean = true,
    var progress: Float = 0f,
    var startX: FloatArray = floatArrayOf(),
    var startY: FloatArray = floatArrayOf(),
    var endX: FloatArray = floatArrayOf(),
    var endY: FloatArray = floatArrayOf(),
    var angle: FloatArray = floatArrayOf(),
)
