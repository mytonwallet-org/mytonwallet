package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.graphics.Typeface
import android.os.Build
import androidx.core.content.res.ResourcesCompat
import org.mytonwallet.app_air.walletbasecontext.R
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

enum class WFont {
    Regular,
    Medium,
    Bold,

    Balance
}

enum class FontFamily(val familyName: String, val displayName: String) {
    SYSTEM("system", "System"),
    MISANS("misans", "Mi Sans");

    companion object {
        private val deviceDefault: FontFamily
            get() = if (Build.MANUFACTURER.equals("samsung", ignoreCase = true)) MISANS else SYSTEM

        fun fromFamilyName(familyName: String?): FontFamily {
            return entries.firstOrNull { it.familyName == familyName } ?: deviceDefault
        }
    }
}

val WFont.typeface: Typeface
    get() {
        return when (this) {
            WFont.Balance -> FontManager.balance

            WFont.Regular -> FontManager.regular
            WFont.Medium -> FontManager.medium
            WFont.Bold -> FontManager.bold
        }
    }

fun adaptiveFontSize(base: Float = 16f): Float {
    val screenAdjusted = if (ApplicationContextHolder.isSmallScreen) base - 1f else base
    // Mi Sans glyphs are ~4% taller than other families at the same size (cap height
    // 0.74em vs ~0.72em), so it reads larger; compensate with a 0.5sp reduction.
    return if (FontManager.activeFont == FontFamily.MISANS) screenAdjusted - 0.5f else screenAdjusted
}

object FontManager {
    lateinit var regular: Typeface
    lateinit var medium: Typeface
    lateinit var bold: Typeface

    lateinit var balance: Typeface

    lateinit var activeFont: FontFamily
        private set

    fun init(context: Context) {
        activeFont = FontFamily.fromFamilyName(WGlobalStorage.getActiveFont())

        when (activeFont) {
            FontFamily.SYSTEM -> {
                regular = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
                medium = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                bold = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            }

            FontFamily.MISANS -> {
                regular = ResourcesCompat.getFont(context, R.font.misans_regular)!!
                // Mi Sans Medium (380) is too light for the emphasis weight, use Demibold (450)
                medium = ResourcesCompat.getFont(context, R.font.misans_demibold)!!
                bold = ResourcesCompat.getFont(context, R.font.misans_bold)!!
            }
        }

        balance = if (WGlobalStorage.isRoundedBalanceFontActive()) {
            ResourcesCompat.getFont(context, R.font.google_sans_flex_round_bold)!!
        } else {
            bold
        }
    }

    fun setActiveFont(context: Context, font: FontFamily) {
        activeFont = font
        WGlobalStorage.setActiveFont(font.familyName)
        init(context)
    }
}
