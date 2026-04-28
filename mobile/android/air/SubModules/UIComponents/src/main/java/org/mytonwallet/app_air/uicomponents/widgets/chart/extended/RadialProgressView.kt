package org.mytonwallet.app_air.uicomponents.widgets.chart.extended

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View

class RadialProgressView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 4f
    }
    private var sizePx = 24

    fun setSize(size: Int) {
        sizePx = size
        requestLayout()
    }

    fun setStrokeWidth(width: Float) {
        paint.strokeWidth = width
        invalidate()
    }

    fun setProgressColor(color: Int) {
        paint.color = color
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(sizePx, sizePx)
    }

    override fun onDraw(canvas: Canvas) {
        val pad = paint.strokeWidth
        canvas.drawArc(pad, pad, width - pad, height - pad, -90f, 270f, false, paint)
    }
}
