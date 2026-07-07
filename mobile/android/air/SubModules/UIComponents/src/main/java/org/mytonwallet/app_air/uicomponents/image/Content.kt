package org.mytonwallet.app_air.uicomponents.image

import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.stores.TokenStore

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

        data class RadiusRatio(
            val ratio: Float
        ) : Rounding()
    }

    sealed class Placeholder {
        data object Default : Placeholder()
        data class Color(val color: WColor) : Placeholder()
        data class Initials(val text: String) : Placeholder()
    }

    companion object {
        private const val STOCK_TOKEN_CORNER_RADIUS_RATIO = 0.3f

        private fun roundingFor(token: IApiToken): Rounding =
            if (token.isRwaStock) Rounding.RadiusRatio(STOCK_TOKEN_CORNER_RADIUS_RATIO)
            else Rounding.Default

        fun of(token: IApiToken, showChain: Boolean): Content {
            val nativeIconId = token.mBlockchain?.nativeIcon ?: 0
            val rounding = roundingFor(token)

            return if (nativeIconId != 0 && token.isBlockchainNative) {
                Content(
                    image = Image.Res(nativeIconId),
                    subImageRes = 0,
                    rounding = rounding,
                )
            } else if (token.isUsdt) {
                Content(
                    image = Image.Res(R.drawable.ic_coin_usdt_40),
                    subImageRes = if (showChain) token.mBlockchain?.icon ?: 0 else 0,
                    rounding = rounding,
                )
            } else {
                val image = token.image?.takeIf { it.isNotBlank() }
                Content(
                    image = if (image != null) Image.Url(image) else Image.Empty,
                    subImageRes = if (showChain) token.mBlockchain?.icon ?: 0 else 0,
                    placeholder = Placeholder.Initials(tokenInitials(token.name, token.symbol)),
                    rounding = rounding,
                )
            }
        }

        fun of(
            tokenBalance: MTokenBalance,
            showChain: Boolean,
            showPercentBadge: Boolean = false
        ): Content? {
            val balanceToken = TokenStore.getToken(tokenBalance.token) ?: run {
                return null
            }
            val token =
                if (balanceToken.slug == STAKE_SLUG)
                    TokenStore.getToken(TONCOIN_SLUG) ?: balanceToken
                else
                    balanceToken
            val blockchain = token.mBlockchain
            val chainIconRes = blockchain?.icon ?: 0
            val isTonOrStake = token.slug == TONCOIN_SLUG || token.slug == STAKE_SLUG

            val mainImage: Image = when {
                showPercentBadge -> {
                    if (isTonOrStake) Image.Res(R.drawable.ic_token_gram)
                    else Image.Url(token.image)
                }

                isTonOrStake -> Image.Res(R.drawable.ic_token_gram)
                token.image.isNotBlank() -> Image.Url(token.image)
                token.isUsdt -> Image.Res(R.drawable.ic_coin_usdt_40)
                chainIconRes != 0 && token.slug == blockchain?.nativeSlug -> Image.Res(chainIconRes)
                else -> Image.Empty
            }

            val finalSubImageRes = when {
                showPercentBadge -> R.drawable.ic_percent
                showChain && !token.isBlockchainNative -> chainIconRes
                else -> 0
            }

            val placeholder = when (mainImage) {
                is Image.Url, is Image.Empty ->
                    Placeholder.Initials(tokenInitials(token.name, token.symbol))

                else -> Placeholder.Default
            }

            return Content(
                image = mainImage,
                subImageRes = finalSubImageRes,
                placeholder = placeholder,
                rounding = roundingFor(token)
            )
        }

        fun tokenInitials(name: String?, symbol: String?): String {
            val source =
                name?.takeIf { it.isNotBlank() } ?: symbol?.takeIf { it.isNotBlank() } ?: return "?"
            val parts = source.split("[^\\p{L}\\p{N}]+".toRegex()).filter { it.isNotEmpty() }
            return when {
                parts.size >= 2 ->
                    parts.take(2).joinToString("") { it.first().toString() }.uppercase()

                parts.isNotEmpty() -> parts.first().take(2).uppercase()
                else -> "?"
            }
        }

        fun chain(chain: MBlockchain) = Content(image = Image.Res(chain.icon))

        fun ofUrl(url: String): Content {
            return Content(
                image = Image.Url(url)
            )
        }
    }
}
