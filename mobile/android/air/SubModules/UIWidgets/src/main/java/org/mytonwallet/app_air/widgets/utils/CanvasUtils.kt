package org.mytonwallet.app_air.widgets.utils

import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import androidx.core.graphics.withSave

fun Canvas.drawOval(ovalRect: RectF, rotation: Float, colors: IntArray, paint: Paint) {
    withSave {
        rotate(rotation, ovalRect.centerX(), ovalRect.centerY())
        paint.shader = LinearGradient(
            0f, 0f, ovalRect.width(), ovalRect.height(),
            colors,
            null,
            Shader.TileMode.CLAMP
        )
        drawOval(ovalRect, paint)
    }
}
