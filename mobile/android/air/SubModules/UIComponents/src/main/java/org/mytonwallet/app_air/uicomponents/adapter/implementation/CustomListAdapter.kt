package org.mytonwallet.app_air.uicomponents.adapter.implementation

import android.view.View
import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.adapter.BaseListAdapter
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListAlertCell
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListExpandableTextCell
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListGapCell
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListIconDualLineCell
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListTextCell
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListTextCellHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListTitleValueCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivityCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

// TODO: There is TonConnectRequestSendVC.kt screen using this class for CustomListAdapter.ItemClickListener
//  instead of using WRecyclerViewAdapter, let's unify it :)
@Deprecated(
    message = "Use WRecyclerViewAdapter instead of CustomListAdapter",
    replaceWith = ReplaceWith("WRecyclerViewAdapter")
)
open class CustomListAdapter : BaseListAdapter() {
    interface ItemClickListener {
        fun onItemClickToken(view: View, position: Int, item: BaseListItem, token: IApiToken) {}
        fun onItemClickIndex(view: View, position: Int, item: BaseListItem, index: Int) {}
        fun onItemClickItems(
            view: View,
            position: Int,
            item: BaseListItem,
            items: List<BaseListItem>
        ) {
        }
    }

    private var onItemClickListener: ItemClickListener? = null
    fun setOnItemClickListener(listener: ItemClickListener?) {
        onItemClickListener = listener
    }

    override fun createHolder(parent: ViewGroup, viewType: Int): BaseListHolder<out BaseListItem> {
        return when (viewType) {
            Item.Type.LIST_TITLE.value -> HeaderCell.Holder(parent.context)
            Item.Type.LIST_TITLE_VALUE.value -> ListTitleValueCell.Holder(parent)
            Item.Type.ICON_DUAL_LINE.value -> ListIconDualLineCell.Holder(parent)
            Item.Type.TEXT.value -> ListTextCell.Holder(parent)
            Item.Type.COPYABLE_TEXT.value -> ListTextCellHolder(parent)
            Item.Type.EXPANDABLE_TEXT.value -> ListExpandableTextCell.Holder(parent)
            Item.Type.GAP.value -> ListGapCell.Holder(parent)
            Item.Type.ACTIVITY.value -> ActivityCell.Holder(parent)
            Item.Type.ALERT.value -> ListAlertCell.Holder(parent)
            else -> throw IllegalArgumentException("Unknown viewType: $viewType")
        }
    }

    override fun onBindViewHolder(holder: BaseListHolder<out BaseListItem>, position: Int) {
        applyClickable(holder, getItem(position), position)
        super.onBindViewHolder(holder, position)
        if (holder.item?.type == Item.Type.GAP.value)
            return
        val isPreviousViewGap = position > 0 && getItem(position - 1).type == Item.Type.GAP.value
        val isNextViewGap =
            position < itemCount - 1 && getItem(position + 1).type == Item.Type.GAP.value
        val isLast = position == itemCount - 1
        val topRadius = when {
            position == 0 -> ViewConstants.TOOLBAR_RADIUS.dp
            isPreviousViewGap -> ViewConstants.BLOCK_RADIUS.dp
            else -> 0f
        }
        val bottomRadius = when {
            isLast || isNextViewGap -> ViewConstants.BLOCK_RADIUS.dp
            else -> 0f
        }
        if (holder !is ListAlertCell.Holder)
            holder.itemView.setBackgroundColor(
                WColor.Background.color,
                topRadius,
                bottomRadius
            )
    }

    private fun applyClickable(
        holder: BaseListHolder<out BaseListItem>,
        item: BaseListItem,
        position: Int
    ) {
        val clickableItem = item as? Item.IClickable ?: return
        holder.itemView.isClickable = clickableItem.clickable != null

        val clickable = clickableItem.clickable ?: return
        when (clickable) {
            is Item.Clickable.Token -> holder.itemView.setOnClickListener {
                onItemClickListener?.onItemClickToken(it, position, item, clickable.token)
            }

            is Item.Clickable.Index -> holder.itemView.setOnClickListener {
                onItemClickListener?.onItemClickIndex(it, position, item, clickable.index)
            }

            is Item.Clickable.Items -> holder.itemView.setOnClickListener {
                onItemClickListener?.onItemClickItems(it, position, item, clickable.items)
            }
        }
    }
}
