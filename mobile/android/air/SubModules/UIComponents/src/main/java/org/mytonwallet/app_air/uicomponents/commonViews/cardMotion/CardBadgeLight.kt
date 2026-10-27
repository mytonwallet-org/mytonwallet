package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt

/** Background-only sheen; the native blur and foreground glyphs retain their own layers. */
internal class CardBadgeLight {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var x: Float? = null
    private var y: Float? = null
    private var lastWidth = 0
    private var lastHeight = 0
    private var dirty = true
    private val colors = IntArray(13) { index ->
        val v = cos(PI * index / 12)
        val alpha = (255 * abs(v) * if (v >= 0) .041 else .04).roundToInt()
        if (v >= 0) Color.argb(alpha, 255, 255, 255) else Color.argb(alpha, 0, 0, 0)
    }
    fun setTilt(nextX: Float?, nextY: Float?): Boolean {
        if (x == nextX && y == nextY) return false
        x = nextX
        y = nextY
        dirty = true
        return true
    }
    fun draw(canvas: Canvas, width: Int, height: Int) {
        val lx = x ?: return
        val ly = y ?: return
        if (width <= 0 || height <= 0) return
        if (dirty || width != lastWidth || height != lastHeight) {
            val dx = .65f * lx
            val dy = 1 + .65f * ly
            val extent = .65f * (abs(dx) * width + dy * height) / (dx * dx + dy * dy)
            paint.shader = LinearGradient(
                width / 2f - dx * extent,
                height / 2f - dy * extent,
                width / 2f + dx * extent,
                height / 2f + dy * extent,
                colors,
                null,
                Shader.TileMode.CLAMP
            )
            lastWidth = width
            lastHeight = height
            dirty = false
        }
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
    }
}
