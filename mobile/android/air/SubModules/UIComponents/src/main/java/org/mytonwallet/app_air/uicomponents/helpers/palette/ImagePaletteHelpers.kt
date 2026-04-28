package org.mytonwallet.app_air.uicomponents.helpers.palette

import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import com.facebook.common.references.CloseableReference
import com.facebook.datasource.DataSource
import com.facebook.datasource.DataSources
import com.facebook.drawee.backends.pipeline.Fresco
import com.facebook.imagepipeline.image.CloseableBitmap
import com.facebook.imagepipeline.image.CloseableImage
import com.facebook.imagepipeline.request.ImageRequestBuilder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.mytonwallet.app_air.walletbasecontext.theme.NftAccentColors
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import kotlin.math.pow
import kotlin.math.sqrt

class ImagePaletteHelpers {
    companion object {
        private fun getBitmapFromUri(imageUrl: String): Bitmap? {
            val imageRequest = ImageRequestBuilder.newBuilderWithSource(Uri.parse(imageUrl)).build()
            val dataSource: DataSource<CloseableReference<CloseableImage>> =
                Fresco.getImagePipeline().fetchDecodedImage(imageRequest, null)

            return try {
                val result: CloseableReference<CloseableImage>? =
                    DataSources.waitForFinalResult(dataSource)

                val bitmap = result?.get()?.let { image ->
                    if (image is CloseableBitmap) image.underlyingBitmap else null
                }

                CloseableReference.closeSafely(result)
                dataSource.close()

                bitmap
            } catch (_: Exception) {
                null
            } finally {
                dataSource.close()
            }
        }

        private fun findClosestColorIndex(color: Int): Int {
            val target = rgbToLab(Color.red(color), Color.green(color), Color.blue(color))

            return NftAccentColors.light.mapIndexed { index, hex ->
                if (index in EXCLUDED_DETECT_INDICES) {
                    index to Double.MAX_VALUE
                } else {
                    val rgb = Color.parseColor(hex)
                    val candidate =
                        rgbToLab(Color.red(rgb), Color.green(rgb), Color.blue(rgb))
                    val distance = sqrt(
                        (target[0] - candidate[0]).pow(2) +
                            (target[1] - candidate[1]).pow(2) +
                            (target[2] - candidate[2]).pow(2)
                    )
                    index to distance
                }
            }.minByOrNull { it.second }!!.first
        }

        private fun rgbToLab(r: Int, g: Int, b: Int): DoubleArray {
            fun toLinear(value: Double): Double =
                if (value > 0.04045) ((value + 0.055) / 1.055).pow(2.4) else value / 12.92

            val rl = toLinear(r / 255.0)
            val gl = toLinear(g / 255.0)
            val bl = toLinear(b / 255.0)

            var x = rl * 0.4124 + gl * 0.3576 + bl * 0.1805
            var y = rl * 0.2126 + gl * 0.7152 + bl * 0.0722
            var z = rl * 0.0193 + gl * 0.1192 + bl * 0.9505

            fun fxyz(value: Double): Double =
                if (value > 0.008856) value.pow(1.0 / 3.0) else (7.787 * value) + 16.0 / 116.0

            x = fxyz(x / 0.95047)
            y = fxyz(y)
            z = fxyz(z / 1.08883)

            return doubleArrayOf(116.0 * y - 16.0, 500.0 * (x - y), 200.0 * (y - z))
        }

        private val EXCLUDED_DETECT_INDICES = setOf(
            NftAccentColors.ACCENT_RADIOACTIVE_INDEX,
            NftAccentColors.ACCENT_SILVER_INDEX,
            NftAccentColors.ACCENT_GOLD_INDEX,
            NftAccentColors.ACCENT_BNW_INDEX,
        )

        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        private fun extractPaletteFromImage(imageUrl: String, onPaletteExtracted: (Int?) -> Unit) {
            scope.launch {
                val closestColorIndex = runCatching {
                    val bitmap = getBitmapFromUri(imageUrl) ?: return@runCatching null
                    val dominantColor =
                        BitmapPaletteExtractHelpers.extractAccentColorIndex(bitmap)
                    findClosestColorIndex(dominantColor)
                }.getOrNull()

                withContext(Dispatchers.Main) {
                    onPaletteExtracted(closestColorIndex)
                }
            }
        }

        fun extractPaletteFromNft(nft: ApiNft, onPaletteExtracted: (Int?) -> Unit) {
            if (nft.metadata?.mtwCardBorderShineType == ApiMtwCardBorderShineType.RADIOACTIVE)
                return onPaletteExtracted(NftAccentColors.ACCENT_RADIOACTIVE_INDEX)
            when (nft.metadata?.mtwCardType) {
                ApiMtwCardType.SILVER -> {
                    onPaletteExtracted(NftAccentColors.ACCENT_SILVER_INDEX)
                }

                ApiMtwCardType.GOLD -> {
                    onPaletteExtracted(NftAccentColors.ACCENT_GOLD_INDEX)
                }

                ApiMtwCardType.PLATINUM, ApiMtwCardType.BLACK -> {
                    onPaletteExtracted(NftAccentColors.ACCENT_BNW_INDEX)
                }

                else -> {
                    extractPaletteFromImage(
                        nft.metadata?.cardImageUrl(false) ?: "",
                        onPaletteExtracted
                    )
                }
            }
        }
    }
}
