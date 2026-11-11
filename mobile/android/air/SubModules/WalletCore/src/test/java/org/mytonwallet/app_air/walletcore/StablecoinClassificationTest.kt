package org.mytonwallet.app_air.walletcore

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.models.blockchain.getStablecoinSlugs

class StablecoinClassificationTest {
    @Test
    fun includesConfiguredUsdcAcrossChains() {
        val slugs = getStablecoinSlugs()
        listOf(
            "arbitrum-0xaf88d065",
            SOLANA_USDC_SLUG,
            ETH_USDC_MAINNET_SLUG,
            BASE_USDC_MAINNET_SLUG,
            HYPERLIQUID_USDC_MAINNET_SLUG
        ).forEach { slug -> assertTrue(slug, slug in slugs) }
        assertTrue("arbitrum-0xaf88d065" in getStablecoinSlugs(MBlockchainNetwork.MAINNET))
        assertFalse("arbitrum-0xaf88d065" in getStablecoinSlugs(MBlockchainNetwork.TESTNET))
    }

    @Test
    fun includesUsdtOnBothNetworksWithoutMatchingUnconfiguredTokens() {
        val slugs = getStablecoinSlugs()
        assertTrue(TON_USDT_SLUG in slugs)
        assertTrue(TON_USDT_TESTNET_SLUG in slugs)
        assertTrue(TRON_USDT_SLUG in slugs)
        assertTrue(TRON_USDT_TESTNET_SLUG in slugs)
        assertFalse("" in slugs)
        assertFalse(TONCOIN_SLUG in slugs)
        assertFalse("arbitrum-unlisted-usdc" in slugs)
    }
}
