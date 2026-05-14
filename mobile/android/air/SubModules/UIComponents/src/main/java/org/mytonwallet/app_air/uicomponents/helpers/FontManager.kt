package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.graphics.Typeface
import androidx.core.content.res.ResourcesCompat
import org.mytonwallet.app_air.walletbasecontext.R
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder

enum class WFont {
    Regular,
    Medium,
    DemiBold,
    SemiBold,

    NunitoSemiBold,
    NunitoExtraBold
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

fun adaptiveFontSize(base: Float = 16f): Float {
    val screenAdjusted = if (ApplicationContextHolder.isSmallScreen) base - 1f else base
    return screenAdjusted - 0.5f
}

object FontManager {
    lateinit var regular: Typeface
    lateinit var medium: Typeface
    lateinit var demiBold: Typeface
    lateinit var semiBold: Typeface

    lateinit var nunitoSemiBold: Typeface
    lateinit var nunitoExtraBold: Typeface

    fun init(context: Context) {
        regular = ResourcesCompat.getFont(context, R.font.misans_regular)!!
        medium = ResourcesCompat.getFont(context, R.font.misans_medium)!!
        demiBold = ResourcesCompat.getFont(context, R.font.misans_demi_bold)!!
        semiBold = ResourcesCompat.getFont(context, R.font.misans_semibold)!!

        nunitoSemiBold = ResourcesCompat.getFont(context, R.font.nunito_semi_bold)!!
        nunitoExtraBold = ResourcesCompat.getFont(context, R.font.nunito_extra_bold)!!
    }
}