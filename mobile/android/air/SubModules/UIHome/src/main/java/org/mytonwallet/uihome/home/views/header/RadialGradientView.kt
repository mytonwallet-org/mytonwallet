package org.mytonwallet.uihome.home.views.header

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp

class RadialGradientView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    companion object {
        private val GRADIENT_COLORS_LIGHT_TEXT = intArrayOf(
            Color.argb(128, 0, 0, 0),
            Color.argb(0, 0, 0, 0)
        )

        private val GRADIENT_COLORS_DARK_TEXT = intArrayOf(
            Color.argb(191, 255, 255, 255),
            Color.argb(0, 255, 255, 255)
        )
    }

    init {
        id = generateViewId()
    }

    private val radialPaint = Paint().apply {
        alpha = 40
        isAntiAlias = true
    }

    private val overlayPaint = Paint().apply {
        isAntiAlias = true
        xfermode = PorterDuffXfermode(PorterDuff.Mode.OVERLAY)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)

        update()
    }

    var isTextLight = true
        set(value) {
            field = value
            update()
        }

    private val path = Path()
    var cornerRadius: Float = 0f
        set(value) {
            field = value
            update()
        }

    private fun update() {
        val gradientWidth = width.coerceAtMost(204.dp)
        val gradientHeight = height
        if (gradientWidth == 0 || gradientHeight == 0) return

        val colors =
            if (isTextLight) GRADIENT_COLORS_LIGHT_TEXT else GRADIENT_COLORS_DARK_TEXT

        radialPaint.shader = RadialGradient(
            0.5f * gradientWidth,
            0.5f * height,
            1.61f * gradientWidth,
            colors,
            floatArrayOf(0.35f, 1.0f),
            Shader.TileMode.CLAMP
        )

        overlayPaint.shader = RadialGradient(
            0.5f * gradientWidth,
            0.5f * gradientHeight,
            1.61f * gradientWidth,
            colors,
            floatArrayOf(0.35f, 1.0f),
            Shader.TileMode.CLAMP
        )

        path.reset()
        path.addRoundRect(
            0f, 0f, width.toFloat(), height.toFloat(),
            cornerRadius, cornerRadius,
            Path.Direction.CW
        )
        path.close()
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        canvas.clipPath(path)
        canvas.drawPaint(radialPaint)
        canvas.drawPaint(overlayPaint)
        canvas.restore()
    }
}
