package org.mytonwallet.app_air.uicomponents.drawable

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.view.Gravity
import org.mytonwallet.app_air.uicomponents.extensions.dp

class RecyclerViewGradientDrawable(
    private val context: Context,
    private val gravity: Int
) : Drawable() {
    companion object {
        private const val HEIGHT = 25
    }

    private val paintColor: Paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val paint: Paint = Paint(Paint.ANTI_ALIAS_FLAG)

    var offset = 0
    var color = Color.GREEN
        set(value) {
            if (field != value) {
                field = value
                updatePaint()
            }
        }

    private fun updatePaint() {
        val colors = if (gravity == Gravity.TOP) {
            intArrayOf(color, color and 0x00FFFFFF)
        } else {
            intArrayOf(color and 0x00FFFFFF, color)
        }

        paintColor.color = color
        paint.setShader(
            LinearGradient(
                0f, 0f, 0f, HEIGHT.dp.toFloat(),
                colors, null, Shader.TileMode.CLAMP
            )
        )
    }

    override fun draw(canvas: Canvas) {
        val width = right.toFloat() - left.toFloat()
        val height = bottom.toFloat() - top.toFloat()

        val gradientHeight = HEIGHT.dp.toFloat()
        val offsetHeight = offset.toFloat()

        canvas.save()
        canvas.translate(left.toFloat(), top.toFloat())

        if (gravity == Gravity.TOP) {
            canvas.drawRect(0f, 0f, width, offsetHeight, paintColor)
            canvas.translate(0f, offsetHeight)
        } else {
            canvas.drawRect(0f, height - offsetHeight, width, height, paintColor)
            canvas.translate(0f, height - gradientHeight - offsetHeight)
        }

        canvas.drawRect(0f, 0f, width, gradientHeight, paint)
        canvas.restore()
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
