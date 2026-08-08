package org.mytonwallet.app_air.walletcore.helpers

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction

class ActivityHelpersTest {
    @Test
    fun preservesSdkStableAliasAcrossSameIdUpdates() {
        val existing = transaction("chain-id", ApiTransactionStatus.CONFIRMED).also {
            it.replacedStableId = "local-id"
        }
        val incoming = transaction("chain-id", ApiTransactionStatus.COMPLETED)

        val adjusted = ActivityHelpers.preserveStatusProgress(existing, incoming)

        assertEquals("local-id", adjusted.getStableId())
    }

    @Test
    fun doesNotInferStableAliasAcrossDifferentIds() {
        val existing = transaction("first-chain-id", ApiTransactionStatus.CONFIRMED).also {
            it.replacedStableId = "local-id"
        }
        val incoming = transaction("second-chain-id", ApiTransactionStatus.COMPLETED)

        val adjusted = ActivityHelpers.preserveStatusProgress(existing, incoming)

        assertEquals("second-chain-id", adjusted.getStableId())
    }

    private fun transaction(id: String, status: ApiTransactionStatus) = MApiTransaction.Transaction(
        id = id,
        externalMsgHashNorm = null,
        timestamp = 1,
        amount = BigInteger.ONE,
        fromAddress = "from",
        toAddress = "to",
        fee = BigInteger.ZERO,
        slug = "toncoin",
        isIncoming = false,
        normalizedAddress = "to",
        status = status
    )
}
