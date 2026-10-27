package org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiSubmitTransfersResult

class ConfirmNftVMTest {
    @Test
    fun partialBridgeErrorClosesTheOriginalSelection() {
        val delegate = RecordingDelegate()
        val viewModel = ConfirmNftVM(ConfirmNftVC.Mode.Burn(MBlockchain.ton), delegate)
        val response = ApiSubmitTransfersResult(
            activityIds = listOf("one", "two", "three", "four"),
            error = "PartialTransactionFailure"
        )
        val bridgeError = JSWebViewBridge.ApiError(
            methodName = "submitNftTransfers",
            raw = null,
            parsed = MBridgeError.Type.UNEXPECTED_ERROR,
            parsedResult = response
        )

        viewModel.handleSubmitResult(null, bridgeError, 5, {
            error("Unexpected success")
        }, { error("Unexpected MFA") })

        assertEquals(4 to 5, delegate.partialCounts)
        assertEquals(0, delegate.errors)
    }

    @Test
    fun partialResultAlsoClosesTheOriginalSelection() {
        val delegate = RecordingDelegate()
        val viewModel = ConfirmNftVM(ConfirmNftVC.Mode.Burn(MBlockchain.ton), delegate)
        viewModel.handleSubmitResult(
            ApiSubmitTransfersResult(
                activityIds = listOf("one"),
                error = "PartialTransactionFailure"
            ),
            null,
            5,
            { error("Unexpected success") },
            { error("Unexpected MFA") }
        )

        assertEquals(1 to 5, delegate.partialCounts)
        assertEquals(0, delegate.errors)
    }

    @Test
    fun refusalWithoutAcceptedTransfersRemainsRetryable() {
        val delegate = RecordingDelegate()
        val viewModel = ConfirmNftVM(ConfirmNftVC.Mode.Burn(MBlockchain.ton), delegate)
        viewModel.handleSubmitResult(
            ApiSubmitTransfersResult(error = "InsufficientBalance"),
            null,
            5,
            { error("Unexpected success") },
            { error("Unexpected MFA") }
        )

        assertNull(delegate.partialCounts)
        assertEquals(1, delegate.errors)
    }

    private class RecordingDelegate : ConfirmNftVM.Delegate {
        var partialCounts: Pair<Int, Int>? = null
        var errors = 0

        override fun showError(error: MBridgeError?) {
            errors += 1
        }

        override fun showPartialFailure(completedCount: Int, totalCount: Int) {
            partialCounts = completedCount to totalCount
        }

        override fun feeUpdated(fee: BigInteger?, err: MBridgeError?) = Unit
    }
}
