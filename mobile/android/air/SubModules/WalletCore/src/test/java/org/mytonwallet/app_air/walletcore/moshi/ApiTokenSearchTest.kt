package org.mytonwallet.app_air.walletcore.moshi

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ApiTokenSearchTest {
    @Test
    fun matchesTokenLabel() {
        val token = testToken(label = "TRC-20")

        assertTrue(token.matchesSearch("trc"))
        assertTrue(token.matchesSearch("20"))
    }

    @Test
    fun matchesBlockchainTitle() {
        val token = testToken(chain = "bitcoin_cash", label = "BCH")

        assertTrue(token.matchesSearch("bitcoin cash"))
    }

    @Test
    fun keepsExistingNameSymbolAddressAndKeywordMatches() {
        val token = testToken(
            name = "Custom Coin",
            symbol = "CSTM",
            tokenAddress = "EQ_CUSTOM",
            keywords = listOf("alias")
        )

        assertTrue(token.matchesSearch("custom"))
        assertTrue(token.matchesSearch("cstm"))
        assertTrue(token.matchesSearch("eq_custom"))
        assertTrue(token.matchesSearch("alias"))
        assertFalse(token.matchesSearch("missing"))
    }

    private fun testToken(
        name: String = "Tether USD",
        symbol: String = "USDT",
        chain: String = "tron",
        tokenAddress: String? = null,
        keywords: List<String>? = null,
        label: String? = null,
    ) = ApiTokenWithPrice(
        name = name,
        symbol = symbol,
        slug = "$chain-${symbol.lowercase()}",
        decimals = 6,
        chain = chain,
        tokenAddress = tokenAddress,
        keywords = keywords,
        label = label,
        priceUsd = 1.0,
        percentChange24h = 0.0
    )
}
