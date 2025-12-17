package org.mytonwallet.app_air.walletbasecontext.theme

object NftAccentColors {
    val light = listOf(
        "#31AFC7", "#35C759", "#FF9500", "#FF2C55",
        "#AF52DE", "#5856D7", "#73AAED", "#FFB07A",
        "#B76C78", "#9689D1", "#E572CC", "#6BA07A",
        "#338FCC", "#1FC863", "#929395", "#E4B102",
        "#000000"
    )

    val dark = listOf(
        "#3AB5CC", "#32D74B", "#FF9F0B", "#FF325A",
        "#BF5AF2", "#7977FF", "#73AAED", "#FFB07A",
        "#B76C78", "#9689D1", "#E572CC", "#6BA07A",
        "#338FCC", "#2CD36F", "#C3C5C6", "#DDBA00",
        "#FFFFFF"
    )

    const val ACCENT_RADIOACTIVE_INDEX = 13;
    const val ACCENT_SILVER_INDEX = 14;
    const val ACCENT_GOLD_INDEX = 15;
    const val ACCENT_BNW_INDEX = 16;

    val veryBrightColors = setOf(
        0xFFC3C5C6.toInt(), // Silver color in Dark theme = Light Gray
        0xFFFFFFFF.toInt()  // BNW color in Dark theme = White
    )
}
