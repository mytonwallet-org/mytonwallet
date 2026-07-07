package org.mytonwallet.app_air.uisettings.viewControllers.mintCard

import android.graphics.Color
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager.isDark
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import androidx.core.graphics.toColorInt
import org.mytonwallet.app_air.walletbasecontext.theme.DEFAULT_TINT_DARK
import org.mytonwallet.app_air.walletbasecontext.theme.DEFAULT_TINT_LIGHT

enum class MintCardTypeInfo(
    val type: ApiMtwCardType,
    val slug: String,
    val displayNameKey: String,
) {
    STANDARD(ApiMtwCardType.STANDARD, "standard", "Standard Card"),
    SILVER(ApiMtwCardType.SILVER, "silver", "Silver Card"),
    GOLD(ApiMtwCardType.GOLD, "gold", "Gold Card"),
    PLATINUM(ApiMtwCardType.PLATINUM, "platinum", "Platinum Card"),
    BLACK(ApiMtwCardType.BLACK, "black", "Black Card");

    companion object {
        val ordered = listOf(STANDARD, SILVER, GOLD, PLATINUM, BLACK)

        fun accentColor(type: ApiMtwCardType): Int {
            return when (type) {
                ApiMtwCardType.STANDARD -> if (isDark) DEFAULT_TINT_DARK else DEFAULT_TINT_LIGHT
                ApiMtwCardType.SILVER -> "#929395".toColorInt()
                ApiMtwCardType.GOLD -> "#DF9B23".toColorInt()
                ApiMtwCardType.PLATINUM ->
                    if (isDark) "#D7DEE9".toColorInt() else "#2A2C39".toColorInt()

                ApiMtwCardType.BLACK -> Color.WHITE
            }
        }
    }
}
