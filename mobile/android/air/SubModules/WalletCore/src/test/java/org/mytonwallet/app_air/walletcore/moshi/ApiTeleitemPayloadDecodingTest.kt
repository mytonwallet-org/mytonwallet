package org.mytonwallet.app_air.walletcore.moshi

import org.junit.Assert.assertEquals
import org.junit.Test

class ApiTeleitemPayloadDecodingTest {
    private val adapter = MoshiBuilder.build().adapter(ApiParsedPayload::class.java)

    @Test
    fun decodesStartAuctionWithUint32Duration() {
        val payload = adapter.fromJson(
            """{"type":"teleitem:start-auction","queryId":"bigint:1","nftAddress":"EQ1","beneficiaryAddress":"EQ2","initialMinBid":"bigint:1000000000","maxBid":"bigint:1000000000","minBidStep":5,"minExtendTime":4294967295,"duration":2148088448}"""
        ) as ApiParsedPayload.ApiTeleitemStartAuctionPayload

        assertEquals(4294967295L, payload.minExtendTime)
        assertEquals(2148088448L, payload.duration)
    }

    @Test
    fun decodesDeployWithUint32Duration() {
        val payload = adapter.fromJson(
            """{"type":"teleitem:deploy","tokenName":"gift","beneficiaryAddress":"EQ2","initialMinBid":"bigint:1000000000","maxBid":"bigint:1000000000","minBidStep":5,"minExtendTime":4294967295,"duration":4294967295}"""
        ) as ApiParsedPayload.ApiTeleitemDeployPayload

        assertEquals(4294967295L, payload.minExtendTime)
        assertEquals(4294967295L, payload.duration)
    }
}
