package org.mytonwallet.app_air.widgets.utils

import android.content.Context
import android.graphics.Typeface
import androidx.core.content.res.ResourcesCompat
import org.mytonwallet.app_air.walletbasecontext.R

// TODO:: Maybe we can use user's active font from settings later, instead of the system font
object FontUtils {
    fun balance(context: Context): Typeface {
        return ResourcesCompat.getFont(context, R.font.google_sans_flex_round_bold)!!
    }

    fun medium(context: Context): Typeface {
        return Typeface.create("sans-serif-medium", Typeface.NORMAL)
    }

    fun regular(context: Context): Typeface {
        return Typeface.create(Typeface.DEFAULT, Typeface.NORMAL)
    }
}
