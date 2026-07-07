package org.mytonwallet.app_air.walletcore.helpers

import org.junit.Assert.assertEquals
import org.junit.Test

class DappOriginContractTest {
    @Test
    fun liveWebViewUrlReplacesInitialOriginAfterNavigation() {
        val origin = resolveDappOrigin(
            "https://trusted.example",
            "https://attacker.example/swap?session=secret#confirm"
        )

        assertEquals("https://attacker.example", origin)
    }

    @Test
    fun liveWebViewUrlKeepsOnlySchemeAndHost() {
        val origin = resolveDappOrigin(
            "https://trusted.example",
            "http://127.0.0.1:8765/path?query=value#hash"
        )

        assertEquals("http://127.0.0.1", origin)
    }

    @Test
    fun invalidLiveWebViewUrlsFallBackToInitialOrigin() {
        val initialOrigin = "https://trusted.example"

        assertEquals(initialOrigin, resolveDappOrigin(initialOrigin, null))
        assertEquals(initialOrigin, resolveDappOrigin(initialOrigin, ""))
        assertEquals(initialOrigin, resolveDappOrigin(initialOrigin, "about:blank"))
        assertEquals(initialOrigin, resolveDappOrigin(initialOrigin, "file:///android_asset/js/index.html"))
        assertEquals(initialOrigin, resolveDappOrigin(initialOrigin, "not a url"))
    }
}
