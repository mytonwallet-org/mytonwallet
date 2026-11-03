package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Shader
import android.view.View
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView

/** The News avatar: the Agent's mark gradient with a white pulse line */
internal class AgentNewsIconView(context: Context) :
    View(context),
    WThemedView {
    private val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val pulsePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        color = Color.WHITE
    }
    private val pulse = Path().apply {
        moveTo(6f, 17f)
        lineTo(10f, 17f)
        lineTo(12.5f, 10f)
        lineTo(17f, 23f)
        lineTo(20.5f, 13.5f)
        lineTo(22.5f, 17f)
        lineTo(26f, 17f)
    }

    init {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val size = minOf(w, h).toFloat()
        circlePaint.shader = RadialGradient(
            (w - size) / 2 + size * 0.045455f,
            (h - size) / 2 + size * 0.762425f,
            size * 1.04975f,
            intArrayOf(Color.rgb(0, 190, 255), Color.rgb(182, 86, 255)),
            null,
            Shader.TileMode.CLAMP
        )
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val size = minOf(width, height).toFloat()
        val left = (width - size) / 2
        val top = (height - size) / 2
        val radius = size * Content.STOCK_TOKEN_CORNER_RADIUS_RATIO
        canvas.drawRoundRect(left, top, left + size, top + size, radius, radius, circlePaint)
        canvas.save()
        canvas.translate((width - size) / 2, (height - size) / 2)
        canvas.scale(size / PULSE_BOX, size / PULSE_BOX)
        canvas.scale(1.1f, 1.3f, PULSE_BOX / 2, PULSE_BOX / 2)
        pulsePaint.strokeWidth = PULSE_STROKE
        canvas.drawPath(pulse, pulsePaint)
        canvas.restore()
    }

    override fun updateTheme() = invalidate()

    private companion object {
        const val PULSE_BOX = 32f
        const val PULSE_STROKE = 2.2f
    }
}
