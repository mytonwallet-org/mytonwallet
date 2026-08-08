package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Types
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class MApiTokenDetailsTest {

    @Test
    fun parsesTokenInfoResponse() {
        val type = Types.newParameterizedType(List::class.java, MApiTokenDetails::class.java)
        val adapter = MoshiBuilder.build().adapter<List<MApiTokenDetails>>(type)

        val details = adapter.fromJson(
            """
            [{
              "slug": "toncoin",
              "priceUsd": 4.56,
              "tokenInfo": {
                "description": "English description",
                "localizedDescription": "Localized description",
                "marketCap": 7580000000,
                "supply": { "circulating": 5120000000, "total": 5120000000 },
                "createdAt": "2019-11-15T00:00:00.000Z",
                "volume24h": { "buy": 2440000, "sell": 1580000, "percentChange": 89.46 },
                "links": [{ "url": "https://x.com/toncoin", "type": "x" }],
                "aggregatorLinks": [{ "url": "https://example.com/toncoin", "name": "Aggregator" }],
                "docsUrl": "https://ton.org/docs",
                "sourceCodeUrl": "https://github.com/ton-blockchain"
              }
            }]
            """.trimIndent()
        )?.single()

        assertNotNull(details)
        assertEquals("toncoin", details?.slug)
        assertEquals("Localized description", details?.tokenInfo?.displayDescription)
        assertEquals(7_580_000_000.0, details?.tokenInfo?.marketCap)
        assertEquals(5_120_000_000.0, details?.tokenInfo?.supply?.circulating)
        assertEquals(2_440_000.0, details?.tokenInfo?.volume24h?.buy)
        assertEquals(89.46, details?.tokenInfo?.volume24h?.percentChange)
        assertEquals("x", details?.tokenInfo?.links?.single()?.type)
        assertEquals("Aggregator", details?.tokenInfo?.aggregatorLinks?.single()?.name)
        assertEquals("https://ton.org/docs", details?.tokenInfo?.docsUrl)
        assertEquals("https://github.com/ton-blockchain", details?.tokenInfo?.sourceCodeUrl)
    }

    @Test
    fun parsesVolumeWithoutPercentChange() {
        val type = Types.newParameterizedType(List::class.java, MApiTokenDetails::class.java)
        val adapter = MoshiBuilder.build().adapter<List<MApiTokenDetails>>(type)

        val details = adapter.fromJson(
            """
            [{
              "slug": "toncoin",
              "tokenInfo": {
                "volume24h": { "buy": 2440000, "sell": 1580000 }
              }
            }]
            """.trimIndent()
        )?.single()

        assertNotNull(details)
        assertEquals(2_440_000.0, details?.tokenInfo?.volume24h?.buy)
        assertEquals(1_580_000.0, details?.tokenInfo?.volume24h?.sell)
        assertNull(details?.tokenInfo?.volume24h?.percentChange)
    }

    @Test
    fun fallsBackToDefaultDescriptionWhenLocalizedDescriptionIsBlank() {
        val info = MApiTokenDetails.TokenInfo(
            description = "Default description",
            localizedDescription = " "
        )

        assertEquals("Default description", info.originalDescriptionText)
        assertNull(info.localizedDescriptionText)
        assertEquals("Default description", info.displayDescription)
    }
}
