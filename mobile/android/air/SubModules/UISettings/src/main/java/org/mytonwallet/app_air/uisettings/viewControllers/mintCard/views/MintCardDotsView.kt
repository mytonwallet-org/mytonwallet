package org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import kotlin.math.abs
import org.mytonwallet.app_air.uicomponents.extensions.dp

@SuppressLint("ViewConstructor")
class MintCardDotsView(context: Context, private val count: Int) : View(context) {

    private val activeRadius = 5f.dp
    private val inactiveRadius = 4f.dp
    private val spacing = 16f.dp
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }

    private var position = 0f

    fun setPosition(pos: Float) {
        if (pos == position) return
        position = pos
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = ((count - 1) * spacing + 2 * activeRadius).toInt()
        val height = (2 * activeRadius).toInt()
        setMeasuredDimension(
            resolveSize(width, widthMeasureSpec),
            resolveSize(height, heightMeasureSpec)
        )
    }

    override fun onDraw(canvas: Canvas) {
        val totalWidth = (count - 1) * spacing
        val startX = (width - totalWidth) / 2f
        val cy = height / 2f
        for (i in 0 until count) {
            val directDistance = abs(i - position)
            val distance = minOf(directDistance, count - directDistance).coerceIn(0f, 1f)
            paint.alpha = ((1f - distance) * (255 - 102) + 102).toInt() // 0.4..1.0 alpha
            val radius = activeRadius - distance * (activeRadius - inactiveRadius)
            val visualIndex = if (layoutDirection == LAYOUT_DIRECTION_RTL) count - 1 - i else i
            canvas.drawCircle(startX + visualIndex * spacing, cy, radius, paint)
        }
    }

    override fun onRtlPropertiesChanged(layoutDirection: Int) {
        super.onRtlPropertiesChanged(layoutDirection)
        invalidate()
    }
}
