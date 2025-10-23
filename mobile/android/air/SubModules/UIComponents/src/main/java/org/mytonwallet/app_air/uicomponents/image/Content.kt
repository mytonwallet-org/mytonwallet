package org.mytonwallet.app_air.uicomponents.image

import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

data class Content(
    val image: Image,
    val subImageRes: Int = 0,
    val subImageAnimation: Int = 0,

    val rounding: Rounding = Rounding.Default,
    val placeholder: Placeholder = Placeholder.Default,
    val scaleType: com.facebook.drawee.drawable.ScalingUtils.ScaleType = com.facebook.drawee.drawable.ScalingUtils.ScaleType.CENTER_CROP,
) {
    sealed class Image {
        data object Empty : Image()
        data class Url(val url: String) : Image()
        data class Res(val res: Int) : Image()
        data class Gradient(
            val key: String,
            val icon: Int
        ) : Image()
    }

    sealed class Rounding {
        data object Default : Rounding()
        data object Round : Rounding()
        data class Radius(
            val radius: Float
        ) : Rounding()
    }

    sealed class Placeholder {
        data object Default : Placeholder()
        data class Color(val color: WColor) : Placeholder()
    }

    companion object {
        fun of(token: IApiToken, alwaysShowChain: Boolean = false): Content {
            val resId = token.mBlockchain?.icon ?: 0

            if (token.isUsdt) {
                return Content(
                    image = Image.Res(R.drawable.ic_coin_usdt_40),
                    subImageRes = resId,
                )
            } else if (resId != 0 && token.isBlockchainNative) {
                return Content(
                    image = Image.Res(resId),
                    subImageRes = if (alwaysShowChain) resId else 0,
                )
            } else {
                return Content(
                    image = Image.Url(token.image ?: ""),
                    subImageRes = resId,
                )
            }
        }

        fun of(
            token: MToken,
            alwaysShowChain: Boolean = false,
            showPercentBadge: Boolean = false
        ): Content {
            val blockchain = token.mBlockchain
            val chainIconRes = blockchain?.icon ?: 0
            val subImageRes = if (alwaysShowChain) chainIconRes else 0
            val isTonOrStake = token.slug == TONCOIN_SLUG || token.slug == STAKE_SLUG

            val mainImage: Image = when {
                showPercentBadge -> {
                    if (isTonOrStake) Image.Res(R.drawable.ic_blockchain_ton_128)
                    else Image.Url(token.image)
                }

                isTonOrStake -> Image.Res(R.drawable.ic_blockchain_ton_128)
                token.image.isNotBlank() -> Image.Url(token.image)
                token.isUsdt -> Image.Res(R.drawable.ic_coin_usdt_40)
                chainIconRes != 0 && token.slug == blockchain?.nativeSlug -> Image.Res(chainIconRes)
                else -> Image.Empty
            }

            val finalSubImageRes = when {
                showPercentBadge -> R.drawable.ic_percent
                token.isUsdt -> chainIconRes
                else -> subImageRes
            }

            return Content(
                image = mainImage,
                subImageRes = finalSubImageRes
            )
        }

        fun chain(chain: MBlockchain) = Content(image = Image.Res(chain.icon))

        fun ofUrl(url: String): Content {
            return Content(
                image = Image.Url(url)
            )
        }
    }
}
