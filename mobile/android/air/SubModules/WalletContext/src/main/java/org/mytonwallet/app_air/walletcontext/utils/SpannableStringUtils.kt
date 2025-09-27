package org.mytonwallet.app_air.walletcontext.utils

import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.style.StyleSpan

fun SpannableString.toProcessedSpannableStringBuilder(): SpannableStringBuilder {
    val spannable = SpannableStringBuilder()

    val parts = split("**")
    var isBold = false
    for (part in parts) {
        val start = spannable.length
        spannable.append(part)
        val end = spannable.length

        if (isBold) {
            spannable.setSpan(
                StyleSpan(Typeface.BOLD),
                start,
                end,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        isBold = !isBold
    }

    return spannable
}
