package org.mytonwallet.app_air.walletcore.models.blockchain

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder

@RunWith(AndroidJUnit4::class)
class MBlockchainTest {

    @Before
    fun setUp() {
        ApplicationContextHolder.update(
            InstrumentationRegistry.getInstrumentation().targetContext
        )
    }

    @Test
    fun supportedChainsFollowMyTonWalletDisplayOrder() {
        val supportedChains = MBlockchain.entries.filter { it.isSupported }

        assertEquals(
            listOf(
                MBlockchain.bitcoin,
                MBlockchain.ethereum,
                MBlockchain.solana,
                MBlockchain.hyperliquid,
                MBlockchain.ton,
                MBlockchain.tron,
                MBlockchain.bnb,
                MBlockchain.base,
                MBlockchain.arc,
                MBlockchain.robinhood,
                MBlockchain.monad,
                MBlockchain.arbitrum,
                MBlockchain.polygon,
                MBlockchain.avalanche,
                MBlockchain.optimism,
                MBlockchain.zcash,
                MBlockchain.dogecoin,
                MBlockchain.litecoin,
                MBlockchain.bitcoincash
            ),
            supportedChains
        )
    }

    @Test
    fun chainForAddressPrefersStricterRegexOverSolana() {
        assertEquals(MBlockchain.tron, MBlockchain.chainForAddress(TRON_ADDRESS))
        assertEquals(
            MBlockchain.tron,
            MBlockchain.chainForAddress(TRON_ADDRESS, MBlockchain.solana)
        )
        assertEquals(MBlockchain.dogecoin, MBlockchain.chainForAddress(DOGECOIN_ADDRESS))
        assertEquals(MBlockchain.bitcoin, MBlockchain.chainForAddress(BITCOIN_LEGACY_ADDRESS))
    }

    @Test
    fun chainForAddressKeepsPreferredChainSharingAddressFormat() {
        assertEquals(
            MBlockchain.bitcoincash,
            MBlockchain.chainForAddress(BITCOIN_LEGACY_ADDRESS, MBlockchain.bitcoincash)
        )
        assertEquals(MBlockchain.ethereum, MBlockchain.chainForAddress(EVM_ADDRESS))
        assertEquals(MBlockchain.base, MBlockchain.chainForAddress(EVM_ADDRESS, MBlockchain.base))
    }

    private companion object {
        const val TRON_ADDRESS = "TVQ1BBt6WEQ1gcbkLNaJAWumuQrfDo1MgW"
        const val DOGECOIN_ADDRESS = "DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L"
        const val BITCOIN_LEGACY_ADDRESS = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
        const val EVM_ADDRESS = "0x742d35Cc6634C0532925a3b844Bc454e4438f44e"
    }
}
