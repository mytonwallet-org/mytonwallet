package org.mytonwallet.app_air.uicomponents.helpers.spans

import android.graphics.Typeface
import android.text.TextPaint
import android.text.style.MetricAffectingSpan

class WTypefaceSpan(private val typeface: Typeface?, private val foregroundColor: Int? = null) :
    MetricAffectingSpan() {
    override fun updateDrawState(paint: TextPaint) {
        paint.typeface = typeface
        foregroundColor?.let {
            paint.color = it
        }
    }

    override fun updateMeasureState(paint: TextPaint) {
        paint.typeface = typeface
    }
}
