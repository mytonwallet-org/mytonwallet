package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.graphics.Typeface
import androidx.core.content.res.ResourcesCompat
import org.mytonwallet.app_air.walletbasecontext.R
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

enum class WFont {
    Regular,
    Medium,
    DemiBold,
    SemiBold,

    NunitoSemiBold,
    NunitoExtraBold
}

enum class FontFamily(val familyName: String, val displayName: String) {
    ROBOTO("roboto", "Roboto"),
    MISANS("misans", "Mi Sans");

    companion object {
        fun fromFamilyName(familyName: String?): FontFamily {
            return entries.firstOrNull { it.familyName == familyName } ?: MISANS
        }
    }
}

val WFont.typeface: Typeface
    get() {
        return when (this) {
            WFont.NunitoSemiBold -> FontManager.nunitoSemiBold
            WFont.NunitoExtraBold -> FontManager.nunitoExtraBold

            WFont.Regular -> FontManager.regular
            WFont.Medium -> FontManager.medium
            WFont.DemiBold -> FontManager.demiBold
            WFont.SemiBold -> FontManager.semiBold
        }
    }

val FontFamily.textOffset: Int
    get() {
        return 0
    }

object FontManager {
    lateinit var regular: Typeface
    lateinit var medium: Typeface
    lateinit var demiBold: Typeface
    lateinit var semiBold: Typeface

    lateinit var nunitoSemiBold: Typeface
    lateinit var nunitoExtraBold: Typeface

    lateinit var activeFont: FontFamily
        private set

    fun init(context: Context) {
        activeFont = FontFamily.fromFamilyName(WGlobalStorage.getActiveFont())

        when (activeFont) {
            FontFamily.ROBOTO -> {
                regular = ResourcesCompat.getFont(context, R.font.roboto_regular)!!
                medium = ResourcesCompat.getFont(context, R.font.roboto_medium)!!
                demiBold = ResourcesCompat.getFont(context, R.font.roboto_medium)!!
                semiBold = ResourcesCompat.getFont(context, R.font.roboto_semi_bold)!!
            }

            FontFamily.MISANS -> {
                regular = ResourcesCompat.getFont(context, R.font.misans_regular)!!
                medium = ResourcesCompat.getFont(context, R.font.misans_medium)!!
                demiBold = ResourcesCompat.getFont(context, R.font.misans_demi_bold)!!
                semiBold = ResourcesCompat.getFont(context, R.font.misans_semibold)!!
            }
        }

        nunitoSemiBold = ResourcesCompat.getFont(context, R.font.nunito_semi_bold)!!
        nunitoExtraBold = ResourcesCompat.getFont(context, R.font.nunito_extra_bold)!!
    }

    fun setActiveFont(context: Context, font: FontFamily) {
        activeFont = font
        WGlobalStorage.setActiveFont(font.familyName)
        init(context)
    }
}
