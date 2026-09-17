package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Drawable
import org.mytonwallet.app_air.uicomponents.commonViews.AccountAvatarRenderer
import org.mytonwallet.app_air.uicomponents.commonViews.generateAbbreviation
import org.mytonwallet.app_air.walletbasecontext.utils.gradientColors

class AccountAvatarDrawable(name: String?, address: String) : Drawable() {

    private val abbreviation = generateAbbreviation(name, address)
    private val colors = address.gradientColors
    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }
    private val textPaint = AccountAvatarRenderer.createTextPaint(0f)
    private val ovalRect = RectF()

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        ovalRect.set(bounds)
        backgroundPaint.shader = LinearGradient(
            0f,
            bounds.top.toFloat(),
            0f,
            bounds.bottom.toFloat(),
            colors,
            null,
            Shader.TileMode.CLAMP
        )
        textPaint.textSize = bounds.height() * 0.45f
    }

    override fun draw(canvas: Canvas) {
        if (ovalRect.isEmpty) return
        canvas.drawOval(ovalRect, backgroundPaint)
        AccountAvatarRenderer.drawCenteredText(
            canvas,
            abbreviation,
            ovalRect.centerX(),
            ovalRect.centerY(),
            textPaint
        )
    }

    override fun setAlpha(alpha: Int) {
        backgroundPaint.alpha = alpha
        textPaint.alpha = alpha
        invalidateSelf()
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        backgroundPaint.colorFilter = colorFilter
        textPaint.colorFilter = colorFilter
        invalidateSelf()
    }

    @Deprecated("Deprecated in Java", ReplaceWith("PixelFormat.TRANSLUCENT"))
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
