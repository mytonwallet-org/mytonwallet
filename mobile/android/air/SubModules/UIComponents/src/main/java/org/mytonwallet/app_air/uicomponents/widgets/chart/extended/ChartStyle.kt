package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.graphics.drawable.GradientDrawable
import androidx.annotation.ColorInt
import androidx.core.graphics.ColorUtils
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

data class ChartStyle(
    val isDark: Boolean,
    @ColorInt
    val backgroundColor: Int,
    @ColorInt
    val primaryTextColor: Int,
    @ColorInt
    val tooltipBackgroundColor: Int,
    @ColorInt
    val tooltipRippleColor: Int,
    @ColorInt
    val signatureColor: Int,
    @ColorInt
    val signatureAlphaColor: Int,
    @ColorInt
    val hintLineColor: Int,
    val hintLineWidth: Float,
    @ColorInt
    val activeLineColor: Int,
    @ColorInt
    val activePickerColor: Int,
    @ColorInt
    val inactivePickerColor: Int,
    @ColorInt
    val rippleColor: Int,
    @ColorInt
    val chevronColor: Int,
    @ColorInt
    val lineEmptyColor: Int,
    @ColorInt
    val checkBoxTextColor: Int,
    val useTokenChartPickerResources: Boolean = false,
    val linePalette: Map<String, LinePalette> = emptyMap(),
) {
    data class LinePalette(
        @ColorInt
        val color: Int,
        @ColorInt
        val darkColor: Int = ChartFormatters.defaultDarkLineColor(color),
    )

    @ColorInt
    fun resolveLineColor(line: ChartData.Line): Int {
        val palette = linePalette[line.id]
        return when {
            palette != null -> if (isDark) palette.darkColor else palette.color
            isDark -> line.colorDark
            else -> line.color
        }
    }

    fun createTooltipBackground(cornerRadius: Float): WRippleDrawable {
        return WRippleDrawable.create(cornerRadius).apply {
            backgroundColor = tooltipBackgroundColor
            rippleColor = tooltipRippleColor
        }
    }

    fun createPickerMaskBackground(cornerRadius: Float): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            this.cornerRadius = cornerRadius
            setColor(backgroundColor)
        }
    }

    companion object {
        fun default(isDark: Boolean = ThemeManager.isDark): ChartStyle {
            val background = WColor.Background.color
            val tooltipBackground = WColor.SearchFieldBackground.color
            val primaryText = WColor.PrimaryText.color
            val secondaryText = WColor.SecondaryText.color
            val tint = WColor.Tint.color
            val ripple = WColor.BackgroundRipple.color
            val labelColor = if (isDark) 0x99A3B1C2.toInt() else 0x99252529.toInt()
            val helperLineColor = if (isDark) 0x1AFFFFFF else 0x1A182D3B
            val inactivePickerOverlayColor = if (isDark) 0x99304259.toInt() else 0x99E2EEF9.toInt()

            return ChartStyle(
                isDark = isDark,
                backgroundColor = background,
                primaryTextColor = primaryText,
                tooltipBackgroundColor = tooltipBackground,
                tooltipRippleColor = ripple,
                signatureColor = labelColor,
                signatureAlphaColor = labelColor,
                hintLineColor = helperLineColor,
                hintLineWidth = 0.5f.dp,
                activeLineColor = primaryText.colorWithAlpha(102),
                activePickerColor = WColor.Thumb.color,
                inactivePickerColor = inactivePickerOverlayColor,
                rippleColor = tint.colorWithAlpha(if (isDark) 64 else 48),
                chevronColor = secondaryText,
                lineEmptyColor = ColorUtils.blendARGB(
                    background,
                    primaryText,
                    if (isDark) 0.1f else 0.06f
                ),
                checkBoxTextColor = WColor.White.color,
                useTokenChartPickerResources = true,
            )
        }
    }
}
