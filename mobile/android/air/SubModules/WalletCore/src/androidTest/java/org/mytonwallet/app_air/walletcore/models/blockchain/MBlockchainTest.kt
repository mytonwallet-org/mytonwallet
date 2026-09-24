package org.mytonwallet.app_air.walletcore.models.blockchain

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MBlockchainTest {

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
                MBlockchain.dogecoin,
                MBlockchain.litecoin,
                MBlockchain.bitcoincash
            ),
            supportedChains
        )
    }
}
