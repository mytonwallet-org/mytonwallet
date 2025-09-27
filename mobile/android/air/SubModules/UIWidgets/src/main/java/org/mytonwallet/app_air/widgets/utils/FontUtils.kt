package org.mytonwallet.app_air.widgets.utils

import android.content.Context
import android.graphics.Typeface
import androidx.core.content.res.ResourcesCompat
import org.mytonwallet.app_air.walletbasecontext.R

// TODO:: Maybe we can use user's active font from settings later, instead of misans
object FontUtils {
    fun nunitoExtraBold(context: Context): Typeface {
        return ResourcesCompat.getFont(context, R.font.nunito_extra_bold)!!
    }

    fun semiBold(context: Context): Typeface {
        return ResourcesCompat.getFont(context, R.font.misans_semibold)!!
    }

    fun regular(context: Context): Typeface {
        return ResourcesCompat.getFont(context, R.font.misans_regular)!!
    }
}
