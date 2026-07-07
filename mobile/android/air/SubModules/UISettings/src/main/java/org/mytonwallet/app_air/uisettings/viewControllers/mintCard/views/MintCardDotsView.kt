package org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp
import kotlin.math.abs

@SuppressLint("ViewConstructor")
class MintCardDotsView(context: Context, private val count: Int) : View(context) {

    private val dotRadius = 3f.dp
    private val spacing = 12f.dp
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }

    private var position = 0f

    fun setPosition(pos: Float) {
        if (pos == position) return
        position = pos
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = ((count - 1) * spacing + 2 * dotRadius).toInt()
        val height = (2 * dotRadius).toInt()
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
            val distance = abs(i - position).coerceIn(0f, 1f)
            paint.alpha = ((1f - distance) * (255 - 102) + 102).toInt() // 0.4..1.0 alpha
            canvas.drawCircle(startX + i * spacing, cy, dotRadius, paint)
        }
    }
}
