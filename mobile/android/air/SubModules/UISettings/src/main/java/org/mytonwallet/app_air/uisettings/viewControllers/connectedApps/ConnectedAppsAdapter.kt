package org.mytonwallet.app_air.uisettings.viewControllers.connectedApps

import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListAdapter
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.helpers.swipeRevealLayout.ViewBinderHelper

class ConnectedAppsAdapter : BaseListAdapter() {

    private var onClickListener: OnClickListener? = null
    private val viewBinderHelper = ViewBinderHelper()

    init {
        viewBinderHelper.setOpenOnlyOne(true)
    }

    interface OnClickListener {
        fun onDisconnectAllClick()
        fun onDisconnectClick(item: Item.DApp)
        fun onWarningClick(item: Item.DApp)
    }

    fun setOnItemClickListener(listener: OnClickListener?) {
        onClickListener = listener
    }

    override fun createHolder(parent: ViewGroup, viewType: Int): BaseListHolder<out Item> {
        val onDisconnect: (Item.DApp) -> Unit = {
            onClickListener?.onDisconnectClick(it)
        }
        val onWarning: (Item.DApp) -> Unit = {
            onClickListener?.onWarningClick(it)
        }
        return when (viewType) {
            Item.Type.DAPP.value -> HolderConnectedAppsCell(parent, onDisconnect, onWarning).apply {
                itemView.setOnClickListener {}

                cell.mainView.isClickable = true
                cell.secondaryView.setOnClickListener {
                    item?.let { onClickListener?.onDisconnectClick(it) }
                }
            }

            Item.Type.HEADER.value -> HolderConnectedHeaderCell(parent).apply {
                cell.disconnectContainer.setOnClickListener {
                    onClickListener?.onDisconnectAllClick()
                }
            }

            else -> throw IllegalArgumentException("Unknown viewType: $viewType")
        }
    }

    override fun onBindViewHolder(holder: BaseListHolder<out BaseListItem>, position: Int) {
        super.onBindViewHolder(holder, position)
        val item = currentList[position]
        if (item is Item.DApp) {
            viewBinderHelper.bind(
                (holder as HolderConnectedAppsCell).cell.swipeRevealLayout,
                item.key.toString()
            )
        }
    }
}
