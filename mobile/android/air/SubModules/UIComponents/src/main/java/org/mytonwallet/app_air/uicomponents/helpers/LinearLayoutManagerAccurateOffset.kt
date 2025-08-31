package org.mytonwallet.app_air.uicomponents.helpers;

import android.content.Context
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView

open class LinearLayoutManagerAccurateOffset(context: Context?) : LinearLayoutManager(context) {
    private val mChildSizesMap = HashMap<Int, Int>()

    override fun onLayoutCompleted(state: RecyclerView.State) {
        super.onLayoutCompleted(state)
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child != null) mChildSizesMap[getPosition(child)] = child.height
        }
    }

    override fun computeVerticalScrollOffset(state: RecyclerView.State): Int {
        if (childCount == 0) {
            return 0
        }

        val firstChild = getChildAt(0)
        val firstChildPosition = getPosition(firstChild!!)
        var scrolledY = -firstChild.y.toInt()
        for (i in 0 until firstChildPosition) {
            scrolledY += mChildSizesMap[i] ?: 0
        }
        return scrolledY
    }

    fun getItemHeight(position: Int): Int? {
        return mChildSizesMap[position]
    }
}
