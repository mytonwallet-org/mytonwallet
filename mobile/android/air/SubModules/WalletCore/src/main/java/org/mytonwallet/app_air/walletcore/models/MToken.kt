package org.mytonwallet.app_air.walletcore.models

import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.WEquatable
import org.mytonwallet.app_air.walletcore.DEFAULT_SHOWN_TOKENS
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.PRICELESS_TOKEN_HASHES
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.stakingSlugToTokenSlug
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.app_air.walletcore.tokenSlugToStakingSlug
import java.math.BigDecimal
import java.math.BigInteger
import java.math.RoundingMode

val DIESEL_TOKENS = arrayOf(
    "EQAvlWFDxGF2lXm67y4yzC17wYKD9A0guwPkMs1gOsM__NOT", // NOT
    "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs", // USDT
    "EQCvxJy4eG8hyHBFsZ7eePxrRsUQSFE_jpptRAYBmcG_DOGS", // DOGS
    "EQD-cvR0Nz6XAyRBvbhz-abTrRC6sI5tvHvvpeQraV9UAAD7", // CATI
    "EQAJ8uWd7EBqsmpSWaRdf_I-8R8-XHwh3gsNKhy-UrdrPcUo", // HAMSTER
)

class MToken(json: JSONObject) : IApiToken, WEquatable<MToken> {

    override val decimals: Int = json.optInt("decimals")
    override val slug: String = json.optString("slug")
    override val symbol: String = json.optString("symbol")
    override var name: String = json.optString("name")
    override var image: String = json.optString("image")
    override val tokenAddress: String? =
        json.optString("minterAddress")
            .ifBlank { json.optString("tokenAddress") }
            .ifBlank { null }
    override val isPopular: Boolean = json.optBoolean("isPopular")
    override val chain: String = json.optString("chain").ifBlank { json.optString("blockchain") }
    val codeHash: String? = json.optString("codeHash")

    var percentChange24hReal: Double = json.optDouble("percentChange24h")
    var percentChange24h: Double =
        if (percentChange24hReal.isFinite()) BigDecimal(percentChange24hReal).setScale(
            2,
            RoundingMode.HALF_UP
        ).toDouble() else percentChange24hReal
    var priceUsd: Double = json.optDouble("priceUsd")
    val isFromBackend: Boolean = json.optBoolean("isFromBackend")
    val type: String = json.optString("type")
    override val keywords: List<String>? = json.optJSONArray("keywords")?.let {
        List(it.length()) { i -> it.optString(i) }
    }
    val cmcSlug: String? = json.optString("cmcSlug").ifBlank { null }
    var color: String? = json.optString("color").ifBlank { null }
    val isGaslessEnabled: Boolean = json.optBoolean("isGaslessEnabled")
    val isStarsEnabled: Boolean = json.optBoolean("isStarsEnabled")
    val isTiny: Boolean = json.optBoolean("isTiny")
    val customPayloadApiUrl: String? = json.optString("customPayloadApiUrl").ifBlank { null }

    override val mBlockchain = try {
        MBlockchain.valueOf(chain)
    } catch (t: Throwable) {
        null
    }
    override val isUsdt: Boolean
        get() {
            return symbol == "USDT" || symbol == "USD₮"
        }
    val isTon: Boolean
        get() {
            return slug == TONCOIN_SLUG
        }

    val isLpToken: Boolean
        get() {
            return type == "lp_token"
        }

    init {
        // TODO:: Remove this temporary fix for usdt on trc20 after image added to back-end services.
        if (slug == TRON_USDT_SLUG) {
            image =
                "https://cache.tonapi.io/imgproxy/T3PB4s7oprNVaJkwqbGg54nexKE0zzKhcrPv8jcWYzU/rs:fill:200:200:1/g:no/aHR0cHM6Ly90ZXRoZXIudG8vaW1hZ2VzL2xvZ29DaXJjbGUucG5n.webp"
        }
    }

    fun toDictionary(): JSONObject {
        val dict = JSONObject().apply {
            put("decimals", decimals)
            put("slug", slug)
            put("symbol", symbol)
            put("name", name)
            put("image", image)
            put("tokenAddress", tokenAddress)
            if (percentChange24hReal.isFinite())
                put("percentChange24h", percentChange24hReal)
            if (priceUsd.isFinite())
                put("priceUsd", priceUsd)
            put("isPopular", isPopular)
            put("chain", chain)
            put("isFromBackend", chain)
            put("type", chain)
            put("keywords", keywords)
            put("cmcSlug", cmcSlug)
            put("color", color)
            put("isGaslessEnabled", isGaslessEnabled)
            put("isStarsEnabled", isStarsEnabled)
            put("isTiny", isTiny)
            put("customPayloadApiUrl", customPayloadApiUrl)
            put("codeHash", codeHash)
        }
        return dict
    }

    fun isHidden(
        account: MAccount? = null,
        assetsAndActivityData: MAssetsAndActivityData? = null
    ): Boolean {
        val account = account ?: AccountStore.activeAccount ?: return true
        val assetsAndActivityData = assetsAndActivityData ?: AccountStore.assetsAndActivityData
        val shouldHide = assetsAndActivityData.hiddenTokens.contains(slug)
        if (shouldHide) {
            return true
        }
        val isVisibleToken = assetsAndActivityData.visibleTokens.contains(slug)
        if (isVisibleToken) {
            return false
        }
        if (DEFAULT_SHOWN_TOKENS[account.network]?.contains(slug) == true && account.isNew)
            return false
        if (PRICELESS_TOKEN_HASHES.contains(codeHash) &&
            (BalanceStore.getBalances(account.accountId)?.get(slug)
                ?: BigInteger.ZERO) > BigInteger.ZERO
        )
            return false
        if (WGlobalStorage.getAreNoCostTokensHidden()) {
            val tokenBalance =
                (BalanceStore.getBalances(account.accountId)?.get(slug) ?: BigInteger.ZERO)
            return priceUsd * tokenBalance.doubleAbsRepresentation(decimals) < 0.01
        }
        return false
    }

    val price: Double?
        get() {
            return TokenStore.baseCurrencyRate?.let { baseCurrencyRate ->
                priceUsd * baseCurrencyRate
            }
        }

    val isOnChain: Boolean
        get() {
            return chain == "ton" || (chain == "tron" && AccountStore.activeAccount?.tronAddress?.isNotBlank() == true)
        }

    fun explorerUrl(network: MBlockchainNetwork): String? {
        if (tokenAddress.isNullOrEmpty() && cmcSlug != null)
            return "https://coinmarketcap.com/currencies/${cmcSlug}/"

        val tokenAddress = tokenAddress ?: return null
        return MBlockchain.valueOf(chain).tokenExplorer()?.tokenUrl(network, tokenAddress)
    }

    val isEarnAvailable: Boolean
        get() {
            return slug == TONCOIN_SLUG || slug == MYCOIN_SLUG || slug == USDE_SLUG
        }

    val stakingSlug: String? = tokenSlugToStakingSlug(slug)

    val unstakedSlug: String? = stakingSlugToTokenSlug(slug)

    override fun isSame(comparing: WEquatable<*>): Boolean {
        return comparing is MToken && slug == comparing.slug
    }

    override fun isChanged(comparing: WEquatable<*>): Boolean {
        return true
    }
}
