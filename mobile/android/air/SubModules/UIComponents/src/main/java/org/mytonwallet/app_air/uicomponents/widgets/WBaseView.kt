package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.view.View
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

open class WBaseView(context: Context?) : View(context), WThemedView {
    init {
        id = generateViewId()
    }

    private var _backgroundColor: WColor? = null
    fun setBackground(wColor: WColor?) {
        _backgroundColor = wColor
        wColor?.let {
            setBackgroundColor(wColor.color)
        } ?: run {
            background = null
        }
    }

    override fun updateTheme() {
        if (background is SeparatorBackgroundDrawable)
            background.invalidateSelf()
        _backgroundColor?.let {
            setBackgroundColor(it.color)
        }
    }
}
