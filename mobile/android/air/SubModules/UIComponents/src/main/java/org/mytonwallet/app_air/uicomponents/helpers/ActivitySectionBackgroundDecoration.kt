package org.mytonwallet.app_air.uicomponents.helpers

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class ActivitySectionBackgroundDecoration(
    private val firstPosition: () -> Int,
    private val rowCount: () -> Int
) : RecyclerView.ItemDecoration() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val bounds = RectF()
    private val radii = FloatArray(8)
    private val cardPath = Path()
    private val cornerPath = Path()
    private var hasBackground = false
    private var hasCorners = false

    override fun onDraw(canvas: Canvas, parent: RecyclerView, state: RecyclerView.State) {
        hasBackground = false
        val first = firstPosition()
        val count = rowCount()
        if (count <= 0) return
        val last = first + count - 1
        var hasFirst = false
        var hasLast = false
        for (i in 0 until parent.childCount) {
            val child = parent.getChildAt(i)
            val position = parent.getChildAdapterPosition(child)
            if (position < first || position > last || child.visibility != View.VISIBLE) continue
            val left = child.left + child.translationX
            val top = child.top + child.translationY
            val right = child.right + child.translationX
            val bottom = child.bottom + child.translationY
            if (!hasBackground) {
                bounds.set(left, top, right, bottom)
                paint.alpha = (child.alpha * 255).toInt()
                hasBackground = true
            } else {
                bounds.union(left, top, right, bottom)
            }
            hasFirst = hasFirst || position == first
            hasLast = hasLast || position == last
        }
        if (!hasBackground || bounds.isEmpty) {
            hasBackground = false
            return
        }
        val radius = ViewConstants.BLOCK_RADIUS.dp
        hasCorners = radius > 0f && (hasFirst || hasLast)
        val alpha = paint.alpha
        paint.color = WColor.Background.color
        paint.alpha = alpha
        if (hasCorners) {
            radii.fill(if (hasFirst) radius else 0f, 0, 4)
            radii.fill(if (hasLast) radius else 0f, 4, 8)
            cardPath.reset()
            cardPath.addRoundRect(bounds, radii, Path.Direction.CW)
            canvas.drawPath(cardPath, paint)
        } else {
            canvas.drawRect(bounds, paint)
        }
    }

    override fun onDrawOver(canvas: Canvas, parent: RecyclerView, state: RecyclerView.State) {
        if (!hasBackground || !hasCorners) return
        // Keep row content and ripples inside the card's animated corners.
        cornerPath.reset()
        cornerPath.addRect(bounds, Path.Direction.CW)
        cornerPath.op(cardPath, Path.Op.DIFFERENCE)
        paint.color = WColor.SecondaryBackground.color
        canvas.drawPath(cornerPath, paint)
    }
}
