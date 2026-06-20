package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Shader
import android.graphics.drawable.Drawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import kotlin.math.min

class TabletEdgeFadeDrawable(
    private val baseColor: Int = Color.BLACK,
    private val dimWhenWide: Boolean = true,
) : Drawable() {

    private val fadeWidthPx = (ViewConstants.TABLET_PANELS_OVERLAP_WIDTH * 2).dp

    private val isWide: Boolean
        get() = ViewConstants.ADDITIONAL_TABLET_PADDING > 0

    private val color: Int
        get() = if (isWide && dimWhenWide) (baseColor and 0x00FFFFFF) or 0x80000000.toInt() else baseColor

    private val paint = Paint()
    private var gradient: LinearGradient? = null
    private var gradientWide = false

    private fun rebuildGradient(bounds: Rect) {
        gradientWide = isWide
        val color = color
        if (!isWide) {
            gradient = null
            paint.shader = null
            paint.color = color
            return
        }
        val fadeWidth = min(fadeWidthPx, bounds.width().toFloat())
        if (fadeWidth <= 0f) {
            gradient = null
            paint.shader = null
            paint.color = color
            return
        }
        val transparent = color and 0x00FFFFFF
        val fadeFraction = fadeWidth / bounds.width().toFloat()
        gradient = if (LocaleController.isRTL) {
            LinearGradient(
                bounds.left.toFloat(), 0f, bounds.right.toFloat(), 0f,
                intArrayOf(color, color, transparent),
                floatArrayOf(0f, 1f - fadeFraction, 1f),
                Shader.TileMode.CLAMP
            )
        } else {
            LinearGradient(
                bounds.left.toFloat(), 0f, bounds.right.toFloat(), 0f,
                intArrayOf(transparent, color, color),
                floatArrayOf(0f, fadeFraction, 1f),
                Shader.TileMode.CLAMP
            )
        }
        paint.shader = gradient
    }

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        rebuildGradient(bounds)
    }

    override fun draw(canvas: Canvas) {
        val bounds = bounds
        if (bounds.isEmpty) return

        if (gradientWide != isWide) rebuildGradient(bounds)

        canvas.drawRect(bounds, paint)
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
        invalidateSelf()
    }

    override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) {
        paint.colorFilter = colorFilter
        invalidateSelf()
    }

    @Deprecated("Deprecated in Java", ReplaceWith("PixelFormat.TRANSLUCENT"))
    override fun getOpacity() = PixelFormat.TRANSLUCENT
}
