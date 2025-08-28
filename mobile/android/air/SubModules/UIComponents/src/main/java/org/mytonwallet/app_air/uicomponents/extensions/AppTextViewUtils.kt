package org.mytonwallet.app_air.uicomponents.extensions

import android.text.Spannable
import android.text.SpannableString
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan

fun AppCompatTextView.getSpan(text: String? = null, textSize: Int? = null): SpannableString {
    return SpannableString(text ?: this@getSpan.text ?: "").apply {
        setSpan(
            ForegroundColorSpan(currentTextColor),
            0,
            length,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        setSpan(
            AbsoluteSizeSpan(textSize ?: this@getSpan.textSize.toInt()),
            0,
            length,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        setSpan(
            WTypefaceSpan(typeface),
            0,
            length,
            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }
}
