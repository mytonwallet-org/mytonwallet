package org.mytonwallet.app_air.walletcore.moshi

import java.math.BigInteger
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.BITCOIN_SLUG

class MTransactionChangeDetectionTest {
    @Test
    fun detectsConfirmationOnlyChanges() {
        val previous = btcTransaction(confirmations = 1, maxConfirmations = 2)
        val next = btcTransaction(confirmations = 2, maxConfirmations = 2)

        assertTrue(next.isChanged(previous))
    }

    @Test
    fun unchangedConfirmationFieldsAreNotChanged() {
        val previous = btcTransaction(confirmations = 1, maxConfirmations = 2)
        val next = btcTransaction(confirmations = 1, maxConfirmations = 2)

        assertFalse(next.isChanged(previous))
    }

    @Test
    fun detectsMaxConfirmationOnlyChanges() {
        val previous = btcTransaction(confirmations = 1, maxConfirmations = 2)
        val next = btcTransaction(confirmations = 1, maxConfirmations = 3)

        assertTrue(next.isChanged(previous))
    }

    @Test
    fun detectsEtaOnlyChanges() {
        val previous = btcTransaction(confirmations = 1, maxConfirmations = 2, etaSeconds = 600)
        val next = btcTransaction(confirmations = 1, maxConfirmations = 2, etaSeconds = 300)

        assertTrue(next.isChanged(previous))
    }

    private fun btcTransaction(
        confirmations: Int?,
        maxConfirmations: Int?,
        etaSeconds: Int? = null
    ): MApiTransaction.Transaction = MApiTransaction.Transaction(
        id = "abc",
        externalMsgHashNorm = null,
        timestamp = 0,
        amount = BigInteger.ONE,
        fromAddress = "from",
        toAddress = "to",
        fee = BigInteger.ZERO,
        slug = BITCOIN_SLUG,
        isIncoming = true,
        normalizedAddress = null,
        status = ApiTransactionStatus.PENDING,
        confirmations = confirmations,
        maxConfirmations = maxConfirmations,
        etaSeconds = etaSeconds
    )
}
