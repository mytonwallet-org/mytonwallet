package org.mytonwallet.app_air.walletbasecontext.theme

import android.graphics.Color
import androidx.core.graphics.toColorInt

const val BlackWhiteAccentId = 14

val lightAccentColors = arrayListOf(
    WColor.Accent(
        id = 1,
        accent = "#0098EB".toColorInt(),
        textOnAccent = Color.WHITE,
    ),
    WColor.Accent(
        id = 2,
        accent = Color.rgb(48, 176, 198),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 3,
        accent = Color.rgb(51, 199, 90),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 4,
        accent = Color.rgb(255, 148, 0),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 5,
        accent = Color.rgb(255, 46, 84),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 6,
        accent = Color.rgb(176, 82, 223),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 7,
        accent = Color.rgb(89, 87, 214),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 8,
        accent = Color.rgb(255, 176, 122),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 9,
        accent = Color.rgb(183, 110, 120),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 10,
        accent = Color.rgb(150, 138, 210),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 11,
        accent = Color.rgb(230, 114, 204),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 12,
        accent = Color.rgb(108, 162, 122),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 13,
        accent = Color.rgb(51, 143, 204),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = BlackWhiteAccentId,
        accent = WColor.PrimaryText.color,
        textOnAccent = WColor.Background.color
    )
)

val darkAccentColors = arrayListOf(
    WColor.Accent(
        id = 1,
        accent = "#3C90D5".toColorInt(),
        textOnAccent = Color.WHITE,
    ),
    WColor.Accent(
        id = 2,
        accent = Color.rgb(57, 182, 204),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 3,
        accent = Color.rgb(50, 215, 75),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 4,
        accent = Color.rgb(255, 159, 10),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 5,
        accent = Color.rgb(255, 51, 90),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 6,
        accent = Color.rgb(191, 90, 242),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 7,
        accent = Color.rgb(94, 92, 230),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 8,
        accent = Color.rgb(255, 176, 122),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 9,
        accent = Color.rgb(183, 110, 120),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 10,
        accent = Color.rgb(150, 138, 210),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 11,
        accent = Color.rgb(230, 114, 204),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 12,
        accent = Color.rgb(108, 162, 122),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = 13,
        accent = Color.rgb(51, 143, 204),
        textOnAccent = Color.WHITE
    ),
    WColor.Accent(
        id = BlackWhiteAccentId,
        accent = WColor.PrimaryText.color,
        textOnAccent = WColor.Background.color
    )
)

var WAccentColors = lightAccentColors

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
}
