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

class WCutoutDrawable :
    Drawable(),
    Drawable.Callback {
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

    /**
     * Drawn over the dim, in the same coordinates as [cutoutPath], at full strength whatever the dim's alpha: what is
     * lifted with the cutout beyond its path
     */
    var lifted: Drawable? = null
        set(value) {
            field?.callback = null
            field = value
            value?.callback = this
            value?.bounds = bounds
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
        lifted?.bounds = bounds
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
        lifted?.draw(canvas)
    }

    override fun invalidateDrawable(who: Drawable) {
        invalidateSelf()
    }

    override fun scheduleDrawable(who: Drawable, what: Runnable, `when`: Long) {
        scheduleSelf(what, `when`)
    }

    override fun unscheduleDrawable(who: Drawable, what: Runnable) {
        unscheduleSelf(what)
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
