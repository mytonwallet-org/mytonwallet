package org.mytonwallet.app_air.uicomponents.viewControllers.selector.cells

import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.TokenItem
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class HolderTokenHeaderCell(
    parent: ViewGroup,
) : BaseListHolder<TokenItem.Title>(WLabel(parent.context)), WThemedView {
    private val title: WLabel = itemView as WLabel

    init {
        title.apply {
            setStyle(20f, WFont.Bold)
            setLineHeight(24f)
            setPadding(16.dp, 24.dp, 16.dp, 0)
        }

        title.layoutParams =
            ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 56.dp)

        updateTheme()
    }

    override fun updateTheme() {
        title.setTextColor(WColor.PrimaryText.color)
    }

    override fun onBind(item: TokenItem.Title) {
        title.text = item.title
    }
}
