package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.Drawable
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

class WCutoutDrawable() : Drawable() {
    private var alpha: Int = 255

    var color: Int = WColor.PopupWindow.color
        set(value) {
            field = value
            paint.color = getPaintColor()
            invalidateSelf()
        }

    var cutoutPath: Path? = null
        set(value) {
            field = value
            rebuildPath()
            invalidateSelf()
        }

    private val drawPath = Path().apply {
        fillType = Path.FillType.EVEN_ODD
    }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = getPaintColor()
        style = Paint.Style.FILL
    }

    private fun getPaintColor(): Int = color.colorWithAlpha(alpha)

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        rebuildPath()
    }

    private fun rebuildPath() {
        val bounds = this.bounds
        if (bounds.isEmpty) {
            return
        }

        with(drawPath) {
            reset()
            addRect(
                bounds.left.toFloat(),
                bounds.top.toFloat(),
                bounds.right.toFloat(),
                bounds.bottom.toFloat(),
                Path.Direction.CW
            )
            cutoutPath?.let { addPath(it) }
        }
    }

    override fun draw(canvas: Canvas) {
        val bounds = this.bounds
        if (bounds.isEmpty) {
            return
        }
        canvas.drawPath(drawPath, paint)
    }

    override fun setAlpha(alpha: Int) {
        this.alpha = alpha
        paint.color = getPaintColor()
        invalidateSelf()
    }

    override fun getAlpha(): Int = alpha

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
        invalidateSelf()
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
