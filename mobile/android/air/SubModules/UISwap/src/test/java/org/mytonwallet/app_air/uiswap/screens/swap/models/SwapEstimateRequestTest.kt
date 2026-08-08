package org.mytonwallet.app_air.uiswap.screens.swap.models

import java.math.BigInteger
import org.junit.Assert.assertNull
import org.junit.Test
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

class SwapEstimateRequestTest {
    private val wallet = SwapWalletState(
        accountId = "account",
        addressByChain = emptyMap(),
        balances = emptyMap(),
        assets = emptyList()
    )

    @Test
    fun rejectsSendingTokenWithoutKnownBlockchain() {
        val request = createRequest(
            tokenToSend = token(slug = "unknown"),
            nativeTokenToSend = token(slug = "native")
        )

        assertNull(request)
    }

    @Test
    fun rejectsMissingNativeTokenMetadata() {
        val request = createRequest(
            tokenToSend = token(slug = "token", failOnBlockchainAccess = true),
            nativeTokenToSend = null
        )

        assertNull(request)
    }

    private fun createRequest(tokenToSend: IApiToken, nativeTokenToSend: IApiToken?) =
        SwapEstimateRequest.create(
            key = "estimate",
            wallet = wallet,
            tokenToSend = tokenToSend,
            tokenToReceive = token(slug = "receive"),
            nativeTokenToSend = nativeTokenToSend,
            nativeTokenToSendBalance = "0",
            amount = BigInteger.ONE,
            slippage = 0.5f,
            reverse = false,
            isFromAmountMax = false,
            prevEst = null
        )

    private fun token(slug: String, failOnBlockchainAccess: Boolean = false) = object : IApiToken {
        override val slug = slug
        override val decimals = 9
        override val name: String? = slug
        override val symbol: String? = slug
        override val chain: String? = null
        override val tokenAddress: String? = null
        override val image: String? = null
        override val isPopular: Boolean? = null
        override val keywords: List<String>? = null
        override val mBlockchain: MBlockchain?
            get() {
                check(!failOnBlockchainAccess) {
                    "Sending-token blockchain must not be read when native metadata is missing"
                }
                return null
            }
    }
}
