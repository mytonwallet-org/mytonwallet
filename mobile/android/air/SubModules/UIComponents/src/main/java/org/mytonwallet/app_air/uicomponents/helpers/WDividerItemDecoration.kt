package org.mytonwallet.app_air.uicomponents.helpers

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.view.View
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class WDividerItemDecoration(
    private val marginStartPx: Float,
    private val marginEndPx: Float,
    private val backgroundColor: Int
) : RecyclerView.ItemDecoration() {

    private val paint = Paint().apply {
        color = WColor.Separator.color
        strokeWidth = 0.5f.dp
    }

    private val backgroundPaint = Paint().apply {
        color = backgroundColor
        strokeWidth = 0.5f.dp
    }

    override fun onDrawOver(c: Canvas, parent: RecyclerView, state: RecyclerView.State) {
        val left = marginStartPx
        val right = parent.width.toFloat() - marginEndPx

        for (i in 0 until parent.childCount) {
            val child = parent.getChildAt(i)

            if (parent.getChildAdapterPosition(child) == state.itemCount - 1) continue

            val bottom = child.bottom.toFloat()

            c.drawLine(left, bottom, right, bottom, paint)
            c.drawLine(0f, bottom, left, bottom, backgroundPaint)
        }
    }

    override fun getItemOffsets(
        outRect: Rect,
        view: View,
        parent: RecyclerView,
        state: RecyclerView.State
    ) {
        outRect.bottom = 0.5f.dp.toInt()
    }

}
