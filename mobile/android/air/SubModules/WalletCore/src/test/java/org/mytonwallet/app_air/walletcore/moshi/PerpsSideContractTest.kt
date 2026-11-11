package org.mytonwallet.app_air.walletcore.moshi

import org.junit.Assert.assertEquals
import org.junit.Test

class PerpsSideContractTest {
    private val moshi = MoshiBuilder.build()

    @Test
    fun `order draft sends the side the SDK expects`() {
        val json = moshi.adapter(MApiPerpsDraftRequest::class.java).toJson(
            MApiPerpsDraftRequest(
                assetId = "hyperliquid:BTC",
                side = MApiPerpsSide.SHORT,
                amount = "10",
                unit = PERPS_UNIT_CURRENCY,
                leverage = 2
            )
        )

        assert(json.contains("\"side\":\"short\"")) { json }
    }

    @Test
    fun `position reads the side the SDK sends`() {
        val position = moshi.adapter(MApiPerpsNativePosition::class.java).fromJson(
            """
            {"id":"1","assetId":"a","side":"short","size":"1","collateral":"1","equity":"1",
             "raw":{"coin":"BTC","leverage":{"type":"isolated","value":2},"marginUsed":"1",
             "positionValue":"1","returnOnEquity":"0","szi":"-1","unrealizedPnl":"0"}}
            """.trimIndent()
        )

        assertEquals(MApiPerpsSide.SHORT, position?.side)
    }
}
