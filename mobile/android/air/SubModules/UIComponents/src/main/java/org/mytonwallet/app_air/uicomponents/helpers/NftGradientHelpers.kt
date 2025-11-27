package org.mytonwallet.app_air.uicomponents.helpers

import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import org.mytonwallet.app_air.uicomponents.drawable.ScaledDrawable
import org.mytonwallet.app_air.uicomponents.drawable.TiltGradientDrawable
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.DOWN
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.LEFT
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.RADIOACTIVE
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.RIGHT
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardBorderShineType.UP
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType.BLACK
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import kotlin.math.atan2

class NftGradientHelpers(val nft: ApiNft?) {
    val tiltOffset = 0.15f

    fun gradient(
        radius: Float,
        tiltX: Float,
        tiltY: Float
    ): LayerDrawable {
        return when (nft?.metadata?.mtwCardBorderShineType) {
            UP -> LayerDrawable(
                arrayOf(
                    ScaledDrawable(
                        createRadialGradient(
                            (0.5f + tiltX * tiltOffset).coerceIn(0f, 1f),
                            (-tiltY).coerceIn(-0.2f, 0.5f),
                            radius
                        ),
                        0.5f,
                        1.0f
                    ),
                    createLinearGradient(-tiltX, tiltY)
                )
            )

            DOWN -> LayerDrawable(
                arrayOf(
                    ScaledDrawable(
                        createRadialGradient(
                            (0.5f + tiltX * tiltOffset).coerceIn(0f, 1f),
                            (1f - tiltY).coerceIn(0.5f, 1.2f),
                            radius
                        ),
                        0.5f,
                        1.0f
                    ),
                    createLinearGradient(-tiltX, tiltY)
                )
            )

            LEFT -> LayerDrawable(
                arrayOf(
                    ScaledDrawable(
                        createRadialGradient(
                            (0f + tiltX).coerceIn(-0.2f, 0.5f),
                            (0.5f - tiltY * tiltOffset).coerceIn(0f, 1f),
                            radius
                        ),
                        1.0f,
                        0.5f
                    ),
                    createLinearGradient(-tiltX, tiltY)
                )
            )

            RIGHT -> LayerDrawable(
                arrayOf(
                    ScaledDrawable(
                        createRadialGradient(
                            (1f + tiltX).coerceIn(0.5f, 1.2f),
                            (0.5f - tiltY * tiltOffset).coerceIn(0f, 1f),
                            radius
                        ),
                        1.0f,
                        0.5f
                    ),
                    createLinearGradient(-tiltX, tiltY)
                )
            )

            RADIOACTIVE, null -> {
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

    val gradientColors: IntArray
        get() {
            if (nft?.metadata?.mtwCardBorderShineType == RADIOACTIVE) {
                val greenColor = Color.parseColor("#5CE850")
                return intArrayOf(greenColor, greenColor)
            }
            return when (nft?.metadata?.mtwCardType) {
                BLACK -> {
                    intArrayOf(
                        Color.rgb(41, 41, 41),
                        Color.rgb(20, 21, 24),
                    )
                }

                else -> {
                    intArrayOf(
                        Color.argb(217, 186, 188, 194),
                        Color.argb(128, 140, 148, 176),
                    )
                }
            }
        }

    private fun createLinearGradient(tiltX: Float, tiltY: Float): Drawable {
        val angle = Math.toDegrees(atan2(tiltY, tiltX).toDouble()).toFloat()

        return TiltGradientDrawable(gradientColors).apply {
            this.angle = angle
        }
    }

}
