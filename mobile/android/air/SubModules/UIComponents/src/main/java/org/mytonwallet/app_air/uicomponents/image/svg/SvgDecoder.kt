package org.mytonwallet.app_air.uicomponents.image.svg

import android.graphics.Bitmap
import android.graphics.Canvas
import com.caverock.androidsvg.SVG
import com.facebook.common.references.CloseableReference
import com.facebook.imagepipeline.bitmaps.SimpleBitmapReleaser
import com.facebook.imagepipeline.common.ImageDecodeOptions
import com.facebook.imagepipeline.decoder.ImageDecoder
import com.facebook.imagepipeline.image.CloseableImage
import com.facebook.imagepipeline.image.CloseableStaticBitmap
import com.facebook.imagepipeline.image.EncodedImage
import com.facebook.imagepipeline.image.ImmutableQualityInfo
import com.facebook.imagepipeline.image.QualityInfo

class SvgDecoder : ImageDecoder {

    companion object {
        private const val MAX_SIZE = 512
        private const val DEFAULT_SIZE = 96
    }

    override fun decode(
        encodedImage: EncodedImage,
        length: Int,
        qualityInfo: QualityInfo,
        options: ImageDecodeOptions
    ): CloseableImage? {
        val stream = encodedImage.inputStream ?: return null
        return try {
            val svg = stream.use { SVG.getFromInputStream(it) }
            val (width, height) = renderSize(svg)
            svg.setDocumentWidth(width.toFloat())
            svg.setDocumentHeight(height.toFloat())
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            svg.renderToCanvas(Canvas(bitmap))
            val reference = CloseableReference.of(bitmap, SimpleBitmapReleaser.getInstance())
            try {
                CloseableStaticBitmap.of(reference, ImmutableQualityInfo.FULL_QUALITY, 0)
            } finally {
                reference.close()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun renderSize(svg: SVG): Pair<Int, Int> {
        val intrinsicW = svg.documentWidth
        val intrinsicH = svg.documentHeight
        if (intrinsicW <= 0f || intrinsicH <= 0f) {
            return DEFAULT_SIZE to DEFAULT_SIZE
        }
        val maxDimension = maxOf(intrinsicW, intrinsicH)
        if (maxDimension <= MAX_SIZE) {
            return intrinsicW.toInt().coerceAtLeast(1) to intrinsicH.toInt().coerceAtLeast(1)
        }
        val scale = MAX_SIZE / maxDimension
        return (intrinsicW * scale).toInt().coerceAtLeast(1) to
            (intrinsicH * scale).toInt().coerceAtLeast(1)
    }
}