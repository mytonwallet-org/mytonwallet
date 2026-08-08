package org.mytonwallet.app_air.uiswap.screens.swap.helpers

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TON_CHAIN
import org.mytonwallet.app_air.walletcore.TON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset

class SwapDefaultTokensTest {

    private val ton = asset(
        slug = TONCOIN_SLUG,
        symbol = "TON",
        chain = TON_CHAIN,
        decimals = 9,
        priceUsd = 3.0
    )
    private val tonUsdt = asset(
        slug = TON_USDT_SLUG,
        symbol = "USD₮",
        chain = TON_CHAIN,
        decimals = 6,
        priceUsd = 1.0
    )
    private val usdc = asset(
        slug = "ton-usdc",
        symbol = "USDC",
        chain = TON_CHAIN,
        decimals = 6,
        priceUsd = 1.0
    )
    private val gold = asset(
        slug = "ton-gold",
        symbol = "GOLD",
        chain = TON_CHAIN,
        decimals = 9,
        priceUsd = 5.0
    )

    @Test
    fun defaultsToTonAndTonUsdt() {
        val defaults = resolve()

        assertEquals(ton.slug, defaults.tokenToSend?.slug)
        assertEquals(tonUsdt.slug, defaults.tokenToReceive?.slug)
    }

    @Test
    fun missingSendingTokenDefaultsToTon() {
        val defaults = resolve(
            receivingToken = gold
        )

        assertEquals(ton.slug, defaults.tokenToSend?.slug)
        assertEquals(gold.slug, defaults.tokenToReceive?.slug)
    }

    @Test
    fun buyingTonDefaultsToTonUsdtForSelling() {
        val defaults = resolve(receivingToken = ton)

        assertEquals(tonUsdt.slug, defaults.tokenToSend?.slug)
        assertEquals(ton.slug, defaults.tokenToReceive?.slug)
    }

    @Test
    fun otherSellingTokenDefaultsToTonUsdtForBuying() {
        val defaults = resolve(sendingToken = usdc)

        assertEquals(usdc.slug, defaults.tokenToSend?.slug)
        assertEquals(tonUsdt.slug, defaults.tokenToReceive?.slug)
    }

    @Test
    fun sellingTonUsdtDefaultsToTonForBuying() {
        val defaults = resolve(sendingToken = tonUsdt)

        assertEquals(tonUsdt.slug, defaults.tokenToSend?.slug)
        assertEquals(ton.slug, defaults.tokenToReceive?.slug)
    }

    @Test
    fun explicitPairIsPreserved() {
        val defaults = resolve(
            sendingToken = usdc,
            receivingToken = gold
        )

        assertEquals(usdc.slug, defaults.tokenToSend?.slug)
        assertEquals(gold.slug, defaults.tokenToReceive?.slug)
    }

    private fun resolve(
        sendingToken: MApiSwapAsset? = null,
        receivingToken: MApiSwapAsset? = null
    ) = SwapHelpers.resolveDefaultTokens(
        assets = listOf(ton, tonUsdt, usdc, gold),
        defaultSendingToken = sendingToken,
        defaultReceivingToken = receivingToken
    )

    private fun asset(
        slug: String,
        symbol: String,
        chain: String,
        decimals: Int,
        priceUsd: Double
    ) = MApiSwapAsset(
        name = symbol,
        symbol = symbol,
        chain = chain,
        slug = slug,
        decimals = decimals,
        priceUsd = priceUsd
    )
}
