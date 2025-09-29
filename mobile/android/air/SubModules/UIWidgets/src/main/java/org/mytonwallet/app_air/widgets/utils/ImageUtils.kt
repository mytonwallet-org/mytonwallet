package org.mytonwallet.app_air.widgets.utils

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.Shader
import androidx.annotation.DrawableRes
import androidx.core.content.ContextCompat
import androidx.core.graphics.createBitmap
import androidx.core.net.toUri
import com.facebook.common.executors.CallerThreadExecutor
import com.facebook.common.references.CloseableReference
import com.facebook.datasource.DataSource
import com.facebook.datasource.DataSubscriber
import com.facebook.drawee.backends.pipeline.Fresco
import com.facebook.imagepipeline.image.CloseableBitmap
import com.facebook.imagepipeline.image.CloseableImage
import com.facebook.imagepipeline.request.ImageRequestBuilder

object ImageUtils {
    fun getTintedBitmap(
        context: Context,
        @DrawableRes drawableId: Int,
        color: Int
    ): Bitmap? {
        var drawable = ContextCompat.getDrawable(context, drawableId)
        if (drawable == null) return null

        drawable = drawable.mutate()
        drawable.setColorFilter(color, PorterDuff.Mode.SRC_IN)

        val bitmap = createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight)

        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)

        return bitmap
    }

    private fun getCircularBitmap(bitmap: Bitmap): Bitmap {
        val size = bitmap.width.coerceAtMost(bitmap.height)
        val output = createBitmap(size, size)
        val canvas = Canvas(output)

        val paint = Paint().apply {
            isAntiAlias = true
            shader = BitmapShader(bitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
        }

        val radius = size / 2f
        canvas.drawCircle(radius, radius, radius, paint)

        return output
    }

    fun loadBitmapFromUrl(
        context: Context,
        url: String?,
        width: Int = 100,
        height: Int = 100,
        isCircular: Boolean = true,
        onBitmapReady: (Bitmap?) -> Unit
    ) {
        if (url.isNullOrEmpty()) {
            onBitmapReady(null)
            return
        }

        try {
            if (!Fresco.hasBeenInitialized()) {
                Fresco.initialize(context.applicationContext)
            }
        } catch (_: Exception) {
            onBitmapReady(null)
            return
        }

        val imageRequest = ImageRequestBuilder
            .newBuilderWithSource(url.toUri())
            .setResizeOptions(
                com.facebook.imagepipeline.common.ResizeOptions(width, height)
            )
            .build()

        val imagePipeline = Fresco.getImagePipeline()
        val dataSource = imagePipeline.fetchDecodedImage(imageRequest, context)

        dataSource.subscribe(object : DataSubscriber<CloseableReference<CloseableImage>> {
            override fun onNewResult(dataSource: DataSource<CloseableReference<CloseableImage>>) {
                if (!dataSource.isFinished) {
                    return
                }

                val result = dataSource.result
                if (result != null) {
                    try {
                        val closeableImage = result.get()
                        if (closeableImage is CloseableBitmap) {
                            val bitmap = closeableImage.underlyingBitmap
                            if (bitmap != null && !bitmap.isRecycled) {
                                val bitmapCopy = bitmap.copy(bitmap.config!!, false)
                                val finalBitmap = if (isCircular) {
                                    getCircularBitmap(bitmapCopy)
                                } else {
                                    bitmapCopy
                                }
                                onBitmapReady(finalBitmap)
                            } else {
                                onBitmapReady(null)
                            }
                        } else {
                            onBitmapReady(null)
                        }
                    } finally {
                        result.close()
                    }
                } else {
                    onBitmapReady(null)
                }
            }

            override fun onFailure(dataSource: DataSource<CloseableReference<CloseableImage>>) {
                onBitmapReady(null)
            }

            override fun onCancellation(dataSource: DataSource<CloseableReference<CloseableImage>>) {
                onBitmapReady(null)
            }

            override fun onProgressUpdate(dataSource: DataSource<CloseableReference<CloseableImage>>) {
            }
        }, CallerThreadExecutor.getInstance())
    }

}
