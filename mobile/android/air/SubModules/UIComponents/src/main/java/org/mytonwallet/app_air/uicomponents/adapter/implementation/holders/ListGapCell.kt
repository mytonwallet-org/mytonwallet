package org.mytonwallet.app_air.uicomponents.adapter.implementation.holders

import android.content.Context
import android.graphics.drawable.Drawable
import android.view.View
import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor

class ListGapCell(
    context: Context,
    private val gap: Int = 12.dp
) : View(context), WThemedView {

    var showSeparator: Boolean = true
        set(value) {
            field = value
            background = null
        }

    val drawable: Drawable by lazy {
        SeparatorBackgroundDrawable().apply {
            backgroundWColor = WColor.SecondaryBackground
            isTop = true
        }
    }

    init {
        layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, gap)
        showSeparator = true
        updateTheme()
    }

    override fun updateTheme() {
        invalidate()
    }

    class Holder(parent: ViewGroup) :
        BaseListHolder<Item.Gap>(ListGapCell(parent.context).apply {
            layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, gap)
        }) {
        override fun onBind(item: Item.Gap) {}
    }
}




