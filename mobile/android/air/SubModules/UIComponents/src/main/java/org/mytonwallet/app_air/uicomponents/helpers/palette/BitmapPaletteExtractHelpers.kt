package org.mytonwallet.app_air.uicomponents.helpers.palette

import android.graphics.Bitmap
import android.graphics.Color

class BitmapPaletteExtractHelpers {
    companion object {

        private fun quantize(pixelArray: List<IntArray>, colorCount: Int): MMCQ.CMap? =
            MMCQ.quantize(pixelArray, colorCount)

        fun extractAccentColorIndex(bitmap: Bitmap): Int {
            return try {
                val palette = extractPaletteFromBitmap(bitmap)?.get(0) ?: return Color.BLACK
                return Color.rgb(palette[0], palette[1], palette[2])
            } catch (_: Exception) {
                Color.BLACK
            }
        }

        // Average color of the bottom band of the image, used to blend the image into the
        // screen background. Returns null when the band is mostly transparent.
        fun extractAverageColor(bitmap: Bitmap): Int? {
            return try {
                val bandTop = bitmap.height * 3 / 4
                val bandHeight = bitmap.height - bandTop
                if (bandHeight <= 0 || bitmap.width <= 0) return null
                val pixels = IntArray(bitmap.width * bandHeight)
                bitmap.getPixels(pixels, 0, bitmap.width, 0, bandTop, bitmap.width, bandHeight)
                val step = (pixels.size / 10_000).coerceAtLeast(1)
                var r = 0L
                var g = 0L
                var b = 0L
                var opaqueCount = 0
                var sampledCount = 0
                var i = 0
                while (i < pixels.size) {
                    val pixel = pixels[i]
                    sampledCount++
                    if (Color.alpha(pixel) >= 120) {
                        r += Color.red(pixel)
                        g += Color.green(pixel)
                        b += Color.blue(pixel)
                        opaqueCount++
                    }
                    i += step
                }
                if (opaqueCount == 0 || opaqueCount < sampledCount / 20) return null
                Color.rgb(
                    (r / opaqueCount).toInt(),
                    (g / opaqueCount).toInt(),
                    (b / opaqueCount).toInt()
                )
            } catch (_: Exception) {
                null
            }
        }

        // Extract palette from bitmap
        private fun extractPaletteFromBitmap(bitmap: Bitmap): List<IntArray>? {
            val imageData = extractImageData(bitmap)
            val pixelCount = bitmap.width * bitmap.height
            val quality = 10
            val pixelArray = createPixelArray(imageData, pixelCount, quality)
            val colorCount = 5

            val cmap = quantize(pixelArray, colorCount) ?: return null
            return cmap.palette()
        }

        // Extract raw pixel data from bitmap
        private fun extractImageData(bitmap: Bitmap): IntArray {
            val pixelCount = bitmap.width * bitmap.height
            val pixels = IntArray(pixelCount)
            bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
            return pixels
        }

        // Create a pixel array suitable for the quantize algorithm
        private fun createPixelArray(
            pixels: IntArray,
            pixelCount: Int,
            quality: Int
        ): List<IntArray> {
            val pixelArray = mutableListOf<IntArray>()

            var i = 0
            while (i < pixelCount) {
                val pixel = pixels[i]
                val r = Color.red(pixel)
                val g = Color.green(pixel)
                val b = Color.blue(pixel)
                val a = Color.alpha(pixel)

                // If pixel is mostly opaque and not white
                if (a >= 125) {
                    if (!(r > 250 && g > 250 && b > 250)) {
                        pixelArray.add(intArrayOf(r, g, b))
                    }
                }

                i += quality
            }

            return pixelArray
        }
    }
}
