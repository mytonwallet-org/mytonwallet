package org.mytonwallet.app_air.uicomponents.drawable

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Paint.Style
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.os.SystemClock
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import kotlin.math.min

class RoundProgressDrawable(
    private val sizeDp: Int = 16,
    strokeWidthDp: Float = 3f
) : Drawable() {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Style.STROKE
        strokeWidth = strokeWidthDp.dp
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }

    override fun getMinimumWidth(): Int {
        return sizeDp.dp
    }

    override fun getMinimumHeight(): Int {
        return sizeDp.dp
    }

    private var angle = 0f
    private var angle2 = 60f
    private var dir = 1
    private var lastFrameTime = 0L

    override fun draw(canvas: Canvas) {
        val t = SystemClock.uptimeMillis()
        val dt = min(t - lastFrameTime, 100)

        angle += (dt / AnimationConstants.SLOW_ANIMATION.toFloat() * 360f) % 360f
        angle2 += (dt / AnimationConstants.SLOW_ANIMATION.toFloat() * 180f * dir)
        if (angle2 >= 300) {
            angle2 = 300f
            dir = -1
        } else if (angle2 <= 60) {
            angle2 = 60f
            dir = 1
        }

        canvas.drawArc(left, top, right, bottom, angle, angle2, false, paint)
        invalidateSelf()

        lastFrameTime = t
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
    }

    override fun getAlpha(): Int {
        return paint.alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {

    }

    var color = 0
        set(value) {
            field = value
            paint.color = value
        }

    var strokeWidth = 0f
        set(value) {
            field = value
            paint.strokeWidth = value
        }


    private var left = 0f
    private var top = 0f
    private var right = 0f
    private var bottom = 0f

    private var cx = 0f
    private var cy = 0f
    private var r = 0f

    override fun setBounds(left: Int, top: Int, right: Int, bottom: Int) {
        super.setBounds(left, top, right, bottom)
        this.left = left.toFloat()
        this.top = top.toFloat()
        this.right = right.toFloat()
        this.bottom = bottom.toFloat()

        cx = (left + right) / 2f
        cy = (top + bottom) / 2f
        r = min(right - left, bottom - top) / 2f - strokeWidth - 1
    }

    override fun getOpacity(): Int {
        return PixelFormat.UNKNOWN
    }
}
