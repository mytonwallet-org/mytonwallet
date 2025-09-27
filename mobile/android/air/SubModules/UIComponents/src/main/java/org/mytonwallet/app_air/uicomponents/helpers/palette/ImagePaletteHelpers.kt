package org.mytonwallet.app_air.uicomponents.helpers.palette

import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.facebook.common.references.CloseableReference
import com.facebook.datasource.DataSource
import com.facebook.datasource.DataSources
import com.facebook.drawee.backends.pipeline.Fresco
import com.facebook.imagepipeline.image.CloseableBitmap
import com.facebook.imagepipeline.image.CloseableImage
import com.facebook.imagepipeline.request.ImageRequestBuilder
import org.mytonwallet.app_air.walletbasecontext.theme.NftAccentColors
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import java.util.concurrent.Executors
import kotlin.math.sqrt

class ImagePaletteHelpers {
    companion object {
        private fun getBitmapFromUri(imageUrl: String): Bitmap? {
            val imageRequest = ImageRequestBuilder.newBuilderWithSource(Uri.parse(imageUrl)).build()
            val dataSource: DataSource<CloseableReference<CloseableImage>> =
                Fresco.getImagePipeline().fetchDecodedImage(imageRequest, null)

            val result: CloseableReference<CloseableImage>? =
                DataSources.waitForFinalResult(dataSource)

            val bitmap = result?.get()?.let { image ->
                if (image is CloseableBitmap) image.underlyingBitmap else null
            }

            CloseableReference.closeSafely(result)
            dataSource.close()

            return bitmap
        }

        private fun findClosestColorIndex(color: Int): Int {
            val r1 = Color.red(color)
            val g1 = Color.green(color)
            val b1 = Color.blue(color)

            return NftAccentColors.light.mapIndexed { index, hex ->
                val rgb = Color.parseColor(hex)
                val r2 = Color.red(rgb)
                val g2 = Color.green(rgb)
                val b2 = Color.blue(rgb)
                val distance = sqrt(
                    ((r1 - r2) * (r1 - r2) + (g1 - g2) * (g1 - g2) + (b1 - b2) * (b1 - b2)).toDouble()
                )
                index to distance
            }.minByOrNull { it.second }!!.first
        }

        private fun extractPaletteFromImage(imageUrl: String, onPaletteExtracted: (Int?) -> Unit) {
            Executors.newSingleThreadExecutor().execute {
                val bitmap = getBitmapFromUri(imageUrl)
                bitmap?.let {
                    val dominantColor = BitmapPaletteExtractHelpers.extractAccentColorIndex(bitmap)
                    val closestColorIndex = findClosestColorIndex(dominantColor)
                    Handler(Looper.getMainLooper()).post {
                        onPaletteExtracted(closestColorIndex)
                    }
                } ?: onPaletteExtracted(null)
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
                    extractPaletteFromImage(nft.metadata?.cardImageUrl ?: "", onPaletteExtracted)
                }
            }
        }
    }
}
