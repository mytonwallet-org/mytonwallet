package org.mytonwallet.app_air.walletcore.moshi

import com.squareup.moshi.Types
import java.math.BigDecimal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

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
    fun completedCexRefreshDefaultsMissingHashesToEmptyList() {
        val swapJson = """
            {
              "id": "swap-id:backend-swap", "kind": "swap", "timestamp": 1,
              "from": "ltc", "to": "usdtbsc", "fromAmount": "1", "toAmount": "100",
              "status": "completed", "transactionIds": {},
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
        assertEquals(emptyList<String>(), swap.hashes)
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
                  "needsBatch": true, "other": []
                }
                """.trimIndent()
            )
        )
        assertEquals("uniswap", quote.dexRouterLabel)
        assertEquals(true, quote.needsBatch)
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

    @Test
    fun evmBuildRequestReachesSubmitWithoutShiftingBatchArgument() {
        val build = requireNotNull(
            moshi.adapter(MApiSwapBuildResponse::class.java).fromJson(
                """
            {
              "id": "swap-id", "chain": "base",
              "transactionRequest": {
                "from": "0x1111111111111111111111111111111111111111",
                "to": "0x2222222222222222222222222222222222222222",
                "chainId": 8453, "data": "0x1234", "value": "30000000000000",
                "gasPrice": "9007199254740993", "gasLimit": "210000", "maxFeePerGas": "2",
                "maxPriorityFeePerGas": "1"
              }
            }
                """.trimIndent()
            )
        )
        assertNull(build.transaction)
        val request = requireNotNull(build.transactionRequest)

        val history = MApiSwapHistoryItem(
            id = "swap-id", timestamp = 1L, from = "base", fromAmount = BigDecimal("0.00003"),
            to = "base-0x833589fc", toAmount = BigDecimal("0.08"), networkFee = 0.0,
            swapFee = BigDecimal.ZERO, status = MApiSwapHistoryItemStatus.PENDING, isCanceled = null
        )
        val submit = ApiMethod.Swap.SwapSubmit(
            MBlockchain.base, "account", "enclave", null, history, false,
            build.transaction, build.calls, request, false, moshi
        )
        val argsType = Types.newParameterizedType(List::class.java, Any::class.java)
        val args = requireNotNull(moshi.adapter<List<Any?>>(argsType).fromJson(submit.arguments))
        assertNull(args[6])
        val encodedRequest = args[8] as Map<*, *>
        assertEquals("0x1234", encodedRequest["data"])
        assertEquals(8453.0, encodedRequest["chainId"])
        assertEquals("30000000000000", encodedRequest["value"])
        assertEquals("9007199254740993", encodedRequest["gasPrice"])
        assertEquals(false, args[9])

        val legacySubmit = ApiMethod.Swap.SwapSubmit(
            MBlockchain.base, "account", "enclave", null, history, false,
            "uniswap-payload", null, null, true, moshi
        )
        val legacyArgs = requireNotNull(
            moshi.adapter<List<Any?>>(argsType).fromJson(legacySubmit.arguments)
        )
        assertEquals("uniswap-payload", legacyArgs[6])
        assertNull(legacyArgs[8])
        assertEquals(true, legacyArgs[9])
    }

    @Test
    fun crossChainDexBuildForwardsRecipientAddress() {
        val request = MApiSwapBuildRequest(
            from = "base", to = "arbitrum", fromAddress = "0xsender",
            toAddress = "0xrecipient", historyAddress = "ton-history",
            fromAmount = BigDecimal("0.00003"), toAmount = BigDecimal("0.000029"),
            toMinAmount = BigDecimal("0.000028"), networkFee = 0.000001,
            swapFee = BigDecimal.ZERO, dexLabel = null, slippage = 1f,
            swapVersion = 3, ourFee = null, dieselFee = null,
            shouldTryDiesel = false, routes = null
        )
        val json = moshi.adapter(MApiSwapBuildRequest::class.java).toJson(request)
        val payload = requireNotNull(
            moshi.adapter(Map::class.java).fromJson(json)
        )

        assertEquals("0xrecipient", payload["toAddress"])
        assertEquals("ton-history", payload["historyAddress"])
    }
}
