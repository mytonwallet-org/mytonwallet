package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.os.Build
import android.view.ViewGroup
import androidx.core.graphics.withSave
import org.mytonwallet.app_air.uicomponents.extensions.dp

class WShiningView(context: Context?) : ViewGroup(context) {
    // Pre-P renderers clip without anti-aliasing, so there the ring is punched out of a software
    // layer instead of clipped.
    private val clipsInnerRect = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P

    init {
        id = generateViewId()
        if (!clipsInnerRect) setLayerType(LAYER_TYPE_SOFTWARE, null)
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

    override fun draw(canvas: Canvas) {
        if (!clipsInnerRect || !updateInnerPath()) {
            super.draw(canvas)
            return
        }
        canvas.withSave {
            clipOutPath(innerPath)
            super.draw(this)
        }
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        if (!clipsInnerRect && updateInnerPath()) canvas.drawPath(innerPath, clearPaint)
    }

    private fun updateInnerPath(): Boolean {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return false
        innerRect.set(borderWidth, borderWidth, w - borderWidth, h - borderWidth)
        innerPath.reset()
        val innerRadius = maxOf(0f, radius - borderWidth)
        innerPath.addRoundRect(innerRect, innerRadius, innerRadius, Path.Direction.CW)
        return true
    }
}
