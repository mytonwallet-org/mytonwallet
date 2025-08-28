package org.mytonwallet.app_air.uicomponents.adapter.implementation.holders

import android.util.TypedValue
import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.CopyTextView
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color

class ListAddressCellHolder(parent: ViewGroup) :
    BaseListHolder<Item.Address>(CopyTextView(parent.context)) {
    private val view: CopyTextView = itemView as CopyTextView

    init {
        view.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        view.setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        view.includeFontPadding = false
        view.setPaddingDp(20, 8, 20, 20)
    }

    override fun onBind(item: Item.Address) {
        view.text = item.address
        view.typeface = WFont.Regular.typeface
        view.setTextColor(WColor.PrimaryText.color)
    }
}
