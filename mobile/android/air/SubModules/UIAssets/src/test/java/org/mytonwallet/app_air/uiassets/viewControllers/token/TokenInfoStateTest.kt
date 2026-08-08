package org.mytonwallet.app_air.uiassets.viewControllers.token

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.MApiTokenDetails

class TokenInfoStateTest {

    @Test
    fun `missing description keeps available metrics expandable`() {
        val info = MApiTokenDetails.TokenInfo(marketCap = 7_580_000_000.0)

        val state = TokenVM.TokenInfoState.resolved(info)

        assertEquals(TokenVM.TokenInfoState.Details(info), state)
    }

    @Test
    fun `links count as expandable public information`() {
        val info = MApiTokenDetails.TokenInfo(
            links = listOf(MApiTokenDetails.Link("https://example.com"))
        )

        val state = TokenVM.TokenInfoState.resolved(info)

        assertEquals(TokenVM.TokenInfoState.Details(info), state)
    }

    @Test
    fun `empty info uses no public information fallback`() {
        val state = TokenVM.TokenInfoState.resolved(MApiTokenDetails.TokenInfo())

        assertEquals(TokenVM.TokenInfoState.Fallback, state)
    }
}
