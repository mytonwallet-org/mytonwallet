package org.mytonwallet.app_air.uiswap.screens.swap.helpers

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.models.SwapType
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.explainedFee.MFeeTerms

class SwapHelpersTest {

    @Test
    fun missingReceivingTokenUsesOnChainFlow() {
        assertEquals(
            SwapType.ON_CHAIN,
            SwapHelpers.swapType(
                tokenToSend = token(slug = "toncoin", chain = "ton"),
                tokenToReceive = null,
                walletAddressByChain = emptyMap()
            )
        )
    }

    @Test
    fun missingTokenCannotBeClassifiedAsCex() {
        assertEquals(false, SwapHelpers.isCex(null, token(slug = "toncoin", chain = "ton")))
        assertEquals(false, SwapHelpers.isCex(token(slug = "toncoin", chain = "ton"), null))
    }

    @Test
    fun missingSendingTokenHasZeroMaximum() {
        assertEquals(
            BigInteger.ZERO,
            SwapHelpers.calcSwapMaxBalance(null, null, null, null, null)
        )
    }

    @Test
    fun missingBalanceHasZeroMaximum() {
        assertEquals(
            BigInteger.ZERO,
            SwapHelpers.calcSwapMaxBalance(
                tokenToSend = token(slug = "toncoin", chain = "ton"),
                tokenToReceive = null,
                addressByChain = mapOf("ton" to "wallet-ton"),
                balances = emptyMap(),
                lastSwapEstimateResponse = null
            )
        )
    }

    @Test
    fun onChainMaximumDoesNotReserveDefaultSwapFee() {
        val maxAmount = SwapHelpers.calcSwapMaxBalance(
            tokenToSend = token(slug = "toncoin", chain = "ton"),
            tokenToReceive = null,
            addressByChain = mapOf("ton" to "wallet-ton"),
            balances = mapOf("toncoin" to BigInteger("1000000000")),
            lastSwapEstimateResponse = null
        )

        assertEquals(BigInteger("1000000000"), maxAmount)
    }

    @Test
    fun crossChainFromWalletKeepsAvailableBalanceWithoutEstimate() {
        val maxAmount = SwapHelpers.calcSwapMaxBalance(
            tokenToSend = token(slug = "toncoin", chain = "ton"),
            tokenToReceive = token(slug = "trx", chain = "tron"),
            addressByChain = mapOf("ton" to "wallet-ton"),
            balances = mapOf("toncoin" to BigInteger.valueOf(100)),
            lastSwapEstimateResponse = null
        )

        assertEquals(BigInteger.valueOf(100), maxAmount)
    }

    @Test
    fun crossChainToWalletBlocksMaximumWithoutFallback() {
        val maxAmount = SwapHelpers.calcSwapMaxBalance(
            tokenToSend = token(slug = "trx", chain = "tron"),
            tokenToReceive = token(slug = "toncoin", chain = "ton"),
            addressByChain = mapOf("ton" to "wallet-ton"),
            balances = mapOf("trx" to BigInteger.valueOf(100)),
            lastSwapEstimateResponse = null
        )

        assertEquals(BigInteger.ZERO, maxAmount)
    }

    @Test
    fun crossChainToWalletFallbackUsesAvailableBalance() {
        val maxAmount = SwapHelpers.calcSwapMaxBalance(
            tokenToSend = token(slug = "trx", chain = "tron"),
            tokenToReceive = token(slug = "toncoin", chain = "ton"),
            addressByChain = mapOf("ton" to "wallet-ton"),
            balances = mapOf("trx" to BigInteger.valueOf(100)),
            lastSwapEstimateResponse = null,
            fallbackToMax = true
        )

        assertEquals(BigInteger.valueOf(100), maxAmount)
    }

    @Test
    fun backendMaximumTakesPriorityOverLocalRules() {
        val maxAmount = calcFromInputs(
            swapType = SwapType.CROSS_CHAIN_TO_WALLET,
            tokenBalance = 100,
            networkTerms = feeTerms(token = 10, native = 20),
            maxAmountFromBackend = BigInteger.valueOf(77)
        )

        assertEquals(BigInteger.valueOf(77), maxAmount)
    }

    @Test
    fun nativeMaximumSubtractsTokenAndNativeNetworkFees() {
        val maxAmount = calcFromInputs(
            tokenBalance = 100,
            isNativeToken = true,
            networkTerms = feeTerms(token = 10, native = 20)
        )

        assertEquals(BigInteger.valueOf(70), maxAmount)
    }

    @Test
    fun nonNativeMaximumSubtractsOnlyTokenNetworkFee() {
        val maxAmount = calcFromInputs(
            tokenBalance = 100,
            networkTerms = feeTerms(token = 10, native = 20)
        )

        assertEquals(BigInteger.valueOf(90), maxAmount)
    }

    @Test
    fun cexNativeMaximumUsesDraftFeeWhenNetworkTermsAreMissing() {
        val maxAmount = calcFromInputs(
            tokenBalance = 100,
            isNativeToken = true,
            isCex = true,
            cexNativeFee = BigInteger.valueOf(20)
        )

        assertEquals(BigInteger.valueOf(80), maxAmount)
    }

    @Test
    fun feeAdjustedMaximumIsClampedToZero() {
        val maxAmount = calcFromInputs(
            tokenBalance = 5,
            networkTerms = feeTerms(token = 10)
        )

        assertEquals(BigInteger.ZERO, maxAmount)
    }

    @Test
    fun onChainMaximumIncludesDieselFee() {
        val maxAmount = calcFromInputs(
            swapType = SwapType.ON_CHAIN,
            tokenBalance = 5,
            networkTerms = feeTerms(token = 1)
        )

        assertEquals(BigInteger.valueOf(5), maxAmount)
    }

    @Test
    fun fallbackRestoresBalanceWhenNonCexFeesConsumeIt() {
        val maxAmount = calcFromInputs(
            tokenBalance = 5,
            networkTerms = feeTerms(token = 10),
            fallbackToMax = true
        )

        assertEquals(BigInteger.valueOf(5), maxAmount)
    }

    @Test
    fun fallbackDoesNotIgnoreRequiredCexNativeFee() {
        val maxAmount = calcFromInputs(
            tokenBalance = 5,
            isNativeToken = true,
            isCex = true,
            cexNativeFee = BigInteger.TEN,
            fallbackToMax = true
        )

        assertEquals(BigInteger.ZERO, maxAmount)
    }

    private fun calcFromInputs(
        swapType: SwapType = SwapType.CROSS_CHAIN_FROM_WALLET,
        tokenBalance: Long,
        isNativeToken: Boolean = false,
        networkTerms: MFeeTerms? = null,
        isCex: Boolean = false,
        cexNativeFee: BigInteger? = null,
        maxAmountFromBackend: BigInteger? = null,
        fallbackToMax: Boolean = false
    ) = SwapHelpers.calcSwapMaxBalanceFromInputs(
        swapType = swapType,
        tokenBalance = BigInteger.valueOf(tokenBalance),
        isNativeToken = isNativeToken,
        networkTerms = networkTerms,
        isCex = isCex,
        cexNativeFee = cexNativeFee,
        maxAmountFromBackend = maxAmountFromBackend,
        fallbackToMax = fallbackToMax
    )

    private fun feeTerms(token: Long? = null, native: Long? = null) = MFeeTerms(
        token = token?.let(BigInteger::valueOf),
        native = native?.let(BigInteger::valueOf),
        stars = null
    )

    private fun token(slug: String, chain: String) = object : IApiToken {
        override val slug = slug
        override val decimals = 9
        override val name: String? = slug
        override val symbol: String? = slug
        override val chain: String? = chain
        override val tokenAddress: String? = null
        override val image: String? = null
        override val isPopular: Boolean? = null
        override val keywords: List<String>? = null
        override val mBlockchain: MBlockchain? = null
    }
}
