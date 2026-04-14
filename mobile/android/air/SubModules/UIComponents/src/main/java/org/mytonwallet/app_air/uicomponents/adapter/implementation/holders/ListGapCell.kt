package org.mytonwallet.app_air.uicomponents.adapter.implementation.holders

import android.content.Context
import android.view.View
import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.extensions.dp

class ListGapCell(context: Context, gap: Int = 12.dp) : View(context) {

    init {
        layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, gap)
    }

    fun configure(item: Item.Gap) {
        if (layoutParams.height == item.height) {
            return
        }
        layoutParams = layoutParams.apply {
            height = item.height
        }
        requestLayout()
    }

    class Holder(parent: ViewGroup) : BaseListHolder<Item.Gap>(ListGapCell(parent.context)) {

        private val view = itemView as ListGapCell

        override fun onBind(item: Item.Gap) {
            view.configure(item)
        }
    }
}
