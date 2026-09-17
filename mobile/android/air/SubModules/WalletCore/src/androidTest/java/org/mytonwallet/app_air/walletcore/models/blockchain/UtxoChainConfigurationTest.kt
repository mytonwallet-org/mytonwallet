package org.mytonwallet.app_air.walletcore.models.blockchain

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.BITCOINCASH_SLUG
import org.mytonwallet.app_air.walletcore.BITCOIN_SLUG
import org.mytonwallet.app_air.walletcore.DOGECOIN_SLUG
import org.mytonwallet.app_air.walletcore.LITECOIN_SLUG
import org.mytonwallet.app_air.walletcore.stores.DefaultTokens

@RunWith(AndroidJUnit4::class)
class UtxoChainConfigurationTest {

    @Before
    fun setUp() {
        ApplicationContextHolder.update(
            InstrumentationRegistry.getInstrumentation().targetContext
        )
    }

    @Test
    fun chainsUseCanonicalNamesAndIosWebDisplayOrder() {
        val supportedChains = MBlockchain.entries
            .filter { it.isSupported }
            .map { it.name }

        assertEquals(
            listOf(
                "bitcoin",
                "ethereum",
                "solana",
                "hyperliquid",
                "ton",
                "tron",
                "bnb",
                "base",
                "robinhood",
                "arc",
                "monad",
                "arbitrum",
                "polygon",
                "avalanche",
                "dogecoin",
                "litecoin",
                "bitcoincash"
            ),
            supportedChains
        )
        assertSame(MBlockchain.bitcoin, MBlockchain.valueOfOrNull("bitcoin"))
        assertSame(MBlockchain.litecoin, MBlockchain.valueOfOrNull("litecoin"))
        assertSame(MBlockchain.bitcoincash, MBlockchain.valueOfOrNull("bitcoincash"))
        assertSame(MBlockchain.dogecoin, MBlockchain.valueOfOrNull("dogecoin"))
        assertNull(MBlockchain.valueOfOrNull("bitcoin_cash"))
        assertNull(MBlockchain.valueOfOrNull("doge"))
    }

    @Test
    fun chainsExposeUtxoWalletConfiguration() {
        val expectations = listOf(
            ChainExpectation(
                chain = MBlockchain.bitcoin,
                nativeSlug = BITCOIN_SLUG,
                derivationPath = "m/86'/0'/0'/0/{index}",
                symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_bitcoin,
                symbolIconPadded =
                    org.mytonwallet.app_air.icons.R.drawable.ic_symbol_bitcoin_15
            ),
            ChainExpectation(
                chain = MBlockchain.litecoin,
                nativeSlug = LITECOIN_SLUG,
                derivationPath = "m/84'/2'/0'/0/{index}",
                symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_litecoin,
                symbolIconPadded =
                    org.mytonwallet.app_air.icons.R.drawable.ic_symbol_litecoin_15
            ),
            ChainExpectation(
                chain = MBlockchain.bitcoincash,
                nativeSlug = BITCOINCASH_SLUG,
                derivationPath = "m/44'/145'/0'/0/{index}",
                symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_bitcoincash,
                symbolIconPadded =
                    org.mytonwallet.app_air.icons.R.drawable.ic_symbol_bitcoincash_15
            ),
            ChainExpectation(
                chain = MBlockchain.dogecoin,
                nativeSlug = DOGECOIN_SLUG,
                derivationPath = "m/44'/3'/0'/0/{index}",
                symbolIcon = org.mytonwallet.app_air.icons.R.drawable.ic_symbol_dogecoin,
                symbolIconPadded =
                    org.mytonwallet.app_air.icons.R.drawable.ic_symbol_dogecoin_15
            )
        )

        expectations.forEach { expectation ->
            val chain = expectation.chain
            assertTrue(chain.isSupported)
            assertEquals(expectation.nativeSlug, chain.nativeSlug)
            assertEquals(expectation.derivationPath, chain.config?.defaultDerivationPath)
            assertEquals(expectation.symbolIcon, chain.symbolIcon)
            assertEquals(expectation.symbolIconPadded, chain.symbolIconPadded)
            assertEquals(MultiWalletSupport.PATH, chain.multiWalletSupport)
            assertTrue(chain.isValidAddress(chain.feeCheckAddress.orEmpty()))
            assertFalse(chain.isValidAddress("not-an-address"))
            assertEquals("transaction-id", chain.idToTxHash("transaction-id"))
            assertEquals("transaction-id", chain.idToTxHash("transaction-id::local"))
        }
    }

    @Test
    fun explorersBuildMainnetAndTestnetUrls() {
        val expectations = listOf(
            ExplorerExpectation(
                explorer = MBlockchainExplorer.MEMPOOL,
                mainnetBaseUrl = "https://mempool.space",
                testnetBaseUrl = "https://mempool.space/testnet",
                transactionPath = "tx"
            ),
            ExplorerExpectation(
                explorer = MBlockchainExplorer.BLOCKCHAIR_LITECOIN,
                mainnetBaseUrl = "https://blockchair.com/litecoin",
                testnetBaseUrl = "https://blockchair.com/litecoin/testnet",
                transactionPath = "transaction"
            ),
            ExplorerExpectation(
                explorer = MBlockchainExplorer.BLOCKCHAIR_BITCOINCASH,
                mainnetBaseUrl = "https://blockchair.com/bitcoin-cash",
                testnetBaseUrl = "https://blockchair.com/bitcoin-cash/testnet",
                transactionPath = "transaction"
            ),
            ExplorerExpectation(
                explorer = MBlockchainExplorer.BLOCKCHAIR_DOGECOIN,
                mainnetBaseUrl = "https://blockchair.com/dogecoin",
                testnetBaseUrl = "https://blockchair.com/dogecoin/testnet",
                transactionPath = "transaction"
            )
        )

        expectations.forEach { expectation ->
            val explorer = expectation.explorer
            assertEquals(
                "${expectation.mainnetBaseUrl}/${expectation.transactionPath}/transaction-id",
                explorer.transactionUrl(MBlockchainNetwork.MAINNET, "transaction-id")
            )
            assertEquals(
                "${expectation.testnetBaseUrl}/${expectation.transactionPath}/transaction-id",
                explorer.transactionUrl(MBlockchainNetwork.TESTNET, "transaction-id")
            )
            assertEquals(
                "${expectation.mainnetBaseUrl}/address/wallet-address",
                explorer.addressUrl(MBlockchainNetwork.MAINNET, "wallet-address")
            )
        }
    }

    @Test
    fun defaultTokensMatchNativeUtxoAssets() {
        val expectations = listOf(
            TokenExpectation(BITCOIN_SLUG, "Bitcoin", "BTC", "bitcoin", "bitcoin"),
            TokenExpectation(LITECOIN_SLUG, "Litecoin", "LTC", "litecoin", "litecoin"),
            TokenExpectation(
                BITCOINCASH_SLUG,
                "Bitcoin Cash",
                "BCH",
                "bitcoincash",
                "bitcoin-cash"
            ),
            TokenExpectation(DOGECOIN_SLUG, "Dogecoin", "DOGE", "dogecoin", "dogecoin")
        )

        expectations.forEach { expectation ->
            val token = DefaultTokens.tokens.getValue(expectation.slug)
            assertEquals(expectation.name, token.name)
            assertEquals(expectation.symbol, token.symbol)
            assertEquals(8, token.decimals)
            assertEquals(expectation.chain, token.chain)
            assertEquals(expectation.cmcSlug, token.cmcSlug)
        }
    }

    private data class ChainExpectation(
        val chain: MBlockchain,
        val nativeSlug: String,
        val derivationPath: String,
        val symbolIcon: Int,
        val symbolIconPadded: Int
    )

    private data class ExplorerExpectation(
        val explorer: MBlockchainExplorer,
        val mainnetBaseUrl: String,
        val testnetBaseUrl: String,
        val transactionPath: String
    )

    private data class TokenExpectation(
        val slug: String,
        val name: String,
        val symbol: String,
        val chain: String,
        val cmcSlug: String
    )
}
