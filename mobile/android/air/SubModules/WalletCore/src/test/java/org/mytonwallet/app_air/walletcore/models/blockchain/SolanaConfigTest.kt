package org.mytonwallet.app_air.walletcore.models.blockchain

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SolanaConfigTest {

    @Test
    fun excludeTronRecipientFromSolana() {
        val address = "TVQ1BBt6WEQ1gcbkLNaJAWumuQrfDo1MgW"

        assertTrue(MBlockchain.tron.isValidAddress(address))
        assertFalse(MBlockchain.solana.isValidAddress(address))
    }

    @Test
    fun acceptSolanaRecipientsWithLeadingZeroBytes() {
        val addresses = listOf(
            "35YT7tt9edJbroEKaC3T3XY4cLNWKtVzmyTEfW8LHPEA",
            "JEKNVnkbo3jma5nREBBJCDoXFVeKkD56V3xKrvRmWxFG",
            "11111111QLbz7JHiBTspS962RLKV8GndWFwiEaqKL",
            "11111111111111111111111111111111"
        )

        for (address in addresses) {
            assertTrue(address, MBlockchain.solana.isValidAddress(address))
        }
    }
}
