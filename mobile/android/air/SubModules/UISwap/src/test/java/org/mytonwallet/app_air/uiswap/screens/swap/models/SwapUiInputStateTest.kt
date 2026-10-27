package org.mytonwallet.app_air.uiswap.screens.swap.models

import org.junit.Assert.assertFalse
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
}
