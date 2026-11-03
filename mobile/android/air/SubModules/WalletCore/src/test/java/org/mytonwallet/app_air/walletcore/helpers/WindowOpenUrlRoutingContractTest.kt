package org.mytonwallet.app_air.walletcore.helpers

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource

class WindowOpenUrlRoutingContractTest {
    @Test
    fun windowOpenWalletOfframpIsConsumedBeforeDelegate() {
        val handledSources = mutableListOf<String>()

        val mtwDecision =
            resolveRouting("mtw://offramp?depositWalletAddress=UQAddress") { _, source ->
                handledSources.add(source.toString())
                false
            }
        val gramDecision =
            resolveRouting("gramwallet://offramp?depositWalletAddress=UQAddress") { _, source ->
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
    fun windowOpenWebUrlLoadsWhenDelegateDenies() {
        assertEquals("LOAD_URL", resolveRouting("https://example.com/page") { _, _ -> false })
        assertEquals("LOAD_URL", resolveRouting("HTTP://example.com") { _, _ -> false })
    }

    @Test
    fun windowOpenNonWebUrlGoesToBrowserRoutingWhenDelegateDenies() {
        assertEquals(
            "OPEN_NON_WEB_URL",
            resolveRouting("unknown-scheme://example") { _, _ -> false }
        )
        assertEquals(
            "OPEN_NON_WEB_URL",
            resolveRouting("mailto:support@example.com") { _, _ -> false }
        )
    }

    @Test
    fun windowOpenJavascriptAndSchemelessUrlsAreIgnoredBeforeDelegate() {
        val handled = mutableListOf<String>()
        val urls = listOf(
            "javascript:alert(1)",
            "JavaScript:alert(1)",
            " javascript:alert(1)",
            "\tjavascript:alert(1)",
            "java\nscript:alert(1)",
            "/relative/path",
            ""
        )

        urls.forEach { url ->
            val decision = resolveRouting(url) { deeplink, _ ->
                handled.add(deeplink)
                true
            }
            assertEquals(url, "IGNORE", decision)
        }
        assertEquals(emptyList<String>(), handled)
    }

    private fun resolveRouting(
        url: String,
        handleDeeplink: (String, DeeplinkOpenSource) -> Boolean
    ): String = WindowOpenUrlRoutingDecision.resolve(url, handleDeeplink).toString()
}
