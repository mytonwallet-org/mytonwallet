package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.graphics.Typeface
import android.os.Build
import androidx.core.content.res.ResourcesCompat
import org.mytonwallet.app_air.walletbasecontext.R
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage
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

        fun fromFamilyName(familyName: String?): FontFamily = entries.firstOrNull {
            it.familyName == familyName
        } ?: deviceDefault
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
    return if (FontManager.activeFont ==
        FontFamily.MISANS
    ) {
        screenAdjusted - 0.5f
    } else {
        screenAdjusted
    }
}

object FontManager {
    lateinit var regular: Typeface
    lateinit var medium: Typeface
    lateinit var bold: Typeface

    lateinit var balance: Typeface

    lateinit var ltrRegular: Typeface
        private set
    lateinit var ltrMedium: Typeface
        private set
    lateinit var ltrBold: Typeface
        private set

    lateinit var activeFont: FontFamily
        private set

    var inlineIconVerticalOffsetEm = 0f
        private set

    fun init(context: Context) {
        activeFont = FontFamily.fromFamilyName(WGlobalStorage.getActiveFont())

        when (activeFont) {
            FontFamily.SYSTEM -> {
                ltrRegular = Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
                ltrMedium = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                ltrBold = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            }

            FontFamily.MISANS -> {
                ltrRegular = ResourcesCompat.getFont(context, R.font.misans_regular)!!
                ltrMedium = ResourcesCompat.getFont(context, R.font.misans_demibold)!!
                ltrBold = ResourcesCompat.getFont(context, R.font.misans_bold)!!
            }
        }

        val activeLang = WBaseStorage.getActiveLanguage()
        val useVazirmatn =
            activeLang == WLanguage.PERSIAN.langCode || activeLang == WLanguage.ARABIC.langCode
        inlineIconVerticalOffsetEm = if (useVazirmatn) -1f / 14f else 0f
        if (useVazirmatn) {
            regular = ResourcesCompat.getFont(context, R.font.vazirmatn_regular)!!
            medium = ResourcesCompat.getFont(context, R.font.vazirmatn_semibold)!!
            bold = ResourcesCompat.getFont(context, R.font.vazirmatn_bold)!!
        } else {
            regular = ltrRegular
            medium = ltrMedium
            bold = ltrBold
        }

        balance = if (WGlobalStorage.isRoundedBalanceFontActive()) {
            ResourcesCompat.getFont(context, R.font.google_sans_flex_round_bold)!!
        } else {
            bold
        }
    }

    fun ltrVariant(typeface: Typeface?): Typeface? = when {
        !::ltrRegular.isInitialized -> typeface
        typeface === regular -> ltrRegular
        typeface === medium -> ltrMedium
        typeface === bold -> ltrBold
        else -> typeface
    }

    fun setActiveFont(context: Context, font: FontFamily) {
        activeFont = font
        WGlobalStorage.setActiveFont(font.familyName)
        init(context)
    }
}
