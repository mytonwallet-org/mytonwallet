package org.mytonwallet.app_air.uicomponents.widgets.stories

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp

@SuppressLint("ViewConstructor")
internal class StoryProgressView(context: Context, private val count: Int) : View(context) {
    private var index = 0
    private var progress = 0f
    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb((0.35f * 255).toInt(), 255, 255, 255)
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }

    init {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    fun update(index: Int, progress: Float) {
        if (this.index == index && this.progress == progress) return
        this.index = index
        this.progress = progress
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        if (count == 0) return
        val gap = 4f.dp
        val width = maxOf(0f, (this.width - (count - 1) * gap) / count)
        val height = this.height.toFloat()
        val radius = height / 2
        val isRTL = layoutDirection == LAYOUT_DIRECTION_RTL
        for (i in 0 until count) {
            val visualIndex = if (isRTL) count - 1 - i else i
            val left = visualIndex * (width + gap)
            canvas.drawRoundRect(left, 0f, left + width, height, radius, radius, trackPaint)
            val fraction = when {
                i < index -> 1f
                i == index -> progress
                else -> 0f
            }
            val fillWidth = width * fraction
            if (fillWidth <= 0f) continue
            val fillLeft = if (isRTL) left + width - fillWidth else left
            canvas.drawRoundRect(
                fillLeft,
                0f,
                fillLeft + fillWidth,
                height,
                radius,
                radius,
                fillPaint
            )
        }
    }
}
