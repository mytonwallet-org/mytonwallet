package org.mytonwallet.app_air.walletbasecontext.utils

import android.graphics.Color
import androidx.core.graphics.ColorUtils
import java.lang.Math.clamp
import kotlin.math.pow

fun Int.isLightColor(): Boolean {
    fun toLinear(value: Double): Double =
        if (value > 0.04045) ((value + 0.055) / 1.055).pow(2.4) else value / 12.92

    val luminance = 0.2126 * toLinear(Color.red(this) / 255.0) +
        0.7152 * toLinear(Color.green(this) / 255.0) +
        0.0722 * toLinear(Color.blue(this) / 255.0)

    return luminance > 0.3
}

fun Int.isBrightColor(): Boolean {
    val r = Color.red(this)
    val g = Color.green(this)
    val b = Color.blue(this)

    val luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255

    return luminance > 0.7
}

fun Int.colorChanged(amount: Float, darker: Boolean): Int = if (darker) {
    colorDarkened(amount * 2)
} else {
    colorLightened(amount)
}

fun Int.colorLightened(amount: Float): Int =
    colorAdjusted(brightnessDelta = amount, saturationDelta = -amount * 0.35f)

fun Int.colorDarkened(amount: Float): Int =
    colorAdjusted(brightnessDelta = -amount, saturationDelta = amount * 0.25f)

fun Int.colorAdjusted(brightnessDelta: Float, saturationDelta: Float): Int {
    val hsl = FloatArray(3)
    ColorUtils.colorToHSL(this, hsl)

    hsl[1] = clamp(hsl[1] + saturationDelta, 0f, 1f) // saturation
    hsl[2] = clamp(hsl[2] + brightnessDelta, 0f, 1f) // lightness/brightness

    return ColorUtils.HSLToColor(hsl)
}

fun Int.colorAdjusted(
    hueDelta: Float = 0f,
    saturationDelta: Float = 0f,
    brightnessDelta: Float = 0f
): Int {
    val hsl = FloatArray(3)
    ColorUtils.colorToHSL(this, hsl)

    hsl[0] = (hsl[0] + hueDelta + 360f) % 360f
    hsl[1] = clamp(hsl[1] + saturationDelta, 0f, 1f)
    hsl[2] = clamp(hsl[2] + brightnessDelta, 0f, 1f)

    return ColorUtils.HSLToColor(hsl)
}
