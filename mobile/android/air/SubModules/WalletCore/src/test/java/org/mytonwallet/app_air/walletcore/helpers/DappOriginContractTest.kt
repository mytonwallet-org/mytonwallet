package org.mytonwallet.app_air.walletcore.helpers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mytonwallet.app_air.walletcore.moshi.ApiDappUrlTrustStatus

// Inputs are the `android.net.Uri` scheme, host and port of a WebView message's source origin.
// Expected origins are `window.location.origin` of that page, which bridge responses compare to.
class DappOriginContractTest {
    @Test
    fun subframeMessagesAreRejected() {
        assertNull(resolveDappMessageContext(isMainFrame = false, "https", "site.example", -1))
        assertNull(resolveDappMessageContext(isMainFrame = false, "http", "site.example", -1))
    }

    @Test
    fun httpMainFrameKeepsOriginAsUnknown() {
        assertEquals(
            DappMessageContext("http://site.example", ApiDappUrlTrustStatus.UNKNOWN),
            resolveDappMessageContext(isMainFrame = true, "http", "site.example", -1)
        )
    }

    @Test
    fun httpsMainFrameKeepsNonDefaultPortAsVerified() {
        assertEquals(
            DappMessageContext("https://site.example:8443", ApiDappUrlTrustStatus.VERIFIED),
            resolveDappMessageContext(isMainFrame = true, "https", "site.example", 8443)
        )
    }

    @Test
    fun originMatchesLocationOriginSerialization() {
        assertEquals(
            DappMessageContext("https://site.example", ApiDappUrlTrustStatus.VERIFIED),
            resolveDappMessageContext(isMainFrame = true, "HTTPS", "Site.Example", 443)
        )
        assertEquals(
            DappMessageContext("http://site.example", ApiDappUrlTrustStatus.UNKNOWN),
            resolveDappMessageContext(isMainFrame = true, "http", "site.example", 80)
        )
        assertEquals(
            DappMessageContext("http://localhost:8080", ApiDappUrlTrustStatus.UNKNOWN),
            resolveDappMessageContext(isMainFrame = true, "http", "localhost", 8080)
        )
        assertEquals(
            DappMessageContext("http://[::1]:8080", ApiDappUrlTrustStatus.UNKNOWN),
            resolveDappMessageContext(isMainFrame = true, "http", "[::1]", 8080)
        )
        assertEquals(
            DappMessageContext("https://[::1]", ApiDappUrlTrustStatus.VERIFIED),
            resolveDappMessageContext(isMainFrame = true, "https", "[::1]", -1)
        )
    }

    @Test
    fun underscoreHostIsKept() {
        assertEquals(
            DappMessageContext("https://my_dapp.example.com", ApiDappUrlTrustStatus.VERIFIED),
            resolveDappMessageContext(isMainFrame = true, "https", "my_dapp.example.com", -1)
        )
    }

    @Test
    fun nonWebOriginsAreRejected() {
        // "null"
        assertNull(resolveDappMessageContext(isMainFrame = true, null, null, -1))
        // "file://"
        assertNull(resolveDappMessageContext(isMainFrame = true, "file", "", -1))
        assertNull(resolveDappMessageContext(isMainFrame = true, "file", null, -1))
        // "data:"
        assertNull(resolveDappMessageContext(isMainFrame = true, "data", null, -1))
        // "chrome-extension://abc"
        assertNull(resolveDappMessageContext(isMainFrame = true, "chrome-extension", "abc", -1))
        // "https://"
        assertNull(resolveDappMessageContext(isMainFrame = true, "https", "", -1))
        assertNull(resolveDappMessageContext(isMainFrame = true, "https", null, -1))
    }
}
