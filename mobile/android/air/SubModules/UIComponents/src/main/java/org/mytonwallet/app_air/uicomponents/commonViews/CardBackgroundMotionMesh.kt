package org.mytonwallet.app_air.uicomponents.commonViews

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import kotlin.math.PI
import kotlin.math.sin

/** Backward-compatible artwork animation for Android 12 and below or software canvases */
internal class CardBackgroundMotionMesh(private val image: Bitmap, private val phase: Float) {
    private val meshWidth = 12
    private val meshHeight = 7
    private val vertices = FloatArray((meshWidth + 1) * (meshHeight + 1) * 2)
    private val rowEnvelope = FloatArray(meshHeight + 1) { sin(PI * it / meshHeight).toFloat() }
    private val columnEnvelope = FloatArray(meshWidth + 1) { sin(PI * it / meshWidth).toFloat() }
    private val rowWave = FloatArray(meshHeight + 1)
    private val columnWave = FloatArray(meshWidth + 1)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    fun draw(canvas: Canvas, time: Double, strength: Float) {
        for (row in 0..meshHeight) {
            val v = row.toFloat() / meshHeight
            rowWave[row] = (sin(time * 0.7 + v * 5 + phase) - sin(v * 5 + phase)).toFloat()
        }
        for (column in 0..meshWidth) {
            val u = column.toFloat() / meshWidth
            columnWave[column] =
                (sin(time * 0.53 + u * 4 + phase) - sin(u * 4 + phase)).toFloat()
        }
        val amount = 15f * image.width / 400f * strength
        var index = 0
        for (row in 0..meshHeight) {
            for (column in 0..meshWidth) {
                val u = column.toFloat() / meshWidth
                val v = row.toFloat() / meshHeight
                val envelope = columnEnvelope[column] * rowEnvelope[row]
                vertices[index++] = u * image.width - rowWave[row] * envelope * amount
                vertices[index++] = v * image.height - columnWave[column] * envelope * amount
            }
        }
        canvas.drawBitmapMesh(image, meshWidth, meshHeight, vertices, 0, null, 0, paint)
    }
}
