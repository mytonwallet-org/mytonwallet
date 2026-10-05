package org.mytonwallet.app_air.walletcore.deeplink

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder

@RunWith(AndroidJUnit4::class)
class WalletConnectDeeplinkTest {
    private val wrapperSchemes = listOf("mw", "mywallet-wc", "gramwallet-wc")
    private val requestLink = "wc:topic@2?relay-protocol=irn&symKey=test-key"

    @Before
    fun setup() {
        ApplicationContextHolder.update(InstrumentationRegistry.getInstrumentation().targetContext)
    }

    @Test
    fun rejectsOpaqueWalletConnectWrappersWithoutRequestLink() {
        for (scheme in wrapperSchemes) {
            for (suffix in listOf("wc", "wc?foo=bar", "wc?uri")) {
                val url = "$scheme:$suffix"
                assertNull(url, DeeplinkParser.parse(Uri.parse(url)))
            }
        }
    }

    @Test
    fun preservesRawAndWrappedWalletConnectLinks() {
        val urls = listOf(requestLink) + wrapperSchemes.flatMap {
            listOf(
                "$it://wc?uri=${Uri.encode(requestLink)}",
                "$it:wc?uri=${Uri.encode(requestLink)}"
            )
        }
        for (url in urls) {
            val deeplink = DeeplinkParser.parse(Uri.parse(url)) as? Deeplink.WalletConnect
            assertEquals(url, requestLink, deeplink?.requestUri?.toString())
        }
    }
}
