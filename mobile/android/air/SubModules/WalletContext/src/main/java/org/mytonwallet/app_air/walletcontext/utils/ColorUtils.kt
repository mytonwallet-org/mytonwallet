package org.mytonwallet.app_air.walletcontext.utils

import android.graphics.Color
import androidx.annotation.ColorInt
import androidx.annotation.FloatRange
import androidx.core.graphics.alpha
import androidx.core.graphics.blue
import androidx.core.graphics.green
import androidx.core.graphics.red
import kotlin.math.roundToInt

fun Int.colorWithAlpha(alpha: Int): Int {
    return Color.argb(alpha * this.alpha / 255, red, green, blue)
}

fun Int.solidColorWithAlpha(alpha: Int): Int {
    return Color.argb(alpha, red, green, blue)
}

@ColorInt
fun lerpColor(@ColorInt start: Int, @ColorInt end: Int, @FloatRange(0.0, 1.0) t: Float): Int {
    val clamped = t.coerceIn(0f, 1f)

    val a1 = start.alpha
    val r1 = start.red
    val g1 = start.green
    val b1 = start.blue

    val a2 = end.alpha
    val r2 = end.red
    val g2 = end.green
    val b2 = end.blue

    val a = (a1 + (a2 - a1) * clamped).roundToInt()
    val r = (r1 + (r2 - r1) * clamped).roundToInt()
    val g = (g1 + (g2 - g1) * clamped).roundToInt()
    val b = (b1 + (b2 - b1) * clamped).roundToInt()

    return Color.argb(a, r, g, b)
}
