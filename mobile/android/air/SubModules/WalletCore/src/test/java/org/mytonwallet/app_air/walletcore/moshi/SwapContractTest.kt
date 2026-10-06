package org.mytonwallet.app_air.walletcore.moshi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain

class SwapContractTest {
    private val moshi = MoshiBuilder.build()

    @Test
    fun swapClockFollowsStatusInsteadOfLocalId() {
        val swap = MApiTransaction.Swap(
            id = "swap-id:local",
            externalMsgHashNorm = null,
            timestamp = 1,
            from = "solana-spyx",
            fromAmount = 0.001,
            to = "solana-usdt",
            toAmount = 0.77,
            status = ApiSwapStatus.PENDING
        )

        for (status in ApiSwapStatus.entries) {
            val expected =
                status == ApiSwapStatus.PENDING || status == ApiSwapStatus.PENDING_TRUSTED
            assertEquals(expected, swap.copy(status = status).isInProgress)
            assertEquals(
                expected,
                swap.copy(id = "swap-id:backend-swap", status = status).isInProgress
            )
        }

        val cex = ApiSwapCexTransaction(
            payinAddress = "payin",
            payoutAddress = "payout",
            status = MApiSwapCexTransactionStatus.EXCHANGING,
            transactionId = "provider-id"
        )
        val completed = swap.copy(status = ApiSwapStatus.COMPLETED, cex = cex)
        assertTrue(completed.isInProgress)
        assertFalse(
            completed.copy(
                cex = cex.copy(status = MApiSwapCexTransactionStatus.FINISHED)
            ).isInProgress
        )
    }

    @Test
    fun completedCexRefreshAcceptsNullHashes() {
        val swapJson = """
            {
              "id": "swap-id:backend-swap", "kind": "swap", "timestamp": 1,
              "from": "ltc", "to": "usdtbsc", "fromAmount": "1", "toAmount": "100",
              "status": "completed", "hashes": null, "transactionIds": {},
              "cex": {
                "payinAddress": "payin", "payoutAddress": "payout",
                "status": "finished", "transactionId": "provider-id"
              }
            }
        """.trimIndent()
        val result = requireNotNull(
            moshi.adapter(MApiFetchSwapsResult::class.java).fromJson(
                """
                {
                  "nonExistentIds": [], "swaps": [$swapJson],
                  "patch": {
                    "accountId": "account", "upsert": [$swapJson],
                    "removeIds": [], "replacedIds": {}
                  }
                }
                """.trimIndent()
            )
        )
        val swap = result.swaps.single()
        assertEquals(ApiSwapStatus.COMPLETED, swap.status)
        assertEquals(MApiSwapCexTransactionStatus.FINISHED, swap.cex?.status)
        assertNull(swap.hashes)
        assertEquals(swap, requireNotNull(result.patch).upsert.single())
        assertEquals("swap-id", swap.getTxIdentifier())
        assertEquals(false, swap.isChanged(swap.copy(hashes = emptyList())))
    }

    @Test
    fun uniswapQuotePreservesRouterAndApprovalWithoutTonVenue() {
        val quote = requireNotNull(
            moshi.adapter(MApiSwapEstimateResponse::class.java).fromJson(
                """
                {
                  "route": "dex", "chain": "ethereum", "dexRouterLabel": "uniswap",
                  "from": "ethereum-usdc", "to": "eth",
                  "fromAmount": "20", "toAmount": "0.01", "toMinAmount": "0.0099",
                  "slippage": 1, "impact": 0.1, "dieselStatus": "not-available",
                  "networkFee": "0.0001", "realNetworkFee": "0.0001",
                  "swapFee": "0", "swapFeePercent": 0, "ourFee": "0.00008", "ourFeePercent": 0.8,
                  "needsApprove": true, "other": []
                }
                """.trimIndent()
            )
        )
        assertEquals("uniswap", quote.dexRouterLabel)
        assertEquals(true, quote.needsApprove)
        assertNull(quote.dexLabel)
    }

    @Test
    fun evmBuildPreservesBatchCallsAndTransactionWithoutTonTransfers() {
        val build = requireNotNull(
            moshi.adapter(MApiSwapBuildResponse::class.java).fromJson(
                """
                {
                  "id": "swap-id", "chain": "ethereum", "transaction": "uniswap-payload",
                  "calls": [{"to": "0x1111111111111111111111111111111111111111", "value": "0", "data": "0x1234"}],
                  "isBatchTx": true
                }
                """.trimIndent()
            )
        )
        assertEquals(MBlockchain.ethereum, build.chain)
        assertEquals("uniswap-payload", build.transaction)
        assertNull(build.transfers)
        assertEquals(
            listOf(MApiEvmSwapCall("0x1111111111111111111111111111111111111111", "0", "0x1234")),
            build.calls
        )
    }
}
