package org.mytonwallet.app_air.walletcore.moshi.api

import com.squareup.moshi.JsonDataException
import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.MoshiBuilder

class ApiUpdateDecodingTest {
    private val moshi = MoshiBuilder.build()

    private inline fun <reified T : ApiUpdate> decode(json: String): T? =
        moshi.adapter(T::class.java).fromJson(json)

    @Test
    fun unknownTopLevelFieldsAreIgnored() {
        val update = decode<ApiUpdate.ApiUpdateUpdatingStatus>(
            """{"kind":"balance","accountId":"0-ton","isUpdating":true,"futureField":{"nested":[1,2]}}"""
        )
        assertEquals("balance", update?.kind)
        assertEquals(true, update?.isUpdating)
    }

    @Test
    fun optionalFieldsMayBeAbsent() {
        assertEquals(
            null,
            decode<ApiUpdate.ApiUpdateUpdatingStatus>("""{"kind":"activities"}""")?.isUpdating
        )
        assertNull(decode<ApiUpdate.ApiUpdateShowError>("""{}""")?.error)
        assertEquals(
            null,
            decode<ApiUpdate.ApiUpdateOpenUrl>("""{"url":"https://a.b"}""")?.isExternal
        )
    }

    @Test
    fun missingRequiredFieldRejectsOnlyThatUpdate() {
        assertThrows(JsonDataException::class.java) {
            decode<ApiUpdate.ApiUpdateUpdatingStatus>("""{"accountId":"0-ton","isUpdating":true}""")
        }
        assertThrows(JsonDataException::class.java) {
            decode<ApiUpdate.ApiUpdateNftSent>("""{"accountId":"0-ton"}""")
        }
    }

    @Test
    fun extraFieldsDeclaredInTsButUnusedNativelyAreIgnored() {
        val sent = decode<ApiUpdate.ApiUpdateNftSent>(
            """{"accountId":"0-ton","chain":"ton","nftAddress":"EQ1","newOwnerAddress":"EQ2"}"""
        )
        assertEquals("EQ1", sent?.nftAddress)
        val url = decode<ApiUpdate.ApiUpdateOpenUrl>(
            """{"url":"https://a.b","isExternal":false,"title":"t","subtitle":"s"}"""
        )
        assertEquals("https://a.b", url?.url)
    }

    @Test
    fun balancesDecodeBridgeBigintEncoding() {
        val update = decode<ApiUpdate.ApiUpdateBalances>(
            """{"accountId":"0-ton","chain":"ton","balances":{"toncoin":"bigint:123456789012345678901234567890","usdt":"bigint:0"}}"""
        )
        assertEquals(BigInteger("123456789012345678901234567890"), update?.balances?.get("toncoin"))
        assertEquals(BigInteger.ZERO, update?.balances?.get("usdt"))
    }

    @Test
    fun domainDataDecodesMapsAndIgnoresNfts() {
        val update = decode<ApiUpdate.ApiUpdateAccountDomainData>(
            """{"accountId":"0-ton","expirationByAddress":{"EQ1":1700000000000},"linkedAddressByAddress":{"EQ1":"EQ9"},"nfts":{"EQ1":{"address":"EQ1","whatever":true}}}"""
        )
        assertEquals(1700000000000L, update?.expirationByAddress?.get("EQ1"))
        assertEquals("EQ9", update?.linkedAddressByAddress?.get("EQ1"))
    }

    @Test
    fun accountConfigKeepsRawBlob() {
        val update = decode<ApiUpdate.ApiUpdateAccountConfig>(
            """{"accountId":"0-ton","accountConfig":{"isMfaEnabled":true,"newKey":"v"}}"""
        )
        assertNotNull(update?.accountConfig)
    }

    @Test
    fun configToleratesUnknownAndAbsentFields() {
        val update = decode<ApiUpdate.ApiUpdateConfig>(
            """{"isLimited":false,"isCopyStorageEnabled":true,"isAppUpdateRequired":false,"seasonalTheme":"newYear","knowledgeBaseVersion":"3","swapVersion":3}"""
        )
        assertEquals(3, update?.swapVersion)
        assertEquals("newYear", update?.seasonalTheme)
        assertNull(update?.countryCode)
    }
}
