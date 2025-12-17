package org.mytonwallet.app_air.uicomponents.helpers

import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import androidx.core.graphics.toColorInt
import org.mytonwallet.app_air.uicomponents.drawable.TiltGradientDrawable
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.DOWN
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.LEFT
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.RADIOACTIVE
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.RIGHT
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.UP
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType.BLACK
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import kotlin.math.atan2

class NftGradientHelpers(val nft: ApiNft?) {
    val tiltOffset = 0.25f

    fun gradient(
        width: Float,
        tiltX: Float,
        tiltY: Float
    ): LayerDrawable? {
        if (nft?.isMtwCard != true)
            return null
        val radius = width * 0.58f * 1.41f / 2
        return when (nft.metadata?.mtwCardBorderShineType ?: UP) {
            UP -> LayerDrawable(
                arrayOf(
                    createRadialGradient(
                        (0.75f + tiltX * tiltOffset).coerceIn(0f, 1f),
                        (-tiltY).coerceIn(-0.2f, 0.5f),
                        radius
                    ),
                    createLinearGradient(-tiltX, tiltY)
                )
            )

            DOWN -> LayerDrawable(
                arrayOf(
                    createRadialGradient(
                        (0.25f + tiltX * tiltOffset).coerceIn(0f, 1f),
                        (1f - tiltY).coerceIn(0.5f, 1.2f),
                        radius
                    ),
                    createLinearGradient(-tiltX, tiltY)
                )
            )

            LEFT -> LayerDrawable(
                arrayOf(
                    createRadialGradient(
                        (0f + tiltX).coerceIn(-0.2f, 0.5f),
                        (0.25f - tiltY * tiltOffset).coerceIn(0f, 1f),
                        radius
                    ),
                    createLinearGradient(-tiltX, tiltY)
                )
            )

            RIGHT -> LayerDrawable(
                arrayOf(
                    createRadialGradient(
                        (1f + tiltX).coerceIn(0.5f, 1.2f),
                        (0.75f - tiltY * tiltOffset).coerceIn(0f, 1f),
                        radius
                    ),
                    createLinearGradient(-tiltX, tiltY)
                )
            )

            RADIOACTIVE -> {
                LayerDrawable(
                    arrayOf(
                        createLinearGradient(-tiltX, tiltY)
                    )
                )
            }
        }
    }

    private fun createRadialGradient(
        centerX: Float,
        centerY: Float,
        radius: Float
    ): GradientDrawable {
        return GradientDrawable().apply {
            gradientType = GradientDrawable.RADIAL_GRADIENT
            gradientRadius = radius
            setGradientCenter(centerX, centerY)
            colors = intArrayOf(
                Color.WHITE,
                Color.argb(0, 255, 255, 255)
            )
        }
    }

    val gradientColors: IntArray?
        get() {
            if (nft?.metadata?.mtwCardBorderShineType == RADIOACTIVE) {
                val greenColor = "#5CE850".toColorInt()
                return intArrayOf(greenColor, greenColor)
            }
            return when (nft?.metadata?.mtwCardType) {
                ApiMtwCardType.SILVER -> {
                    intArrayOf(
                        Color.rgb(39, 39, 39),
                        Color.rgb(152, 152, 152),
                    )
                }

                ApiMtwCardType.GOLD -> {
                    intArrayOf(
                        Color.rgb(76, 52, 3),
                        Color.rgb(176, 125, 29),
                    )
                }

                ApiMtwCardType.PLATINUM -> {
                    intArrayOf(
                        Color.rgb(119, 119, 127),
                        Color.rgb(255, 255, 255),
                    )
                }

                BLACK -> {
                    if (ThemeManager.isDark) {
                        intArrayOf(
                            Color.argb(15, 255, 255, 255),
                            Color.argb(31, 255, 255, 255),
                        )
                    } else {
                        intArrayOf(
                            Color.argb(31, 255, 255, 255),
                            Color.argb(61, 255, 255, 255),
                        )
                    }
                }

                else -> {
                    null
                }
            }
        }

    private fun createLinearGradient(tiltX: Float, tiltY: Float): Drawable? {
        val angle = Math.toDegrees(atan2(tiltY, tiltX).toDouble()).toFloat()

        return gradientColors?.let {
            TiltGradientDrawable(it).apply {
                this.angle = angle
            }
        }
    }

}
