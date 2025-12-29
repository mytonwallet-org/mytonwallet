package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.recyclerview.widget.RecyclerView

@SuppressLint("ViewConstructor")
open class WCell(
    context: Context,
    layoutParams: ViewGroup.LayoutParams = ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
) : WView(context, layoutParams) {
    class Holder(val cell: WCell) : RecyclerView.ViewHolder(cell)
    class Type(val value: Int)

}
