package org.mytonwallet.app_air.uiassets.viewControllers.nft

import android.graphics.Color
import androidx.core.graphics.ColorUtils
import org.mytonwallet.app_air.walletbasecontext.utils.isLightColor
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

data class NftPalette(val baseColor: Int) {
    val isLight = baseColor.isLightColor()
    val contentColor = if (isLight) Color.BLACK else Color.WHITE
    val secondaryContentColor = contentColor.colorWithAlpha(191)
    val subtleBackgroundColor = ColorUtils.compositeColors(
        contentColor.colorWithAlpha(if (isLight) 10 else 15),
        baseColor
    )
    val innerBackgroundColor = ColorUtils.compositeColors(
        contentColor.colorWithAlpha(if (isLight) 10 else 15),
        subtleBackgroundColor
    )
    val innerTitlesBackgroundColor = ColorUtils.compositeColors(
        contentColor.colorWithAlpha(10),
        innerBackgroundColor
    )
    val separatorColor = contentColor.colorWithAlpha(26)
    val rippleColor = contentColor.colorWithAlpha(31)
}
