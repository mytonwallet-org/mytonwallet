package org.mytonwallet.app_air.uicomponents.extensions

import android.graphics.drawable.GradientDrawable
import androidx.core.graphics.toColorInt
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

fun GradientDrawable.setRounding(rounding: Content.Rounding) {
    when (rounding) {
        is Content.Rounding.Round -> {
            this.shape = GradientDrawable.OVAL
            this.cornerRadii = FloatArray(8) { 0f }
        }

        is Content.Rounding.Radius -> {
            this.shape = GradientDrawable.RECTANGLE
            this.cornerRadii = FloatArray(8) { rounding.radius }
        }

        else -> {}
    }
}

object GradientDrawables {
    private fun gradientDrawable(colors: IntArray): GradientDrawable {
        return GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            colors
        ).apply {
            shape = GradientDrawable.OVAL
        }
    }

    val greenDrawable: GradientDrawable
        get() {
            val alpha = if (ThemeManager.isDark) 230 else 255
            return gradientDrawable(
                intArrayOf(
                    "#A0DE7E".toColorInt().colorWithAlpha(alpha),
                    "#54CB68".toColorInt().colorWithAlpha(alpha)
                )
            )
        }
    val blueDrawable: GradientDrawable
        get() {
            val alpha = if (ThemeManager.isDark) 230 else 255
            return gradientDrawable(
                intArrayOf(
                    "#72D5FD".toColorInt().colorWithAlpha(alpha),
                    "#2A9EF1".toColorInt().colorWithAlpha(alpha)
                )
            )
        }
    val purpleDrawable: GradientDrawable
        get() {
            val alpha = if (ThemeManager.isDark) 230 else 255
            return gradientDrawable(
                intArrayOf(
                    "#82B1FF".toColorInt().colorWithAlpha(alpha),
                    "#665FFF".toColorInt().colorWithAlpha(alpha)
                )
            )
        }
    val grayDrawable: GradientDrawable
        get() {
            val alpha = if (ThemeManager.isDark) 230 else 255
            return gradientDrawable(
                intArrayOf(
                    "#AEB3BF".toColorInt().colorWithAlpha(alpha),
                    "#848890".toColorInt().colorWithAlpha(alpha)
                )
            )
        }
    val redDrawable: GradientDrawable
        get() {
            val alpha = if (ThemeManager.isDark) 230 else 255
            return gradientDrawable(
                intArrayOf(
                    "#FF885E".toColorInt().colorWithAlpha(alpha),
                    "#FF516A".toColorInt().colorWithAlpha(alpha)
                )
            )
        }

}
