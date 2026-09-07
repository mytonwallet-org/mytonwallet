package org.mytonwallet.app_air.walletcore.moshi

import java.math.BigInteger
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ApprovalTransactionUpdateTest {
    private val transfer = MApiTransaction.Transaction(
        id = "approval-hash",
        externalMsgHashNorm = null,
        timestamp = 1,
        amount = BigInteger.ONE,
        fromAddress = "owner",
        toAddress = "spender",
        fee = BigInteger.ZERO,
        slug = "tron:token",
        isIncoming = true,
        normalizedAddress = "owner",
        status = ApiTransactionStatus.COMPLETED
    )

    @Test
    fun detectsReclassifiedApprovalWithoutStatusChange() {
        val approval = transfer.copy(type = ApiTransactionType.APPROVAL)
        assertTrue(transfer.isSame(approval))
        assertTrue(transfer.isChanged(approval))
        assertTrue(approval.isChanged(transfer))
    }

    @Test
    fun detectsAllowanceAndUnlimitedFlagChanges() {
        val approval = transfer.copy(type = ApiTransactionType.APPROVAL)
        assertTrue(approval.isChanged(approval.copy(amount = BigInteger.ZERO)))
        assertTrue(approval.isChanged(approval.copy(isApprovalUnlimited = true)))
    }

    @Test
    fun doesNotInvalidateIdenticalTransactions() {
        assertFalse(transfer.isChanged(transfer.copy()))
        val approval = transfer.copy(type = ApiTransactionType.APPROVAL)
        assertFalse(approval.isChanged(approval.copy()))
    }
}
