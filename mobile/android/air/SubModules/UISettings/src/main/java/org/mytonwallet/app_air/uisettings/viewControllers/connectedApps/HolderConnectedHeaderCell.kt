package org.mytonwallet.app_air.uisettings.viewControllers.connectedApps

import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uisettings.viewControllers.connectedApps.cells.ConnectedHeaderCell

class HolderConnectedHeaderCell(parent: ViewGroup) :
    BaseListHolder<Item.Header>(ConnectedHeaderCell(parent.context)) {
    val cell = itemView as ConnectedHeaderCell

    override fun onBind(item: Item.Header) {}
}