package org.mytonwallet.app_air.walletcore.helpers

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource

class WindowOpenUrlRoutingContractTest {
    @Test
    fun windowOpenWalletOfframpIsConsumedBeforeDelegate() {
        val handledSources = mutableListOf<String>()

        val mtwDecision = resolveRouting("mtw://offramp?depositWalletAddress=UQAddress") { _, source ->
            handledSources.add(source.toString())
            false
        }
        val gramDecision = resolveRouting("gramwallet://offramp?depositWalletAddress=UQAddress") { _, source ->
            handledSources.add(source.toString())
            false
        }

        assertEquals("CONSUME", mtwDecision)
        assertEquals("CONSUME", gramDecision)
        assertEquals(emptyList<String>(), handledSources)
    }

    @Test
    fun windowOpenCustomSchemeDeeplinksCarryInAppBrowserSource() {
        val handled = mutableListOf<Pair<String, String>>()
        val url = "ton://transfer/UQAddress?amount=1"

        val decision = resolveRouting(url) { deeplink, source ->
            handled.add(deeplink to source.toString())
            true
        }

        assertEquals("CONSUME", decision)
        assertEquals(listOf(url to "IN_APP_BROWSER"), handled)
    }

    @Test
    fun windowOpenUnknownUrlFallsBackToLoadUrlWhenDelegateDenies() {
        val decision = resolveRouting("unknown-scheme://example") { _, _ ->
            false
        }

        assertEquals("LOAD_URL", decision)
    }

    private fun resolveRouting(
        url: String,
        handleDeeplink: (String, DeeplinkOpenSource) -> Boolean
    ): String {
        return WindowOpenUrlRoutingDecision.resolve(url, handleDeeplink).toString()
    }
}
