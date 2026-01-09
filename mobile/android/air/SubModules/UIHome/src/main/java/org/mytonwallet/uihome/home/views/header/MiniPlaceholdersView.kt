package org.mytonwallet.uihome.home.views.header

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp

class MiniPlaceholdersView(context: Context) : View(context) {

    init {
        id = generateViewId()
    }

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }

    private val line1Width = 16f.dp
    private val line1Height = 2.5f.dp

    private val line2Width = 5f.dp
    private val line2Height = 1.5f.dp

    private val line3Width = 8f.dp
    private val line3Height = 1.5f.dp

    private val topPadding = 6f.dp
    private val space12 = 2f.dp
    private val space23 = 4f.dp

    fun setColor(color: Int) {
        paint.color = color
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val height =
            topPadding +
            line1Height +
            space12 +
            line2Height +
            space23 +
            line3Height

        val width = 36.dp

        setMeasuredDimension(
            resolveSize(width, widthMeasureSpec),
            resolveSize(height.toInt(), heightMeasureSpec)
        )
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val centerX = width / 2f

        var y = topPadding

        // Line 1
        paint.alpha = 255
        canvas.drawRoundRect(
            centerX - line1Width / 2,
            y,
            centerX + line1Width / 2,
            y + line1Height,
            line1Height / 2,
            line1Height / 2,
            paint
        )

        y += line1Height + space12

        // Line 2
        paint.alpha = (255 * 0.6f).toInt()
        canvas.drawRoundRect(
            centerX - line2Width / 2,
            y,
            centerX + line2Width / 2,
            y + line2Height,
            line2Height / 2,
            line2Height / 2,
            paint
        )

        y += line2Height + space23

        // Line 3
        canvas.drawRoundRect(
            centerX - line3Width / 2,
            y,
            centerX + line3Width / 2,
            y + line3Height,
            line3Height / 2,
            line3Height / 2,
            paint
        )
    }
}
