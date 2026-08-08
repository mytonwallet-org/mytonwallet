package org.mytonwallet.app_air.walletcore.debug

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TokenInfoDebugSourceTest {

    @Test
    fun providesExpectedMockShapes() {
        val completeData = TokenInfoDebugSource.COMPLETE_DATA.mockTokenInfo
        val localizedDescription =
            TokenInfoDebugSource.LOCALIZED_DESCRIPTION.mockTokenInfo
        val longDescriptionPartialData =
            TokenInfoDebugSource.LONG_DESCRIPTION_PARTIAL_DATA.mockTokenInfo
        val missingDescription = TokenInfoDebugSource.MISSING_DESCRIPTION.mockTokenInfo

        assertEquals(7_580_000_000.0, completeData?.marketCap)
        assertEquals(3, completeData?.links?.size)
        assertEquals("https://docs.ton.org", completeData?.docsUrl)
        assertEquals(
            "https://github.com/ton-blockchain/ton",
            completeData?.sourceCodeUrl
        )
        assertEquals(
            localizedDescription?.localizedDescriptionText,
            localizedDescription?.displayDescription
        )
        assertEquals(
            completeData?.displayDescription,
            localizedDescription?.originalDescriptionText
        )
        assertNull(longDescriptionPartialData?.marketCap)
        assertEquals(
            5,
            longDescriptionPartialData?.let {
                it.links.orEmpty().size +
                    it.aggregatorLinks.orEmpty().size +
                    listOfNotNull(it.docsUrl, it.sourceCodeUrl).size
            }
        )
        assertNull(longDescriptionPartialData?.aggregatorLinks)
        assertNull(missingDescription?.displayDescription)
    }

    @Test
    fun defaultsUnknownStoredSourceToRealApi() {
        assertEquals(
            TokenInfoDebugSource.REAL_API,
            TokenInfoDebugSource.fromStorageValue("unknown")
        )
    }

    @Test
    fun mapsLegacyPresetNamesToClearerSources() {
        assertEquals(
            TokenInfoDebugSource.COMPLETE_DATA,
            TokenInfoDebugSource.fromStorageValue("design")
        )
        assertEquals(
            TokenInfoDebugSource.LONG_DESCRIPTION_PARTIAL_DATA,
            TokenInfoDebugSource.fromStorageValue("longSparse")
        )
    }
}
