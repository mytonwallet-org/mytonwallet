package org.mytonwallet.app_air.uicomponents.adapter.implementation.holders

import android.util.TypedValue
import android.view.ViewGroup
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.CopyTextView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class ListTextCellHolder(parent: ViewGroup) :
    BaseListHolder<Item.CopyableText>(FrameLayout(parent.context)) {

    private val container: FrameLayout = itemView as FrameLayout
    private val copyTextView: CopyTextView = CopyTextView(parent.context)

    init {
        container.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        container.setPaddingDp(16, 6, 16, 18)

        copyTextView.layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        copyTextView.setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        copyTextView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        copyTextView.includeFontPadding = false

        container.addView(copyTextView)
    }

    override fun onBind(item: Item.CopyableText) {
        copyTextView.text = item.address
        copyTextView.typeface = WFont.Regular.typeface
        copyTextView.setTextColor(WColor.PrimaryText.color)
        copyTextView.clipLabel = item.copyLabel
        copyTextView.clipToast = item.copyToast
    }
}
