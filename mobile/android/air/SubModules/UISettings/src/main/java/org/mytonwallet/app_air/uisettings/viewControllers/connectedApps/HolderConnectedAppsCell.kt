package org.mytonwallet.app_air.uisettings.viewControllers.connectedApps

import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uisettings.viewControllers.connectedApps.cells.ConnectedAppsCell

class HolderConnectedAppsCell(parent: ViewGroup, val onDisconnect: (Item.DApp) -> Unit) :
    BaseListHolder<Item.DApp>(ConnectedAppsCell(parent.context)) {
    val cell = itemView as ConnectedAppsCell

    override fun onBind(item: Item.DApp) {
        cell.configure(item.app, item.isLastItem) {
            onDisconnect.invoke(item)
        }
    }
}
