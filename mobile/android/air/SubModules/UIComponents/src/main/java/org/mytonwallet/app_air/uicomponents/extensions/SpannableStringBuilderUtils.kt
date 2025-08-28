package org.mytonwallet.app_air.uicomponents.extensions

import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.Spanned
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan

private const val dots = "···"
fun SpannableStringBuilder.updateDotsTypeface(startIndex: Int = 0) {
    val index = indexOf(dots, startIndex = startIndex)
    if (index > -1) {
        setSpan(
            WTypefaceSpan(Typeface.DEFAULT_BOLD),
            index,
            index + 3,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }
}

