package org.mytonwallet.app_air.uicomponents.commonViews

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import androidx.core.graphics.createBitmap
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

internal object GramDefaultCardArtwork {
    private const val WIDTH = 400f
    private const val HEIGHT = 232f

    val base: Bitmap by lazy {
        createBitmap(800, 464).also { bitmap ->
            val canvas = Canvas(bitmap)
            canvas.scale(2f, 2f)
            val angle = 145 * PI / 180
            val directionX = sin(angle).toFloat()
            val directionY = -cos(angle).toFloat()
            val halfLength = (abs(directionX) * WIDTH + abs(directionY) * HEIGHT) / 2
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = LinearGradient(
                    WIDTH / 2 - directionX * halfLength,
                    HEIGHT / 2 - directionY * halfLength,
                    WIDTH / 2 + directionX * halfLength,
                    HEIGHT / 2 + directionY * halfLength,
                    intArrayOf(
                        Color.rgb(92, 200, 255),
                        Color.rgb(0, 136, 255),
                        Color.rgb(0, 87, 194)
                    ),
                    floatArrayOf(0f, .46f, 1f),
                    Shader.TileMode.CLAMP
                )
            }
            canvas.drawRect(0f, 0f, WIDTH, HEIGHT, paint)
            drawBrush(canvas)
        }
    }

    private fun drawBrush(canvas: Canvas) {
        val patterns = arrayOf(
            11.7f to arrayOf(Triple(0f, .7f, .32f), Triple(.7f, 1.25f, -.18f)),
            5.2f to
                arrayOf(
                    Triple(0f, .14f, .22f),
                    Triple(.95f, 1.85f, -.14f),
                    Triple(1.85f, 2.7f, .16f)
                ),
            8.3f to
                arrayOf(
                    Triple(0f, .45f, -.18f),
                    Triple(1.15f, 1.95f, .28f),
                    Triple(1.95f, 2.15f, -.12f),
                    Triple(4.2f, 4.38f, .12f)
                ),
            6.1f to
                arrayOf(
                    Triple(0f, .22f, .42f),
                    Triple(.22f, .7f, -.2f),
                    Triple(1.45f, 1.58f, .18f),
                    Triple(2.5f, 3.45f, -.16f)
                )
        )
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
        for ((period, strokes) in patterns) {
            var offset = 0f
            while (offset < hypot(WIDTH, HEIGHT)) {
                for ((start, end, opacity) in strokes) {
                    paint.color = if (opacity > 0) Color.WHITE else Color.BLACK
                    paint.alpha = (abs(opacity) * .15f * 255).toInt()
                    paint.strokeWidth = end - start
                    canvas.drawCircle(WIDTH / 2, HEIGHT / 2, offset + (start + end) / 2, paint)
                }
                offset += period
            }
        }
    }
}
