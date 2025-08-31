package org.mytonwallet.app_air.uicomponents.adapter

import android.content.Context
import android.view.View
import androidx.annotation.CallSuper
import androidx.recyclerview.widget.RecyclerView

abstract class BaseListHolder<I: BaseListItem>(
    view: View
): RecyclerView.ViewHolder(view) {
    val context: Context
        get() = itemView.context

    var item: I? = null
        private set

    fun <V : View> findViewById(id: Int): V = itemView.findViewById(id)

    @CallSuper
    open fun bind(item: BaseListItem) {
        this.item = item as I
        onBind(item)
    }

    abstract fun onBind(item: I)

    fun unbind() {
        item = null
        onUnbind()
    }

    @CallSuper
    open fun onUnbind() {

    }
}
