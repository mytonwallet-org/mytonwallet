package org.mytonwallet.app_air.uiswap.screens.tokenTrade

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp

internal object TokenTradeSlippageScale {
    const val TINT_COLOR = 0xFF0088FF.toInt()
    const val MIN_VALUE = 0.1f
    const val MAX_VALUE = 50f

    val PRESETS = listOf(0.2f, 0.5f, 1f, 2f, 5f, 10f)
    private val STOPS = listOf(MIN_VALUE) + PRESETS + MAX_VALUE

    // Presets are evenly spaced; the short end segments keep Min/Max separate from their dots.
    val POSITIONS = listOf(0f) +
        PRESETS.indices.map { 0.06f + it * 0.88f / (PRESETS.size - 1) } + 1f

    data class Selection(val value: Float, val presetIndex: Int?)

    fun formatSlippage(value: Float): String =
        if (value % 1f == 0f) value.toInt().toString() else value.toString()

    fun positionFor(value: Float): Float =
        interpolate(value.coerceIn(MIN_VALUE, MAX_VALUE), STOPS, POSITIONS)

    private fun valueAt(position: Float): Float =
        interpolate(position.coerceIn(0f, 1f), POSITIONS, STOPS)

    fun selection(position: Float, trackWidth: Float, capturedPreset: Int?): Selection {
        val position = position.coerceIn(0f, 1f)
        val width = max(1f, trackWidth)
        val nearest = PRESETS.indices.minBy { abs(POSITIONS[it + 1] - position) }
        val index = capturedPreset ?: nearest
        val anchor = POSITIONS[index + 1]
        // Hysteresis prevents repeated capture/release feedback at a preset's boundary.
        val radius = min(
            (if (capturedPreset == null) 6f else 10f).dp,
            min(anchor, 1 - anchor) * width * 0.45f
        )
        if (abs(anchor - position) * width <= radius) {
            return Selection(PRESETS[index], index)
        }
        if (capturedPreset != null) {
            return selection(position, width, null)
        }
        val value = valueAt(position)
        return Selection(
            if (value > 5f) value.roundToInt().toFloat() else (value * 10).roundToInt() / 10f,
            null
        )
    }

    private fun interpolate(value: Float, from: List<Float>, to: List<Float>): Float {
        val upper = (1 until from.size).firstOrNull { value <= from[it] } ?: (from.size - 1)
        val lower = upper - 1
        val progress = (value - from[lower]) / (from[upper] - from[lower])
        return to[lower] + progress * (to[upper] - to[lower])
    }
}
