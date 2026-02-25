package org.mytonwallet.app_air.uicomponents.extensions

import android.graphics.Typeface
import android.os.Build
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import kotlin.math.max

private const val dots = "···"

fun SpannableStringBuilder.styleDots(startIndex: Int = 0) {
    val index = indexOf(dots, startIndex = startIndex)
    if (index > -1) {
        setSpan(
            WTypefaceSpan(Typeface.DEFAULT_BOLD),
            index,
            index + dots.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
    }
}

fun CharSequence.measureWidth(paint: TextPaint): Float {
    if (isEmpty()) {
        return 0f
    }

    if (this !is Spanned && !contains("\n")) {
        return paint.measureText(this, 0, length)
    }

    return createLayoutCompat(this, paint).maxLineWidth()
}

private fun createLayoutCompat(text: CharSequence, paint: TextPaint): StaticLayout {
    val maxWidthPx = Int.MAX_VALUE

    //noinspection WrongConstant
    return if (Build.VERSION.SDK_INT >= 28) {
        StaticLayout.Builder
            .obtain(text, 0, text.length, paint, maxWidthPx)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setIncludePad(false)
            .setBreakStrategy(Layout.BREAK_STRATEGY_SIMPLE)
            .setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NONE)
            .setUseLineSpacingFromFallbacks(false)
            .build()
    } else {
        StaticLayout.Builder
            .obtain(text, 0, text.length, paint, maxWidthPx)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setIncludePad(false)
            .build()
    }
}

private fun StaticLayout.maxLineWidth(): Float {
    var max = 0f
    for (i in 0 until lineCount) {
        max = max(max, getLineWidth(i))
    }
    return max
}
