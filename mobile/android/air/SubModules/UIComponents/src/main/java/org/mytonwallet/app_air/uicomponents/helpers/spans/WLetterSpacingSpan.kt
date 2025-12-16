package org.mytonwallet.app_air.uicomponents.helpers.spans

import android.text.TextPaint
import android.text.style.MetricAffectingSpan

class WLetterSpacingSpan(private val letterSpacing: Float) : MetricAffectingSpan() {

    override fun updateDrawState(tp: TextPaint) {
        apply(tp)
    }

    override fun updateMeasureState(tp: TextPaint) {
        apply(tp)
    }

    private fun apply(tp: TextPaint) {
        tp.letterSpacing = letterSpacing
    }
}
