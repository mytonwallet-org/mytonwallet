package org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter

import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.adapter.implementation.CustomListAdapter
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.holder.CellHeaderSendRequest
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews.TotalCurrencyAmountView

class Adapter : CustomListAdapter() {
    override fun createHolder(parent: ViewGroup, viewType: Int): BaseListHolder<out BaseListItem> {
        return when (viewType) {
            TonConnectItem.Type.SEND_HEADER.value -> CellHeaderSendRequest.Holder(parent)
            TonConnectItem.Type.AMOUNT.value -> TotalCurrencyAmountView.Holder(parent)
            else -> super.createHolder(parent, viewType)
        }
    }
}
