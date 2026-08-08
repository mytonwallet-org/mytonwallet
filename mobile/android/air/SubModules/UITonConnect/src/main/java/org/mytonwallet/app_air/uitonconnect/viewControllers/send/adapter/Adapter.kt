package org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter

import android.view.View
import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.adapter.implementation.CustomListAdapter
import org.mytonwallet.app_air.uicomponents.commonViews.WAddressActionView
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.holder.CellAddressAction
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.holder.CellHeaderSendRequest
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.holder.CellPreviewFee
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews.TotalCurrencyAmountView

class Adapter : CustomListAdapter() {
    var onAddressClick: ((View, WAddressActionView, TonConnectItem.Address) -> Unit)? = null
    var onPreviewFeeClick: ((TonConnectItem.PreviewFee) -> Unit)? = null

    override fun onBindViewHolder(holder: BaseListHolder<out BaseListItem>, position: Int) {
        super.onBindViewHolder(holder, position)
        if (
            holder.item is TonConnectItem.SendRequestHeader ||
            holder.item is TonConnectItem.CurrencyAmount ||
            holder.item is TonConnectItem.PreviewFee
        ) {
            holder.itemView.background = null
        }
    }

    override fun createHolder(parent: ViewGroup, viewType: Int): BaseListHolder<out BaseListItem> =
        when (viewType) {
            TonConnectItem.Type.SEND_HEADER.value -> CellHeaderSendRequest.Holder(parent)

            TonConnectItem.Type.AMOUNT.value -> TotalCurrencyAmountView.Holder(parent)

            TonConnectItem.Type.PREVIEW_FEE.value -> CellPreviewFee.Holder(parent) {
                onPreviewFeeClick?.invoke(it)
            }

            TonConnectItem.Type.ADDRESS.value -> CellAddressAction.Holder(parent) {
                    anchorView,
                    view,
                    item
                ->
                onAddressClick?.invoke(anchorView, view, item)
            }

            else -> super.createHolder(parent, viewType)
        }
}
