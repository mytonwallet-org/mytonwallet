package org.mytonwallet.app_air.walletcore.models

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

class SwapTypeTest {

    @Test
    fun sameChainEvmPairsUseOnChainFlow() {
        listOf(
            MBlockchain.ethereum,
            MBlockchain.base,
            MBlockchain.bnb,
            MBlockchain.polygon,
            MBlockchain.arbitrum,
            MBlockchain.optimism,
            MBlockchain.monad,
            MBlockchain.avalanche,
            MBlockchain.robinhood,
            MBlockchain.arc
        ).forEach { chain ->
            assertEquals(
                chain.name,
                SwapType.ON_CHAIN,
                SwapType.from(
                    token(slug = "${chain.name}-token-in", chain = chain.name),
                    token(slug = "${chain.name}-token-out", chain = chain.name),
                    walletAddressByChain = mapOf(chain.name to "wallet-evm")
                )
            )
        }
    }

    @Test
    fun unsupportedAndDifferentEvmChainsKeepCrossChainFlow() {
        listOf("hyperliquid" to "hyperliquid", "ethereum" to "base").forEach { (from, to) ->
            assertEquals(
                SwapType.CROSS_CHAIN_FROM_WALLET,
                SwapType.from(
                    token(slug = "$from-token-in", chain = from),
                    token(slug = "$to-token-out", chain = to),
                    walletAddressByChain = mapOf(from to "wallet-evm")
                )
            )
        }
    }

    @Test
    fun walletOwnedSourceChainUsesCrossChainFromWallet() {
        val type = SwapType.from(
            tokenToSend = token(slug = "toncoin", chain = "ton"),
            tokenToReceive = token(slug = "trx", chain = "tron"),
            walletAddressByChain = mapOf("ton" to "wallet-ton")
        )

        assertEquals(SwapType.CROSS_CHAIN_FROM_WALLET, type)
    }

    @Test
    fun externalSourceChainUsesCrossChainToWallet() {
        val type = SwapType.from(
            tokenToSend = token(slug = "trx", chain = "tron"),
            tokenToReceive = token(slug = "toncoin", chain = "ton"),
            walletAddressByChain = mapOf("ton" to "wallet-ton")
        )

        assertEquals(SwapType.CROSS_CHAIN_TO_WALLET, type)
    }

    private fun token(slug: String, chain: String) = object : IApiToken {
        override val slug = slug
        override val decimals = 9
        override val name: String? = slug
        override val symbol: String? = slug
        override val chain: String = chain
        override val tokenAddress: String? = null
        override val image: String? = null
        override val isPopular: Boolean? = null
        override val keywords: List<String>? = null
        override val mBlockchain: MBlockchain = MBlockchain.valueOf(chain)
    }
}
