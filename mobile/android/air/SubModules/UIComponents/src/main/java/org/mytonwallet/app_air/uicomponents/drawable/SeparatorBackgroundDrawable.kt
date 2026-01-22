package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Paint.Style
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.drawable.Drawable
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class SeparatorBackgroundDrawable : Drawable() {
    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Style.FILL
    }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Style.STROKE
        strokeWidth = 1f
    }

    var isTop = false
    var separatorColor = WColor.Separator
    var separatorWColor: WColor? = WColor.Separator
    var backgroundColor: Int? = null
    var backgroundWColor: WColor? = null

    // Force separator even in Common ui-mode and dark theme
    var forceSeparator: Boolean = false

    var allowSeparator: Boolean = false
    var offsetStart = 0f
    var offsetEnd = 0f
    var topRadius = 0f
    var bottomRadius = 0f

    override fun draw(canvas: Canvas) {
        (backgroundWColor?.color ?: backgroundColor)?.let {
            backgroundPaint.color = it

            if (topRadius > 0f || bottomRadius > 0) {
                val rectF = RectF(left.toFloat(), top.toFloat(), right.toFloat(), bottom.toFloat())
                val radii = floatArrayOf(
                    topRadius, topRadius,
                    topRadius, topRadius,
                    bottomRadius, bottomRadius,
                    bottomRadius, bottomRadius
                )
                val path = Path().apply { addRoundRect(rectF, radii, Path.Direction.CW) }
                canvas.drawPath(path, backgroundPaint)
            } else {
                canvas.drawRect(
                    left.toFloat(),
                    top.toFloat(),
                    right.toFloat(),
                    bottom.toFloat(),
                    backgroundPaint
                )
            }
        }

        if (forceSeparator || (!ThemeManager.isDark && allowSeparator)) {
            val y = (if (isTop) top + 0.5f else bottom - 0.5f)

            paint.color = separatorWColor?.color ?: separatorColor.color
            canvas.drawLine(left + offsetStart, y, right - offsetEnd, y, paint)
        }
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {

    }

    override fun getOpacity(): Int {
        return PixelFormat.TRANSPARENT
    }


    private var left: Int = 0
    private var top: Int = 0
    private var right: Int = 0
    private var bottom: Int = 0

    override fun setBounds(left: Int, top: Int, right: Int, bottom: Int) {
        super.setBounds(left, top, right, bottom)
        this.left = left
        this.top = top
        this.right = right
        this.bottom = bottom
    }
}
