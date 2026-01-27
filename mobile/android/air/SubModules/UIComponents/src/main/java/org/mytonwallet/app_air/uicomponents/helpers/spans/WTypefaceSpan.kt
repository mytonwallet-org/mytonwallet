package org.mytonwallet.app_air.uicomponents.helpers.spans

import android.graphics.Typeface
import android.text.TextPaint
import android.text.style.MetricAffectingSpan
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class WTypefaceSpan(
    private val typeface: Typeface?,
    var foregroundColor: Int? = null
) : MetricAffectingSpan() {

    constructor(font: WFont? = null, color: WColor? = null) : this(font?.typeface, color?.color)

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
