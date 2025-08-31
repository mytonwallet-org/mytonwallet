package org.mytonwallet.app_air.walletcore.models

import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletcore.ALWAYS_SHOWN_TOKENS
import org.mytonwallet.app_air.walletcore.DEFAULT_SHOWN_TOKENS
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.PRICELESS_TOKEN_HASHES
import org.mytonwallet.app_air.walletcore.STAKED_MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.STAKED_USDE_SLUG
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
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

class MToken(json: JSONObject) : IApiToken {

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

    var price: Double? = json.optDouble("price")
    var percentChange24hReal: Double = json.optDouble("percentChange24h")
    var percentChange24h: Double =
        if (percentChange24hReal.isFinite()) BigDecimal(percentChange24hReal).setScale(
            2,
            RoundingMode.HALF_UP
        ).toDouble() else percentChange24hReal
    var priceUsd: Double = json.optDouble("priceUsd")
    val isFromBackend: Boolean = json.optBoolean("isFromBackend")
    val type: String = json.optString("type")
    val keywords: List<String>? = json.optJSONArray("keywords")?.let {
        List(it.length()) { i -> it.optString(i) }
    }
    val cmcSlug: String? = json.optString("cmcSlug").ifBlank { null }
    val color: String? = json.optString("color").ifBlank { null }
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
            if (price?.isFinite() == true)
                put("price", price)
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

    fun isHidden(): Boolean {
        val shouldHide = AccountStore.assetsAndActivityData.hiddenTokens.contains(slug)
        if (shouldHide) {
            return true
        }
        val isVisibleToken = AccountStore.assetsAndActivityData.visibleTokens.contains(slug)
        if (isVisibleToken) {
            return false
        }
        if ((ALWAYS_SHOWN_TOKENS.contains(slug) &&
                AccountStore.activeAccount?.addressByChain?.contains(chain) == true) ||
            (DEFAULT_SHOWN_TOKENS.contains(slug) && AccountStore.activeAccount?.isNew == true)
        )
            return false
        if (PRICELESS_TOKEN_HASHES.contains(codeHash) &&
            (BalanceStore.getBalances(AccountStore.activeAccountId)?.get(slug)
                ?: BigInteger.ZERO) > BigInteger.ZERO
        )
            return false
        if (WGlobalStorage.getAreNoCostTokensHidden()) {
            val tokenBalance = (BalanceStore.getBalances(AccountStore.activeAccountId)?.get(slug)
                ?: BigInteger.ZERO)
            return priceUsd * tokenBalance.doubleAbsRepresentation(decimals) < 0.01
        }
        return false
    }

    val isOnChain: Boolean
        get() {
            return chain == "ton" || (chain == "tron" && AccountStore.activeAccount?.tronAddress?.isNotBlank() == true)
        }

    val explorerUrl: String?
        get() {
            if (tokenAddress.isNullOrEmpty())
                return "https://coinmarketcap.com/currencies/${cmcSlug}/"

            val chain = MBlockchain.valueOf(chain)

            return when (chain) {
                MBlockchain.ton -> {
                    val domain = ExplorerHelpers.tonScanUrl(WalletCore.activeNetwork)
                    "${domain}jetton/${tokenAddress}"
                }

                MBlockchain.tron -> {
                    val domain = ExplorerHelpers.tronScanUrl(WalletCore.activeNetwork)
                    return "${domain}token20/${tokenAddress}"
                }

                else -> {
                    return null
                }
            }
        }

    val isEarnAvailable: Boolean
        get() {
            return slug == TONCOIN_SLUG || slug == MYCOIN_SLUG || slug == USDE_SLUG
        }

    val stakingSlug: String?
        get() {
            return when (slug) {
                TONCOIN_SLUG -> STAKE_SLUG
                MYCOIN_SLUG -> STAKED_MYCOIN_SLUG
                USDE_SLUG -> STAKED_USDE_SLUG
                else -> null
            }
        }

    val unstakedSlug: String?
        get() {
            return when (slug) {
                STAKE_SLUG, TONCOIN_SLUG -> TONCOIN_SLUG
                STAKED_MYCOIN_SLUG, MYCOIN_SLUG -> MYCOIN_SLUG
                STAKED_USDE_SLUG, USDE_SLUG -> USDE_SLUG
                else -> null
            }
        }
}
