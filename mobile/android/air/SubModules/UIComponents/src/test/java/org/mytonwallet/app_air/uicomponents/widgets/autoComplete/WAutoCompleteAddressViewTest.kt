package org.mytonwallet.app_air.uicomponents.widgets.autoComplete

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WAutoCompleteAddressViewTest {

    @Test
    fun matchesDomainCaseInsensitivelyAtAnyPosition() {
        assertTrue(
            doesAddressItemFitSearch(
                address = "UQ123",
                domain = "Alice.Wallet.ton",
                name = "Main Wallet",
                query = "WALLET"
            )
        )
    }

    @Test
    fun rejectsQueryMissingFromAddressDomainAndName() {
        assertFalse(
            doesAddressItemFitSearch(
                address = "UQ123",
                domain = "alice.ton",
                name = "Main Wallet",
                query = "bob"
            )
        )
    }
}
