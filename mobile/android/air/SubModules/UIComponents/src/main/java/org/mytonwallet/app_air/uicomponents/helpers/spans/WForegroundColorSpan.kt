package org.mytonwallet.app_air.uicomponents.helpers.spans

import android.graphics.Color
import android.text.TextPaint
import android.text.style.CharacterStyle
import android.text.style.UpdateAppearance
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class WForegroundColorSpan() : CharacterStyle(), UpdateAppearance {
    constructor(wColor: WColor) : this() {
        this.wColor = wColor
    }

    var wColor: WColor? = null
    var color: Int = Color.GREEN

    override fun updateDrawState(textPaint: TextPaint) {
        textPaint.color = wColor?.color ?: color
    }
}
