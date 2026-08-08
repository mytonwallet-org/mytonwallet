package org.mytonwallet.app_air.widgets.utils

import android.content.Context
import android.graphics.Typeface
import androidx.core.content.res.ResourcesCompat
import org.mytonwallet.app_air.walletbasecontext.R
import org.mytonwallet.app_air.walletbasecontext.WBaseStorage
import org.mytonwallet.app_air.walletbasecontext.localization.WLanguage

// TODO:: Maybe we can use user's active font from settings later, instead of the system font
object FontUtils {
    private val useVazirmatn: Boolean
        get() {
            val lang = WBaseStorage.getActiveLanguage()
            return lang == WLanguage.PERSIAN.langCode || lang == WLanguage.ARABIC.langCode
        }

    fun balance(context: Context): Typeface =
        ResourcesCompat.getFont(context, R.font.google_sans_flex_round_bold)!!

    fun medium(context: Context): Typeface {
        if (useVazirmatn) return ResourcesCompat.getFont(context, R.font.vazirmatn_semibold)!!
        return Typeface.create("sans-serif-medium", Typeface.NORMAL)
    }

    fun regular(context: Context): Typeface {
        if (useVazirmatn) return ResourcesCompat.getFont(context, R.font.vazirmatn_regular)!!
        return Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }
}
