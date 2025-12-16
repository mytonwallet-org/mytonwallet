package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.view.ViewGroup
import org.mytonwallet.app_air.uicomponents.extensions.dp

class WShiningView(context: Context?) : ViewGroup(context) {
    init {
        id = generateViewId()
        setLayerType(LAYER_TYPE_SOFTWARE, null)
        setWillNotDraw(false)
    }

    var radius = 20f
        set(value) {
            field = value
            invalidate()
        }

    var borderWidth = 1.5f.dp
        set(value) {
            field = value
            invalidate()
        }

    private val clearPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
    }

    private val innerPath = Path()
    private val innerRect = RectF()

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            child.layout(0, 0, width, height)
        }
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)

        val w = width.toFloat()
        val h = height.toFloat()
        if (w > 0 && h > 0) {
            innerRect.set(borderWidth, borderWidth, w - borderWidth, h - borderWidth)
            innerPath.reset()
            val innerRadius = maxOf(0f, radius - borderWidth)
            innerPath.addRoundRect(innerRect, innerRadius, innerRadius, Path.Direction.CW)
            canvas.drawPath(innerPath, clearPaint)
        }
    }
}
