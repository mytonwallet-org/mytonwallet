package org.mytonwallet.app_air.walletcontext.theme

import android.content.res.ColorStateList
import android.graphics.Color
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.graphics.toColorInt
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

enum class WColor {
    Background,
    BackgroundRipple,
    PrimaryText,
    PrimaryDarkText,
    PrimaryLightText,
    SecondaryText,
    SubtitleText,
    Decimals,
    Tint,
    TintRipple,
    TextOnTint,
    Separator,
    SecondaryBackground,
    TrinaryBackground,
    GroupedBackground,
    BadgeBackground,
    Thumb,
    DIVIDER,
    Error,
    Green,
    Red,
    Purple,
    Orange,
    EarnGradientLeft,
    EarnGradientRight,
    IncomingComment,
    OutgoingComment,
    SearchFieldBackground,
    Transparent,
    White,
    Black;

    data class Accent(
        val id: Int,
        val accent: Int,
        val textOnAccent: Int,
    )

    companion object {
        @Deprecated("use WColor.BackgroundRipple")
        val backgroundRippleColor: Int
            get() = PrimaryText.color and 0x10FFFFFF

        @Deprecated("use WColor.TintRipple")
        val tintRippleColor: Int
            get() = Tint.color and 0x20FFFFFF
    }
}

val WColor.color: Int get() = ThemeManager.getColor(this)
val WColor.colorStateList: ColorStateList
    get() {
        return ColorStateList.valueOf(this.color)
    }

val WColorGradients = listOf(
    intArrayOf("#FF885E".toColorInt(), "#FF5150".toColorInt()),
    intArrayOf("#FFD06A".toColorInt(), "#FFA85C".toColorInt()),
    intArrayOf("#A0DE7E".toColorInt(), "#54CB68".toColorInt()),
    intArrayOf("#53EED6".toColorInt(), "#28C9B7".toColorInt()),
    intArrayOf("#72D5FE".toColorInt(), "#2A9EF1".toColorInt()),
    intArrayOf("#82B1FF".toColorInt(), "#665FFF".toColorInt()),
    intArrayOf("#E0A2F3".toColorInt(), "#D569ED".toColorInt())
)

object ThemeManager : ITheme {
    const val THEME_SYSTEM = "system"
    const val THEME_LIGHT = "light"
    const val THEME_DARK = "dark"

    private var colors = THEME_LIGHT_PRESET
    private var activeTheme: String = THEME_LIGHT // will be dark or light, not system

    val isDark: Boolean
        get() {
            return activeTheme == THEME_DARK
        }

    enum class UIMode(val value: String) {
        COMMON("common"),
        BIG_RADIUS("bigRadius"),
        COMPOUND("compound");

        val hasRoundedCorners: Boolean
            get() {
                return this != COMMON
            }

        companion object {
            fun fromValue(value: String): UIMode? {
                return UIMode.entries.find { it.value == value }
            }
        }
    }

    var uiMode = UIMode.COMMON
        set(value) {
            field = value
            when (value) {
                UIMode.BIG_RADIUS -> {
                    ViewConstants.STANDARD_ROUNDS = 24f
                    ViewConstants.BAR_ROUNDS = 24f
                    ViewConstants.BIG_RADIUS = 24f
                    ViewConstants.TOP_RADIUS = 24f
                    ViewConstants.GAP = 16
                }

                UIMode.COMPOUND -> {
                    ViewConstants.STANDARD_ROUNDS = 24f
                    ViewConstants.BAR_ROUNDS = 0f
                    ViewConstants.BIG_RADIUS = 24f
                    ViewConstants.TOP_RADIUS = 0f
                    ViewConstants.GAP = 16
                }

                UIMode.COMMON -> {
                    ViewConstants.STANDARD_ROUNDS = 25f
                    ViewConstants.BAR_ROUNDS = 25f
                    ViewConstants.BIG_RADIUS = 0f
                    ViewConstants.TOP_RADIUS = 0f
                    ViewConstants.GAP = 12
                }
            }
        }

    fun init(theme: String, accountId: String?) {
        activeTheme = theme
        if (theme == THEME_DARK) {
            AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_YES)
            colors = THEME_DARK_PRESET
            WAccentColors = darkAccentColors
        } else if (theme == THEME_LIGHT) {
            AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_NO)
            colors = THEME_LIGHT_PRESET
            WAccentColors = lightAccentColors
        }

        WAccentColors[WAccentColors.size - 1] = WColor.Accent(
            BlackWhiteAccentId,
            WColor.PrimaryText.color,
            WColor.Background.color
        )

        updateAccentColor(accountId = accountId)
        colors[WColor.BackgroundRipple.ordinal] = getColor(WColor.PrimaryText) and 0x10FFFFFF
        colors[WColor.TintRipple.ordinal] = getColor(WColor.Tint) and 0x18FFFFFF

        uiMode = WGlobalStorage.getActiveUiMode()
        ViewConstants.HORIZONTAL_PADDINGS = if (WGlobalStorage.getAreSideGuttersActive()) 10 else 0
    }

    fun updateAccentColor(accountId: String?) {
        accountId?.let {
            WGlobalStorage.getNftAccentColorIndex(accountId)?.let {
                setNftAccentColor(it)
                return
            }
        }
        setAccentColor(WGlobalStorage.getAccentColorId())
    }

    private fun setNftAccentColor(nftAccentId: Int) {
        val accentColor = (if (isDark) NftAccentColors.dark else NftAccentColors.light)[nftAccentId]
        colors[WColor.Tint.ordinal] = accentColor.toColorInt()
        colors[WColor.TextOnTint.ordinal] =
            if (nftAccentId != 16 || !isDark) Color.WHITE else Color.BLACK
    }

    private fun setAccentColor(accentColorId: Int) {
        val accentColor = WAccentColors.find { it.id == accentColorId } ?: WAccentColors.first()
        colors[WColor.Tint.ordinal] = accentColor.accent
        colors[WColor.TextOnTint.ordinal] = accentColor.textOnAccent
    }

    override fun getColor(color: WColor): Int = this.colors[color.ordinal]
}
