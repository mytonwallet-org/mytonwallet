package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.drawable.Drawable
import org.mytonwallet.app_air.uicomponents.commonViews.AccountAvatarRenderer
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class InitialsDrawable(
    private val text: String,
    private val rounding: Content.Rounding = Content.Rounding.Round
) : Drawable() {

    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = WFont.Balance.typeface
        textAlign = Paint.Align.CENTER
        color = WColor.SecondaryText.color
    }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = (WColor.SecondaryText.color and 0x00FFFFFF) or (BORDER_ALPHA shl 24)
    }
    private val borderRect = RectF()

    override fun draw(canvas: Canvas) {
        if (text.isEmpty()) return
        val b = bounds
        val size = minOf(b.width(), b.height()).toFloat()
        if (size <= 0f) return

        borderPaint.strokeWidth = maxOf(1f, size * 0.025f)
        textPaint.textSize = maxOf(10f, size * 0.45f)

        val inset = borderPaint.strokeWidth / 2f
        borderRect.set(b.left + inset, b.top + inset, b.right - inset, b.bottom - inset)
        when (rounding) {
            is Content.Rounding.Radius ->
                canvas.drawRoundRect(borderRect, rounding.radius, rounding.radius, borderPaint)

            is Content.Rounding.RadiusRatio -> {
                val radius = size * rounding.ratio
                canvas.drawRoundRect(borderRect, radius, radius, borderPaint)
            }

            else -> canvas.drawOval(borderRect, borderPaint)
        }

        AccountAvatarRenderer.drawCenteredText(
            canvas,
            text,
            b.exactCenterX(),
            b.exactCenterY(),
            textPaint
        )
    }

    override fun setAlpha(alpha: Int) {
        textPaint.alpha = alpha
        borderPaint.alpha = BORDER_ALPHA * alpha / 255
        invalidateSelf()
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        textPaint.colorFilter = colorFilter
        borderPaint.colorFilter = colorFilter
        invalidateSelf()
    }

    @Deprecated("Deprecated in Java", ReplaceWith("PixelFormat.TRANSLUCENT"))
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT

    private companion object {
        const val BORDER_ALPHA = 0x80
    }
}