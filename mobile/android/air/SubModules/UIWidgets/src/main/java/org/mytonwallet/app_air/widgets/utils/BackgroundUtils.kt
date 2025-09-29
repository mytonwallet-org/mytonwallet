package org.mytonwallet.app_air.widgets.utils

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import androidx.core.graphics.createBitmap
import org.mytonwallet.app_air.walletbasecontext.utils.colorChanged
import org.mytonwallet.app_air.walletbasecontext.utils.isBrightColor

object BackgroundUtils {
    fun createCardBackground(
        baseColor: Int,
        width: Int,
        height: Int
    ): Bitmap {
        val isBright = baseColor.isBrightColor()

        val bitmap = createBitmap(width, height)
        val canvas = Canvas(bitmap)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        paint.shader = LinearGradient(
            0f, 0f, width.toFloat(), height.toFloat(),
            intArrayOf(
                baseColor.colorChanged(0.05f, isBright),
                baseColor.colorChanged(0.3f, isBright)
            ),
            null,
            Shader.TileMode.CLAMP
        )
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)

        canvas.drawOval(
            RectF(-width / 2f, -width / 2f, width * 3f, width * 1.3f),
            -60f,
            intArrayOf(
                baseColor.colorChanged(0.05f, isBright),
                baseColor.colorChanged(0.3f, isBright)
            ),
            paint
        )

        canvas.drawOval(
            RectF(-width / 4f, -width / 2f, width * 3.5f, width * 1.3f),
            -55f,
            intArrayOf(
                baseColor.colorChanged(0.03f, isBright),
                baseColor.colorChanged(0.3f, isBright)
            ),
            paint
        )

        return bitmap
    }
}
