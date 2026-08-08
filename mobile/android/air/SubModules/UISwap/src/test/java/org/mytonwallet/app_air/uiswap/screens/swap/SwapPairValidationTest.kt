package org.mytonwallet.app_air.uiswap.screens.swap

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapInputState
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

class SwapPairValidationTest {

    private val sendingToken = token("send")
    private val receivingToken = token("receive")

    @Test
    fun unavailableBuyPairClearsImplicitSendingToken() {
        val state = inputState().clearingInvalidPair(receivingToken.slug)

        assertNull(state.tokenToSend)
        assertNull(state.tokenToSendMaxAmount)
        assertEquals(receivingToken, state.tokenToReceive)
        assertFalse(state.isFromAmountMax)
    }

    @Test
    fun unavailableSourceFirstPairClearsReceivingToken() {
        val state = inputState().clearingInvalidPair(null)

        assertEquals(sendingToken, state.tokenToSend)
        assertEquals("10", state.tokenToSendMaxAmount)
        assertNull(state.tokenToReceive)
    }

    private fun inputState() = SwapInputState(
        tokenToSend = sendingToken,
        tokenToSendMaxAmount = "10",
        tokenToReceive = receivingToken,
        isFromAmountMax = true
    )

    private fun token(slug: String) = object : IApiToken {
        override val slug = slug
        override val decimals = 9
        override val name: String? = slug
        override val symbol: String? = slug
        override val chain: String? = "ton"
        override val tokenAddress: String? = null
        override val image: String? = null
        override val isPopular: Boolean? = null
        override val keywords: List<String>? = null
        override val mBlockchain: MBlockchain? = null
    }
}
