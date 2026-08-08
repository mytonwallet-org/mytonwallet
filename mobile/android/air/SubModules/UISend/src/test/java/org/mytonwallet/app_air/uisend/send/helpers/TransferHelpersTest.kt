package org.mytonwallet.app_air.uisend.send.helpers

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.MDieselStatus
import org.mytonwallet.app_air.walletcore.moshi.MTransferDiesel
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MExplainedTransferFee
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFee
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFeePrecision
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFeeTerms

class TransferHelpersTest {

    @Test
    fun nativeTransferFeeIncludesTokenAndNativeTerms() {
        val terms = feeTerms(token = 10, native = 20, stars = 30)

        assertEquals(BigInteger.valueOf(30), TransferHelpers.getFullTransferFee(terms, true))
    }

    @Test
    fun nonNativeTransferFeeIncludesOnlyTokenTerms() {
        val terms = feeTerms(token = 10, native = 20, stars = 30)

        assertEquals(BigInteger.TEN, TransferHelpers.getFullTransferFee(terms, false))
    }

    @Test
    fun missingFeeTermsReturnNull() {
        assertNull(TransferHelpers.getFullTransferFee(null, true))
    }

    @Test
    fun missingFeePartsAreTreatedAsZero() {
        val terms = MFeeTerms(token = null, native = null, stars = null)

        assertEquals(BigInteger.ZERO, TransferHelpers.getFullTransferFee(terms, true))
    }

    @Test
    fun maxNativeTransferSubtractsTokenAndNativeFeeTerms() {
        val maxAmount = TransferHelpers.getMaxTransferAmount(
            tokenBalance = BigInteger.valueOf(100),
            isNativeToken = true,
            fullFee = feeTerms(token = 10, native = 20),
            canTransferFullBalance = false
        )

        assertEquals(BigInteger.valueOf(70), maxAmount)
    }

    @Test
    fun maxNonNativeTransferSubtractsOnlyTokenFeeTerms() {
        val maxAmount = TransferHelpers.getMaxTransferAmount(
            tokenBalance = BigInteger.valueOf(100),
            isNativeToken = false,
            fullFee = feeTerms(token = 10, native = 20),
            canTransferFullBalance = false
        )

        assertEquals(BigInteger.valueOf(90), maxAmount)
    }

    @Test
    fun maxTransferAmountDoesNotBecomeNegative() {
        val maxAmount = TransferHelpers.getMaxTransferAmount(
            tokenBalance = BigInteger.valueOf(5),
            isNativeToken = false,
            fullFee = feeTerms(token = 10),
            canTransferFullBalance = false
        )

        assertEquals(BigInteger.ZERO, maxAmount)
    }

    @Test
    fun maxTransferAmountIsZeroWhenFeeEqualsBalance() {
        val maxAmount = TransferHelpers.getMaxTransferAmount(
            tokenBalance = BigInteger.TEN,
            isNativeToken = false,
            fullFee = feeTerms(token = 10),
            canTransferFullBalance = false
        )

        assertEquals(BigInteger.ZERO, maxAmount)
    }

    @Test
    fun maxTransferAmountPreservesArbitraryPrecision() {
        val balance = BigInteger("123456789012345678901234567890")
        val fee = BigInteger("98765432109876543210")
        val maxAmount = TransferHelpers.getMaxTransferAmount(
            tokenBalance = balance,
            isNativeToken = false,
            fullFee = MFeeTerms(token = fee, native = null, stars = null),
            canTransferFullBalance = false
        )

        assertEquals(balance - fee, maxAmount)
    }

    @Test
    fun missingOrNonPositiveBalanceHasNoMaximum() {
        val terms = feeTerms(token = 1)

        assertNull(TransferHelpers.getMaxTransferAmount(null, false, terms, false))
        assertNull(TransferHelpers.getMaxTransferAmount(BigInteger.ZERO, false, terms, false))
        assertNull(
            TransferHelpers.getMaxTransferAmount(BigInteger.valueOf(-1), false, terms, false)
        )
    }

    @Test
    fun fullBalanceSupportDoesNotOverrideMaximum() {
        assertNull(
            TransferHelpers.getMaxTransferAmount(
                tokenBalance = BigInteger.valueOf(100),
                isNativeToken = true,
                fullFee = feeTerms(native = 20),
                canTransferFullBalance = true
            )
        )
    }

    @Test
    fun missingFeeDoesNotOverrideMaximum() {
        assertNull(
            TransferHelpers.getMaxTransferAmount(
                tokenBalance = BigInteger.valueOf(100),
                isNativeToken = true,
                fullFee = null,
                canTransferFullBalance = false
            )
        )
    }

    @Test
    fun nonTonNativeTransferShowsFullFeeWhenAmountAndFeeExceedBalance() {
        val shouldShowFullFee = TransferHelpers.shouldShowFullFee(
            tokenBalance = BigInteger.valueOf(100),
            isNativeToken = true,
            nativeTokenBalance = BigInteger.valueOf(100),
            transferAmount = BigInteger.valueOf(96),
            explainedFee = explainedFee(native = 5, nativeSum = 5),
            diesel = null
        )

        assertTrue(shouldShowFullFee)
    }

    @Test
    fun amountAboveTokenBalanceDoesNotShowFullFee() {
        val shouldShowFullFee = TransferHelpers.shouldShowFullFee(
            tokenBalance = BigInteger.valueOf(100),
            isNativeToken = false,
            nativeTokenBalance = BigInteger.valueOf(100),
            transferAmount = BigInteger.valueOf(101),
            explainedFee = explainedFee(native = 5, nativeSum = 5),
            diesel = null
        )

        assertFalse(shouldShowFullFee)
    }

    @Test
    fun availableDieselShowsRealFeeWhenTokenBalanceCoversIt() {
        val shouldShowFullFee = TransferHelpers.shouldShowFullFee(
            tokenBalance = BigInteger.valueOf(100),
            isNativeToken = false,
            nativeTokenBalance = BigInteger.ZERO,
            transferAmount = BigInteger.valueOf(96),
            explainedFee = explainedFee(
                isGasless = true,
                token = 4,
                native = 0,
                nativeSum = 5
            ),
            diesel = diesel(MDieselStatus.AVAILABLE, 4)
        )

        assertFalse(shouldShowFullFee)
    }

    @Test
    fun fullNativeTransferShowsFullFeeWhenFeeIsNotBelowBalance() {
        val shouldShowFullFee = TransferHelpers.shouldShowFullFee(
            tokenBalance = BigInteger.valueOf(100),
            isNativeToken = true,
            nativeTokenBalance = BigInteger.valueOf(100),
            transferAmount = BigInteger.valueOf(100),
            explainedFee = explainedFee(
                canTransferFullBalance = true,
                native = 100,
                nativeSum = 100
            ),
            diesel = null
        )

        assertTrue(shouldShowFullFee)
    }

    @Test
    fun starsDieselDoesNotConsumeTransferredToken() {
        val shouldShowFullFee = TransferHelpers.shouldShowFullFee(
            tokenBalance = BigInteger.valueOf(100),
            isNativeToken = false,
            nativeTokenBalance = BigInteger.ZERO,
            transferAmount = BigInteger.valueOf(100),
            explainedFee = explainedFee(
                isGasless = true,
                stars = 1,
                native = 0,
                nativeSum = 5
            ),
            diesel = diesel(MDieselStatus.STARS_FEE, 1)
        )

        assertFalse(shouldShowFullFee)
    }

    @Test
    fun insufficientFeeErrorMatchesWebBalanceCoverage() {
        assertTrue(
            TransferHelpers.hasInsufficientFeeError(
                tokenBalance = BigInteger.valueOf(100),
                nativeTokenBalance = BigInteger.valueOf(4),
                transferAmount = BigInteger.valueOf(50),
                fullFee = feeTerms(native = 5),
                canTransferFullBalance = false,
                dieselStatus = null
            )
        )
        assertTrue(
            TransferHelpers.hasInsufficientFeeError(
                tokenBalance = BigInteger.valueOf(100),
                nativeTokenBalance = BigInteger.valueOf(100),
                transferAmount = BigInteger.valueOf(96),
                fullFee = feeTerms(token = 5),
                canTransferFullBalance = false,
                dieselStatus = null
            )
        )
    }

    @Test
    fun insufficientAmountIsNotInsufficientFeeError() {
        assertFalse(
            TransferHelpers.hasInsufficientFeeError(
                tokenBalance = BigInteger.valueOf(100),
                nativeTokenBalance = BigInteger.ZERO,
                transferAmount = BigInteger.valueOf(101),
                fullFee = feeTerms(native = 5),
                canTransferFullBalance = false,
                dieselStatus = null
            )
        )
    }

    @Test
    fun dieselAuthorizationStatesSuppressInsufficientFeeError() {
        listOf(MDieselStatus.NOT_AUTHORIZED, MDieselStatus.PENDING_PREVIOUS).forEach { status ->
            assertFalse(
                TransferHelpers.hasInsufficientFeeError(
                    tokenBalance = BigInteger.valueOf(100),
                    nativeTokenBalance = BigInteger.ZERO,
                    transferAmount = BigInteger.valueOf(50),
                    fullFee = feeTerms(native = 5),
                    canTransferFullBalance = false,
                    dieselStatus = status
                )
            )
        }
    }

    @Test
    fun fullBalanceTransferDoesNotRequireTransferredAmountAgain() {
        assertFalse(
            TransferHelpers.hasInsufficientFeeError(
                tokenBalance = BigInteger.valueOf(100),
                nativeTokenBalance = BigInteger.valueOf(5),
                transferAmount = BigInteger.valueOf(100),
                fullFee = feeTerms(token = 5, native = 5),
                canTransferFullBalance = true,
                dieselStatus = null
            )
        )
    }

    private fun feeTerms(token: Long? = null, native: Long? = null, stars: Long? = null) =
        MFeeTerms(
            token = token?.let(BigInteger::valueOf),
            native = native?.let(BigInteger::valueOf),
            stars = stars?.let(BigInteger::valueOf)
        )

    private fun explainedFee(
        isGasless: Boolean = false,
        canTransferFullBalance: Boolean = false,
        token: Long? = null,
        native: Long? = null,
        stars: Long? = null,
        nativeSum: Long? = null
    ) = MExplainedTransferFee(
        isGasless = isGasless,
        fullFee = MFee(
            precision = MFeePrecision.EXACT,
            terms = feeTerms(token, native, stars),
            nativeSum = nativeSum?.let(BigInteger::valueOf)
        ),
        realFee = null,
        canTransferFullBalance = canTransferFullBalance
    )

    private fun diesel(status: MDieselStatus, amount: Long) = MTransferDiesel(
        status = status,
        realFee = null,
        remainingFee = null,
        nativeAmount = null,
        amount = BigInteger.valueOf(amount)
    )
}
