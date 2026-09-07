package org.mytonwallet.app_air.uiswap.screens.swap

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Test

class NativeFeeGateTest {

    @Test
    fun unknownFeeBlocksASupportedSourceChain() {
        assertEquals(
            NativeFeeGate.Unknown,
            resolveNativeFeeGate(
                fee = null,
                nativeBalance = BigInteger.TEN,
                isSourceChainSupported = true
            )
        )
    }

    @Test
    fun unknownFeePassesWhenTheWalletDoesNotSendTheTransfer() {
        assertEquals(
            NativeFeeGate.Ok,
            resolveNativeFeeGate(
                fee = null,
                nativeBalance = BigInteger.ZERO,
                isSourceChainSupported = false
            )
        )
    }

    @Test
    fun feeAboveTheNativeBalanceIsInsufficient() {
        assertEquals(
            NativeFeeGate.Insufficient,
            resolveNativeFeeGate(
                fee = BigInteger.valueOf(11),
                nativeBalance = BigInteger.TEN,
                isSourceChainSupported = true
            )
        )
    }

    @Test
    fun feeWithinTheNativeBalancePasses() {
        assertEquals(
            NativeFeeGate.Ok,
            resolveNativeFeeGate(
                fee = BigInteger.TEN,
                nativeBalance = BigInteger.TEN,
                isSourceChainSupported = true
            )
        )
    }
}
