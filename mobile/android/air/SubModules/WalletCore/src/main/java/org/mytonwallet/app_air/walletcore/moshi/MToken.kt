package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.JsonClass
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.stores.TokenStore

interface IApiToken {
    val slug: String
    val decimals: Int
    val name: String?
    val symbol: String?
    val chain: String?
    val tokenAddress: String?
    val image: String?
    val isPopular: Boolean?
    val keywords: List<String>?

    val mBlockchain
        get() = try {
            MBlockchain.valueOf(chain!!)
        } catch (t: Throwable) {
            null
        }

    val nativeToken: MToken?
        get() {
            return TokenStore.getToken(mBlockchain?.nativeSlug)
        }

    val isTON get() = slug == MBlockchain.ton.nativeSlug
    val isJetton get() = !isTON && mBlockchain == MBlockchain.ton
    val isTonOrJetton get() = isTON || isJetton

    val isBlockchainNative get() = mBlockchain?.nativeSlug == slug
    val isUsdt get() = symbol == "USDT" || symbol == "USD₮"

    val swapSlug
        get() = if (isTON) "TON" else {
            tokenAddress ?: slug
        }
}

@JsonClass(generateAdapter = true)
data class ApiTokenWithPrice(
    override val name: String?,
    override val symbol: String?,
    override val slug: String,
    override val decimals: Int,
    override val chain: String?,
    override val tokenAddress: String? = null,
    override val image: String? = null,
    override val isPopular: Boolean? = null,
    override val keywords: List<String>? = null,
    val cmcSlug: String? = null,
    val color: String? = null,
    val isGaslessEnabled: Boolean? = null,
    val isStarsEnabled: Boolean? = null,
    val isTiny: Boolean? = null,
    val customPayloadApiUrl: String? = null,
    val codeHash: String? = null,
    val priceUsd: Double?,
    val percentChange24h: Double?
) : IApiToken {

    val price: Double?
        get() {
            return priceUsd?.let { priceUsd ->
                TokenStore.baseCurrencyRate?.let { baseCurrencyRate ->
                    priceUsd * baseCurrencyRate
                }
            }
        }

}
