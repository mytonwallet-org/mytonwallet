package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.widget.FrameLayout

class WFadedEdgeView(context: Context) : FrameLayout(context) {
    var topEdge = 0.3f

    private val fadePaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private val fadeShader: LinearGradient
        get() = LinearGradient(
            0f, 0f, 0f, height.toFloat(),
            intArrayOf(Color.TRANSPARENT, Color.BLACK, Color.BLACK),
            floatArrayOf(0f, topEdge, 1f),
            Shader.TileMode.CLAMP
        )

    override fun dispatchDraw(canvas: Canvas) {
        val saveCount = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)

        super.dispatchDraw(canvas)

        fadePaint.shader = fadeShader
        fadePaint.xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), fadePaint)

        fadePaint.xfermode = null
        canvas.restoreToCount(saveCount)
    }
}
