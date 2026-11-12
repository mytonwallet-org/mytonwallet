package org.mytonwallet.app_air.walletcore.stores

import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain

class NftFullLoadTest {
    @Test
    fun completionWithoutAnAppliedInventoryCannotCertifyASnapshot() {
        val account = UUID.randomUUID().toString()
        NftStore.recordFullLoad(account, MBlockchain.ton, null, false, "complete")
        val snapshot = NftStore.getInventorySnapshot(account)
        assertNull(snapshot.nfts)
        assertFalse(snapshot.isComplete)
    }

    @Test
    fun explicitFreshnessOverridesStreamFlagsAndKeepsAccountsAndChainsIsolated() {
        val account = UUID.randomUUID().toString()
        val other = UUID.randomUUID().toString()
        NftStore.recordFullLoad(other, MBlockchain.ton, null, false, "complete")
        NftStore.recordFullLoad(account, MBlockchain.ethereum, null, false, "complete")
        for (status in listOf("loading", "cached", "error", "future-status")) {
            NftStore.recordFullLoad(account, MBlockchain.ton, null, false, "complete")
            assertEquals(setOf(MBlockchain.ton, MBlockchain.ethereum), NftStore.getFullyLoadedChains(account))
            NftStore.recordFullLoad(account, MBlockchain.ton, false, true, status)
            assertEquals(setOf(MBlockchain.ethereum), NftStore.getFullyLoadedChains(account))
            assertEquals(setOf(MBlockchain.ton), NftStore.getFullyLoadedChains(other))
        }
    }

    @Test
    fun legacyFullLoadsAndStatusFreeDeltasRemainSupported() {
        val account = UUID.randomUUID().toString()
        NftStore.recordFullLoad(account, MBlockchain.ton, true, false)
        assertTrue(NftStore.getFullyLoadedChains(account).isEmpty())
        NftStore.recordFullLoad(account, MBlockchain.ton, false, true)
        assertEquals(setOf(MBlockchain.ton), NftStore.getFullyLoadedChains(account))
        NftStore.recordFullLoad(account, MBlockchain.ton, null, false)
        assertEquals(setOf(MBlockchain.ton), NftStore.getFullyLoadedChains(account))
        NftStore.recordFullLoad(account, MBlockchain.ton, true, false)
        assertTrue(NftStore.getFullyLoadedChains(account).isEmpty())
    }
}
