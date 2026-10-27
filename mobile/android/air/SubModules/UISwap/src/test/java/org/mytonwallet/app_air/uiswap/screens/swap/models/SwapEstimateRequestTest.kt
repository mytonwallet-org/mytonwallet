package org.mytonwallet.app_air.uiswap.screens.swap.models

import java.math.BigInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset

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

    @Test
    fun supportedCrossChainPairUsesUnifiedQuoteWithDestinationAddress() {
        val source = MApiSwapAsset(slug = "base", chain = "base", decimals = 18, symbol = "ETH")
        val destination =
            MApiSwapAsset(slug = "arbitrum", chain = "arbitrum", decimals = 18, symbol = "ETH")
        val wallet = SwapWalletState(
            accountId = "account",
            addressByChain = mapOf("base" to "0xsender", "arbitrum" to "0xrecipient"),
            balances = mapOf("base" to BigInteger("1000000000000000000")),
            assets = listOf(source, destination)
        )
        val request = requireNotNull(
            SwapEstimateRequest.create(
                key = "base-to-arbitrum", wallet = wallet,
                tokenToSend = source, tokenToReceive = destination,
                nativeTokenToSend = source, nativeTokenToSendBalance = "1",
                amount = BigInteger("1000000000000000000"), slippage = 1f,
                reverse = false, isFromAmountMax = true, prevEst = null
            )
        )

        assertTrue(request.usesUnifiedQuote)
        assertEquals("0xrecipient", request.estimateRequestDex.toAddress)
        assertEquals(true, request.estimateRequestDex.isFromAmountMax)
    }

    @Test
    fun externalDestinationKeepsCexQuoteFlow() {
        val source = MApiSwapAsset(slug = "base", chain = "base", decimals = 18)
        val destination = MApiSwapAsset(slug = "toncoin", chain = "ton", decimals = 9)
        val request = requireNotNull(
            SwapEstimateRequest.create(
                key = "external",
                wallet = SwapWalletState(
                    accountId = "account",
                    addressByChain = mapOf("base" to "0xsender"),
                    balances = emptyMap(),
                    assets = listOf(source)
                ),
                tokenToSend = source, tokenToReceive = destination,
                nativeTokenToSend = source, nativeTokenToSendBalance = "0",
                amount = BigInteger.ONE, slippage = 1f,
                reverse = false, isFromAmountMax = false, prevEst = null
            )
        )

        assertFalse(request.usesUnifiedQuote)
    }

    @Test
    fun supportedNonEvmCrossChainPairKeepsCexQuoteFlow() {
        val source = MApiSwapAsset(slug = "toncoin", chain = "ton", decimals = 9)
        val destination = MApiSwapAsset(slug = "base", chain = "base", decimals = 18)
        val request = requireNotNull(
            SwapEstimateRequest.create(
                key = "ton-to-base",
                wallet = SwapWalletState(
                    accountId = "account",
                    addressByChain = mapOf("ton" to "ton-sender", "base" to "0xrecipient"),
                    balances = emptyMap(),
                    assets = listOf(source, destination)
                ),
                tokenToSend = source, tokenToReceive = destination,
                nativeTokenToSend = source, nativeTokenToSendBalance = "0",
                amount = BigInteger.ONE, slippage = 1f,
                reverse = false, isFromAmountMax = false, prevEst = null
            )
        )

        assertFalse(request.usesUnifiedQuote)
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
