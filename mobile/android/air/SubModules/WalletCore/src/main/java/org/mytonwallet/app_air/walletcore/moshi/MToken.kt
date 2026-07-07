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
    val label: String?
        get() = null

    val mBlockchain
        get() = chain?.let { MBlockchain.valueOfOrNull(it) }

    val nativeToken: MToken?
        get() {
            return TokenStore.getToken(mBlockchain?.nativeSlug)
        }

    val isTON get() = slug == MBlockchain.ton.nativeSlug
    val isJetton get() = !isTON && mBlockchain == MBlockchain.ton
    val isTonOrJetton get() = isTON || isJetton

    val isBlockchainNative get() = mBlockchain?.nativeSlug == slug
    val isUsdt get() = symbol == "USDT" || symbol == "USD₮"
    val isRwaStock get() = keywords?.contains("rwa") == true

    val swapSlug
        get() = if (isTON) "TON" else {
            tokenAddress ?: slug
        }

    fun matchesSearch(search: String): Boolean {
        val keyword = search.trim().lowercase()
        if (keyword.isEmpty()) return true
        if (name?.lowercase()?.contains(keyword) == true) return true
        if (symbol?.lowercase()?.contains(keyword) == true) return true
        if (label?.lowercase()?.contains(keyword) == true) return true
        if (chain?.lowercase()?.contains(keyword) == true) return true
        if (chain?.toSearchableChainTitle()?.contains(keyword) == true) return true
        if (tokenAddress?.lowercase()?.contains(keyword) == true) return true
        if (keywords?.any { it.lowercase().contains(keyword) } == true) return true
        return false
    }

    private fun String.toSearchableChainTitle(): String {
        return replace('_', ' ').replace('-', ' ').lowercase()
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
    override val label: String? = null,
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
