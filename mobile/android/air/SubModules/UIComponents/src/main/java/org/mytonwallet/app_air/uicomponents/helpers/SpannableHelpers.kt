package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.StyleSpan
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

object SpannableHelpers {
    fun encryptedCommentSpan(context: Context): SpannableStringBuilder {
        val builder = SpannableStringBuilder()
        ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.uicomponents.R.drawable.ic_lock
        )?.let { drawable ->
            drawable.mutate()
            drawable.setTint(Color.WHITE)
            val width = 16.dp
            val height = 16.dp
            drawable.setBounds(0, 0, width, height)
            val imageSpan = VerticalImageSpan(drawable)
            builder.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        builder.append(" ${LocaleController.getString("Encrypted Message")}")
        builder.setSpan(StyleSpan(Typeface.ITALIC), 0, builder.length, 0)
        return builder
    }
}
