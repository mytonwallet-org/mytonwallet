package org.mytonwallet.app_air.uicomponents.adapter.implementation.holders

import android.content.Context
import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.widgets.WAlertLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView

class ListAlertCell(context: Context) : WAlertLabel(context, coloredText = true), WThemedView {
    init {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
    }

    class Holder(parent: ViewGroup) :
        BaseListHolder<Item.Alert>(ListAlertCell(parent.context)) {
        private val view = itemView as ListAlertCell
        override fun onBind(item: Item.Alert) {
            view.text = item.text
        }
    }
}
