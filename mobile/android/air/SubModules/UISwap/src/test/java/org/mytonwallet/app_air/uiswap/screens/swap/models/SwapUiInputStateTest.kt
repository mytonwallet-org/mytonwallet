package org.mytonwallet.app_air.uiswap.screens.swap.models

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset

class SwapUiInputStateTest {
    @Test
    fun crossChainDexQuoteUsesDexDetailsWithoutEnablingBuyAmount() {
        val source = MApiSwapAsset(slug = "base", chain = "base", decimals = 18)
        val destination = MApiSwapAsset(slug = "arbitrum", chain = "arbitrum", decimals = 18)
        val input = SwapInputState(tokenToSend = source, tokenToReceive = destination)
        val wallet = SwapWalletState(
            accountId = "account",
            addressByChain = mapOf(
                "base" to "0xsender",
                "arbitrum" to "0xrecipient"
            ),
            balances = emptyMap(),
            assets = listOf(source, destination)
        )

        val dexState = SwapUiInputState(wallet, input, quotedCex = false)
        assertFalse(dexState.isCex)
        assertFalse(dexState.canSwapByBuyAmount)
        assertTrue(dexState.swapDetailsVisibility == SwapDetailsVisibility.VISIBLE)

        val cexState = SwapUiInputState(wallet, input, quotedCex = true)
        assertTrue(cexState.isCex)
        assertTrue(cexState.swapDetailsVisibility == SwapDetailsVisibility.CEX)
    }

    @Test
    fun maxKeyIgnoresFeeAdjustedAmountButFollowsBalance() {
        val source = MApiSwapAsset(slug = "robinhood", chain = "robinhood", decimals = 18)
        val destination = MApiSwapAsset(slug = "slv", chain = "robinhood", decimals = 18)
        val wallet = SwapWalletState(
            accountId = "account",
            addressByChain = mapOf("robinhood" to "0xsender"),
            balances = mapOf("robinhood" to BigInteger.valueOf(1_000)),
            assets = listOf(source, destination)
        )
        val input = SwapInputState(
            tokenToSend = source,
            tokenToReceive = destination,
            amount = "0.0000000000000009",
            isFromAmountMax = true
        )
        val key = SwapUiInputState(wallet, input).key

        assertEquals(
            key,
            SwapUiInputState(wallet, input.copy(amount = "0.00000000000000091")).key
        )
        assertNotEquals(
            key,
            SwapUiInputState(
                wallet.copy(balances = mapOf("robinhood" to BigInteger.valueOf(2_000))),
                input
            ).key
        )
    }
}
