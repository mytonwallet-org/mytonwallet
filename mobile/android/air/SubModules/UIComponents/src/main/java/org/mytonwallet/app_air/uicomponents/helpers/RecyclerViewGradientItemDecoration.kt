package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.graphics.Canvas
import android.view.Gravity
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.RecyclerView.ItemDecoration
import org.mytonwallet.app_air.uicomponents.drawable.RecyclerViewGradientDrawable
import org.mytonwallet.app_air.uicomponents.extensions.isBottomScrollReached
import org.mytonwallet.app_air.uicomponents.extensions.isTopScrollReached

class RecyclerViewGradientItemDecoration(context: Context) : ItemDecoration() {
    val top = RecyclerViewGradientDrawable(context, Gravity.TOP)
    val bottom = RecyclerViewGradientDrawable(context, Gravity.BOTTOM)

    override fun onDrawOver(canvas: Canvas, parent: RecyclerView, state: RecyclerView.State) {
        if (!parent.isTopScrollReached) {   // todo animations
            top.setBounds(0, 0, parent.measuredWidth, parent.measuredHeight)
            top.draw(canvas)
        }

        if (!parent.isBottomScrollReached) {
            bottom.setBounds(0, 0, parent.measuredWidth, parent.measuredHeight)
            bottom.draw(canvas)
        }
    }

    var color = 0
        set(value) {
            field = value
            top.color = value
            bottom.color = value
        }
}