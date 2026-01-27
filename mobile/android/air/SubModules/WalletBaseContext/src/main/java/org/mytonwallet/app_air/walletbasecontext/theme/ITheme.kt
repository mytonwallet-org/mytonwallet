package org.mytonwallet.app_air.walletbasecontext.theme

interface ITheme {
    fun getColor(color: WColor): Int
    fun getColor(color: WColor, isDark: Boolean): Int
}

private fun create(colormap: Map<WColor, Int>): IntArray {
    return IntArray(WColor.entries.size).apply {
        colormap.forEach {
            set(it.key.ordinal, it.value)
        }
    }
}

const val DEFAULT_TINT_LIGHT = 0xFF0098EB.toInt()
const val DEFAULT_TINT_DARK = 0xFF3C90D5.toInt()

internal val THEME_LIGHT_PRESET
    get() = create(
        mapOf(
            WColor.Background to 0xFFFFFFFF.toInt(),
            WColor.PrimaryText to 0xFF1C1D21.toInt(),
            WColor.PrimaryDarkText to 0xFF4D5053.toInt(),
            WColor.PrimaryLightText to 0xFF747C87.toInt(),
            WColor.SecondaryText to 0xFF747C87.toInt(),
            WColor.SubtitleText to 0xFF8A8A8A.toInt(),
            WColor.Decimals to 0xFF99999E.toInt(),
            WColor.Tint to DEFAULT_TINT_LIGHT,
            WColor.TextOnTint to 0xFFFFFFFF.toInt(),
            WColor.Separator to 0xFFEFF0F0.toInt(),
            WColor.SecondaryBackground to 0xFFF4F4F5.toInt(),
            WColor.TrinaryBackground to 0xFFF4F4F5.toInt(),
            WColor.GroupedBackground to 0xFFEFEFF4.toInt(),
            WColor.BadgeBackground to 0xFFF5F5F7.toInt(),
            WColor.AttributesBackground to 0xFFF7F7F7.toInt(),
            WColor.PopupSeparator to 0x1F747C87,
            WColor.PopupWindow to 0x4C000000,
            WColor.PopupAmbientShadow to 0xCC000000.toInt(),
            WColor.PopupSpotShadow to 0x66000000,
            WColor.Thumb to 0xFFC5C5CC.toInt(),
            WColor.DIVIDER to 0xFF8E8E93.toInt(),
            WColor.Error to 0xFFFF3B30.toInt(),
            WColor.Green to 0xFF53A30D.toInt(),
            WColor.Red to 0xFFFF3B30.toInt(),
            WColor.Purple to 0xFF5E6BDE.toInt(),
            WColor.Orange to 0xFFF7931A.toInt(),
            WColor.EarnGradientLeft to 0xFF41C433.toInt(),
            WColor.EarnGradientRight to 0xFF0098EB.toInt(),
            WColor.TintRipple to 0x201F8EFE,
            WColor.BackgroundRipple to 0x10000000,
            WColor.IncomingComment to 0xFF68D06E.toInt(),
            WColor.OutgoingComment to 0xFF31A4F2.toInt(),
            WColor.SearchFieldBackground to 0xFFFFFFFF.toInt(),
            WColor.Transparent to 0x00000000.toInt(),
            WColor.White to 0xFFFFFFFF.toInt(),
            WColor.Black to 0xFF000000.toInt(),
            WColor.Icon to 0xFF363A3E.toInt(),
        )
    )

internal val THEME_DARK_PRESET
    get() = create(
        mapOf(
            WColor.Background to 0xFF181818.toInt(),
            WColor.PrimaryText to 0xFFFFFFFF.toInt(),
            WColor.PrimaryDarkText to 0xFF717579.toInt(),
            WColor.PrimaryLightText to 0xFF8E8E93.toInt(),
            WColor.SecondaryText to 0xFF8E8E93.toInt(),
            WColor.SubtitleText to 0xFF8E8E93.toInt(),
            WColor.Decimals to 0xFF8E8E93.toInt(),
            WColor.Tint to DEFAULT_TINT_DARK,
            WColor.TextOnTint to 0xFFFFFFFF.toInt(),
            WColor.Separator to 0xFF313133.toInt(),
            WColor.SecondaryBackground to 0xFF0E0E0E.toInt(),
            WColor.TrinaryBackground to 0xFF282828.toInt(),
            WColor.GroupedBackground to 0xFF000000.toInt(),
            WColor.BadgeBackground to 0xFF282828.toInt(),
            WColor.AttributesBackground to 0xFF2C2C2E.toInt(),
            WColor.PopupSeparator to 0x1FB6B6BB,
            WColor.PopupWindow to 0x4C000000,
            WColor.PopupAmbientShadow to 0xCC000000.toInt(),
            WColor.PopupSpotShadow to 0x66000000,
            WColor.Thumb to 0xFF04D4D50.toInt(),
            WColor.DIVIDER to 0xFF8E8E93.toInt(),
            WColor.Error to 0xFFFF3B30.toInt(),
            WColor.Green to 0xFF57C84A.toInt(),
            WColor.Red to 0xFFFF5148.toInt(),
            WColor.Purple to 0xFF7D88F4.toInt(),
            WColor.Orange to 0xFFF7931A.toInt(),
            WColor.EarnGradientLeft to 0xFF41C433.toInt(),
            WColor.EarnGradientRight to 0xFF0098EB.toInt(),
            WColor.TintRipple to 0x20007AFF,
            WColor.BackgroundRipple to 0x10FFFFFF,
            WColor.IncomingComment to 0xFF55A35A.toInt(),
            WColor.OutgoingComment to 0xFF2C82BD.toInt(),
            WColor.SearchFieldBackground to 0xFF38383B.toInt(),
            WColor.Transparent to 0x00000000.toInt(),
            WColor.White to 0xFFFFFFFF.toInt(),
            WColor.Black to 0xFF000000.toInt(),
            WColor.Icon to 0xFFFFFFFF.toInt(),
        )
    )
