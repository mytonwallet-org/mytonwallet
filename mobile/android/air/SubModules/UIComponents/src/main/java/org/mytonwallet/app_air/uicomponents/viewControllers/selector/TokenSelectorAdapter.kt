package org.mytonwallet.app_air.uicomponents.viewControllers.selector

import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.adapter.implementation.CustomListAdapter
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.cells.HolderTokenHeaderCell

open class TokenSelectorAdapter : CustomListAdapter() {
    override fun createHolder(parent: ViewGroup, viewType: Int): BaseListHolder<out BaseListItem> {
        return when (viewType) {
            TokenItem.Type.TITLE.value -> HolderTokenHeaderCell(parent)
            else -> super.createHolder(parent, viewType)
        }
    }
}
