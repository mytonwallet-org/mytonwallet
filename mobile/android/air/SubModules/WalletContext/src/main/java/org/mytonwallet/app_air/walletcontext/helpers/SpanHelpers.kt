package org.mytonwallet.app_air.walletcontext.helpers

import android.graphics.drawable.Drawable
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.DynamicDrawableSpan
import android.text.style.ImageSpan

object SpanHelpers {
    fun buildSpannableImage(
        drawable: Drawable?,
        align: Int = DynamicDrawableSpan.ALIGN_BOTTOM
    ): CharSequence {
        return drawable?.let {
            it.setBounds(0, 0, it.minimumWidth, it.minimumHeight)
            buildSpannable(" ", ImageSpan(it, align))
        } ?: ""
    }

    fun buildSpannable(text: String, span: Any): CharSequence {
        return SpannableStringBuilder(text).apply {
            setSpan(span, 0, text.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }
}
