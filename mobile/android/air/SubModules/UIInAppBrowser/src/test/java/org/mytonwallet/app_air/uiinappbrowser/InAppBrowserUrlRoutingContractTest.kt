package org.mytonwallet.app_air.uiinappbrowser

import org.junit.Assert.assertEquals
import org.junit.Test
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource

class InAppBrowserUrlRoutingContractTest {
    @Test
    fun browserWalletOfframpDeeplinksAreConsumedBeforeDelegate() {
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
    fun browserCustomSchemeDeeplinksCarryInAppBrowserSource() {
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
    fun browserHttpIsConsumedAndHttpsStaysInWebView() {
        val httpDecision = resolveRouting("http://example.com") { _, _ ->
            throw AssertionError("Http navigation should not route as a deeplink")
        }
        val httpsDecision = resolveRouting("https://example.com") { _, _ ->
            throw AssertionError("Https navigation should not route as a deeplink")
        }

        assertEquals("CONSUME", httpDecision)
        assertEquals("ALLOW_WEB_VIEW", httpsDecision)
    }

    @Test
    fun browserSystemSchemesStaySystemIntentDecisions() {
        assertEquals(
            "OPEN_DIAL_INTENT",
            resolveRouting("tel:+123") { _, _ -> false }
        )
        assertEquals(
            "OPEN_SMS_INTENT",
            resolveRouting("sms:+123?body=test") { _, _ -> false }
        )
        assertEquals(
            "OPEN_SYSTEM_VIEW_INTENT",
            resolveRouting("mailto:test@example.com") { _, _ -> false }
        )
        assertEquals(
            "OPEN_SYSTEM_VIEW_INTENT",
            resolveRouting("geo:0,0") { _, _ -> false }
        )
    }

    private fun resolveRouting(
        url: String,
        handleDeeplink: (String, DeeplinkOpenSource) -> Boolean
    ): String {
        return InAppBrowserUrlRoutingDecision.resolve(url, handleDeeplink).toString()
    }
}
