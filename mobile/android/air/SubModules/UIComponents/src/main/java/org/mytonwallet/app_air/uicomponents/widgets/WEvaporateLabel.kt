package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.util.TypedValue
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.htextview.evaporate.EvaporateTextView

open class WEvaporateLabel(context: Context) : EvaporateTextView(context), WThemedView {
    init {
        id = generateViewId()
    }

    fun setStyle(size: Float, font: WFont? = null) {
        typeface = (font ?: WFont.Regular).typeface
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
    }

    override fun updateTheme() {
        // To force change color on theme change
        if (!text.isNullOrEmpty()) {
            animateText(text, false)
        }
    }
}
