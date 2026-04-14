package org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter

import android.view.View
import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.adapter.implementation.CustomListAdapter
import org.mytonwallet.app_air.uicomponents.commonViews.WAddressActionView
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.holder.CellAddressAction
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.holder.CellHeaderSendRequest
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews.TotalCurrencyAmountView

class Adapter : CustomListAdapter() {
    var onAddressClick: ((View, WAddressActionView, TonConnectItem.Address) -> Unit)? = null

    override fun createHolder(parent: ViewGroup, viewType: Int): BaseListHolder<out BaseListItem> {
        return when (viewType) {
            TonConnectItem.Type.SEND_HEADER.value -> CellHeaderSendRequest.Holder(parent)
            TonConnectItem.Type.AMOUNT.value -> TotalCurrencyAmountView.Holder(parent)
            TonConnectItem.Type.ADDRESS.value -> CellAddressAction.Holder(parent) { anchorView, view, item ->
                onAddressClick?.invoke(anchorView, view, item)
            }

            else -> super.createHolder(parent, viewType)
        }
    }
}
