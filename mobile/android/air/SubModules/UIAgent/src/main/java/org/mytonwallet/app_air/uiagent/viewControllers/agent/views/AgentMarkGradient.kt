package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.content.Context
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.view.View
import kotlin.math.sqrt

/** The Agent's round mark gradient: radial, from cyan at (0.3, 0.3) of the circle's box to purple at (1.1, 1.1) */
internal fun createAgentMarkGradient(left: Float, top: Float, size: Float): Shader = RadialGradient(
    left + MARK_GRADIENT_CENTER * size,
    top + MARK_GRADIENT_CENTER * size,
    (MARK_GRADIENT_END - MARK_GRADIENT_CENTER) * sqrt(2f) * size,
    0xFF00BEFF.toInt(),
    0xFFB656FF.toInt(),
    Shader.TileMode.CLAMP
)

private const val MARK_GRADIENT_CENTER = 0.3f
private const val MARK_GRADIENT_END = 1.1f

/** Telegram's unread mark in the Agent's mark gradient */
internal class AgentUnreadDotView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

    init {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val size = minOf(w, h).toFloat()
        paint.shader = createAgentMarkGradient((w - size) / 2, (h - size) / 2, size)
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawCircle(width / 2f, height / 2f, minOf(width, height) / 2f, paint)
    }
}

internal class AgentUnreadBadgeDrawable : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        rect.set(bounds)
        paint.shader = createAgentMarkGradient(
            bounds.left.toFloat(),
            bounds.top.toFloat(),
            maxOf(bounds.width(), bounds.height()).toFloat()
        )
    }

    override fun draw(canvas: Canvas) {
        val radius = rect.height() / 2f
        canvas.drawRoundRect(rect, radius, radius, paint)
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
        invalidateSelf()
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
        invalidateSelf()
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
