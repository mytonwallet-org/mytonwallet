package org.mytonwallet.app_air.walletcore.stores

import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.ARBITRUM_SLUG
import org.mytonwallet.app_air.walletcore.BASE_SLUG
import org.mytonwallet.app_air.walletcore.BASE_USDC_MAINNET_SLUG
import org.mytonwallet.app_air.walletcore.BASE_USDT_MAINNET_SLUG
import org.mytonwallet.app_air.walletcore.BNB_SLUG
import org.mytonwallet.app_air.walletcore.BSC_USDT_MAINNET_SLUG
import org.mytonwallet.app_air.walletcore.ETH_SLUG
import org.mytonwallet.app_air.walletcore.ETH_USDC_MAINNET_SLUG
import org.mytonwallet.app_air.walletcore.ETH_USDT_MAINNET_SLUG
import org.mytonwallet.app_air.walletcore.HYPERLIQUID_SLUG
import org.mytonwallet.app_air.walletcore.HYPERLIQUID_USDC_MAINNET_SLUG
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.SOLANA_SLUG
import org.mytonwallet.app_air.walletcore.SOLANA_USDC_SLUG
import org.mytonwallet.app_air.walletcore.SOLANA_USDT_SLUG
import org.mytonwallet.app_air.walletcore.STAKED_MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.STAKED_USDE_SLUG
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_TESTNET_SLUG
import org.mytonwallet.app_air.walletcore.TRON_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_TESTNET_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.models.MToken

internal object DefaultTokens {

    private const val TON_USDT_MAINNET_IMAGE =
        "https://imgproxy.mytonwallet.org/imgproxy/T3PB4s7oprNVaJkwqbGg54nexKE0zzKhcrPv8jcWYzU/rs:fill:200:200:1/g:no/aHR0cHM6Ly90ZXRoZXIudG8vaW1hZ2VzL2xvZ29DaXJjbGUucG5n.webp"
    private const val SOLANA_USDC_MAINNET_IMAGE =
        "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/logo.png"
    private const val USDE_IMAGE =
        "https://imgproxy.toncenter.com/binMwUmcnFtjvgjp4wSEbsECXwfXUwbPkhVvsvpubNw/pr:small/aHR0cHM6Ly9tZXRhZGF0YS5sYXllcnplcm8tYXBpLmNvbS9hc3NldHMvVVNEZS5wbmc"
    private const val TSUSDE_IMAGE =
        "https://cache.tonapi.io/imgproxy/vGZJ7erwsWPo7DpVG_V7ygNn7VGs0szZXcNLHB_l0ms/rs:fill:200:200:1/g:no/aHR0cHM6Ly9tZXRhZGF0YS5sYXllcnplcm8tYXBpLmNvbS9hc3NldHMvdHNVU0RlLnBuZw.webp"

    private fun token(
        slug: String,
        name: String,
        symbol: String,
        decimals: Int,
        chain: String,
        tokenAddress: String? = null,
        image: String? = null,
        priceUsd: Double? = null,
        cmcSlug: String? = null,
    ): MToken {
        val json = JSONObject()
        json.put("slug", slug)
        json.put("name", name)
        json.put("symbol", symbol)
        json.put("decimals", decimals)
        json.put("chain", chain)
        tokenAddress?.let { json.put("tokenAddress", it) }
        image?.let { json.put("image", it) }
        priceUsd?.let { json.put("priceUsd", it) }
        cmcSlug?.let { json.put("cmcSlug", it) }
        return MToken(json)
    }

    val tokens: Map<String, MToken> by lazy {
        buildDefaultTokens()
    }

    private fun buildDefaultTokens(): Map<String, MToken> = listOf(
        token(TONCOIN_SLUG, "Gram", "GRAM", 9, "ton", cmcSlug = "toncoin"),
        token(TRON_SLUG, "TRON", "TRX", 6, "tron", cmcSlug = "tron"),
        token(SOLANA_SLUG, "Solana", "SOL", 9, "solana", cmcSlug = "solana"),
        token(MYCOIN_SLUG, "My Wallet Coin", "MY", 9, "ton"),
        token(
            USDE_SLUG, "Ethena USDe", "USDe", 6, "ton",
            tokenAddress = "EQAIb6KmdfdDR7CN1GBqVJuP25iCnLKCvBlJ07Evuu2dzP5f",
            image = USDE_IMAGE,
        ),
        token(STAKE_SLUG, "Staked Gram", "STAKED", 9, "ton"),
        token(STAKED_MYCOIN_SLUG, "Staked \$MY", "stMY", 9, "ton"),
        token(
            STAKED_USDE_SLUG, "Ethena tsUSDe", "tsUSDe", 6, "ton",
            tokenAddress = "EQDQ5UUyPHrLcQJlPAczd_fjxn8SLrlNQwolBznxCdSlfQwr",
            image = TSUSDE_IMAGE,
        ),
        token(
            TON_USDT_SLUG, "Tether USD", "USD₮", 6, "ton",
            image = TON_USDT_MAINNET_IMAGE, priceUsd = 1.0,
        ),
        token(
            TON_USDT_TESTNET_SLUG, "Tether USD", "USD₮", 6, "ton",
            tokenAddress = "kQD0GKBM8ZbryVk2aESmzfU6b9b_8era_IkvBSELujFZPsyy", priceUsd = 1.0,
        ),
        token(TRON_USDT_SLUG, "Tether USD", "USDT", 6, "tron"),
        token(
            TRON_USDT_TESTNET_SLUG, "Tether USD", "USDT", 6, "tron",
            tokenAddress = "TG3XXyExBkPp9nzdajDZsozEu4BkaSJozs",
        ),
        token(
            SOLANA_USDT_SLUG, "Tether USD", "USDT", 6, "solana",
            tokenAddress = "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
            image = TON_USDT_MAINNET_IMAGE, priceUsd = 1.0,
        ),
        token(
            SOLANA_USDC_SLUG, "USD Coin", "USDC", 6, "solana",
            tokenAddress = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            image = SOLANA_USDC_MAINNET_IMAGE, priceUsd = 1.0,
        ),
        token(ETH_SLUG, "Ethereum", "ETH", 18, "ethereum"),
        token(
            ETH_USDT_MAINNET_SLUG, "Tether USD", "USDT", 6, "ethereum",
            tokenAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            image = TON_USDT_MAINNET_IMAGE, priceUsd = 1.0,
        ),
        token(
            ETH_USDC_MAINNET_SLUG, "USD Coin", "USDC", 6, "ethereum",
            tokenAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            image = SOLANA_USDC_MAINNET_IMAGE, priceUsd = 1.0,
        ),
        token(BASE_SLUG, "Base", "ETH", 18, "base"),
        token(
            BASE_USDT_MAINNET_SLUG, "Tether USD", "USDT", 6, "base",
            tokenAddress = "0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2",
            image = TON_USDT_MAINNET_IMAGE, priceUsd = 1.0,
        ),
        token(
            BASE_USDC_MAINNET_SLUG, "USD Coin", "USDC", 6, "base",
            tokenAddress = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            image = SOLANA_USDC_MAINNET_IMAGE, priceUsd = 1.0,
        ),
        token(BNB_SLUG, "BNB", "BNB", 18, "bnb"),
        token(
            BSC_USDT_MAINNET_SLUG, "Tether USD", "USDT", 18, "bnb",
            tokenAddress = "0x55d398326f99059ff775485246999027b3197955",
            image = TON_USDT_MAINNET_IMAGE, priceUsd = 1.0,
        ),
        token(ARBITRUM_SLUG, "Arbitrum", "ETH", 18, "arbitrum"),
        token(HYPERLIQUID_SLUG, "Hyperliquid", "HYPE", 18, "hyperliquid"),
        token(
            HYPERLIQUID_USDC_MAINNET_SLUG, "USD Coin", "USDC", 6, "hyperliquid",
            tokenAddress = "0xb88339CB7199b77E23DB6E890353E22632Ba630f",
            image = SOLANA_USDC_MAINNET_IMAGE, priceUsd = 1.0,
        ),
    ).associateBy { it.slug }
}
