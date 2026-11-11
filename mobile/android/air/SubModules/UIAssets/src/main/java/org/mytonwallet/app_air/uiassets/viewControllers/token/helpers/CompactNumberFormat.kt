package org.mytonwallet.app_air.uiassets.viewControllers.token.helpers

import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.Locale
import kotlin.math.abs

fun formatCompactNumber(value: Double): String {
    if (!value.isFinite()) return "0"
    val magnitude = abs(value)
    val (scaled, suffix) = when {
        magnitude >= 1_000_000_000_000 -> value / 1_000_000_000_000 to "T"
        magnitude >= 1_000_000_000 -> value / 1_000_000_000 to "B"
        magnitude >= 1_000_000 -> value / 1_000_000 to "M"
        magnitude >= 1_000 -> value / 1_000 to "K"
        else -> value to ""
    }
    val formatter = DecimalFormat("0.##", DecimalFormatSymbols(Locale.US))
    return formatter.format(scaled) + suffix
}
