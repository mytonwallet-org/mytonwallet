package org.mytonwallet.app_air.widgets.utils

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.util.TypedValue
import androidx.core.graphics.createBitmap

object TextUtils {
    data class DrawableText(
        val text: String,
        val size: Int,
        val color: Int,
        val typeface: Typeface
    )

    fun textToBitmap(
        context: Context,
        drawableText: DrawableText,
    ): Bitmap? {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = drawableText.color
            textSize = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                drawableText.size.toFloat(),
                context.resources.displayMetrics
            )
            typeface = drawableText.typeface
            isSubpixelText = true
            isDither = true
            isLinearText = true
            hinting = Paint.HINTING_ON
        }

        val bounds = Rect()
        paint.getTextBounds(drawableText.text, 0, drawableText.text.length, bounds)

        val width = bounds.width()
        val height = bounds.height()
        val bitmap = createBitmap(width.coerceAtLeast(1), height.coerceAtLeast(1))

        val canvas = Canvas(bitmap)

        canvas.drawText(drawableText.text, -bounds.left.toFloat(), -bounds.top.toFloat(), paint)

        return bitmap
    }
}
