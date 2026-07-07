package org.mytonwallet.app_air.walletcontext.helpers

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class InAppBrowserDeeplinkHelpersTest {
    @Test
    fun walletOfframpSelfDeeplinksAreRecognized() {
        assertTrue(
            InAppBrowserDeeplinkHelpers.checkIsInAppBrowserOfframpSelfDeeplink(
                "mtw://offramp?depositWalletAddress=UQAddress"
            )
        )
        assertTrue(
            InAppBrowserDeeplinkHelpers.checkIsInAppBrowserOfframpSelfDeeplink(
                "gramwallet://offramp?depositWalletAddress=UQAddress"
            )
        )
    }

    @Test
    fun nonOfframpWalletLinksAreIgnored() {
        assertFalse(
            InAppBrowserDeeplinkHelpers.checkIsInAppBrowserOfframpSelfDeeplink(
                "mtw://transfer/UQAddress"
            )
        )
        assertFalse(
            InAppBrowserDeeplinkHelpers.checkIsInAppBrowserOfframpSelfDeeplink(
                "gramwallet://receive"
            )
        )
    }

    @Test
    fun invalidUrlsAreIgnored() {
        assertFalse(InAppBrowserDeeplinkHelpers.checkIsInAppBrowserOfframpSelfDeeplink("not a uri"))
        assertFalse(InAppBrowserDeeplinkHelpers.checkIsInAppBrowserOfframpSelfDeeplink("mtw:offramp"))
    }

    @Test
    fun matchingIgnoresCase() {
        assertTrue(
            InAppBrowserDeeplinkHelpers.checkIsInAppBrowserOfframpSelfDeeplink(
                "MTW://OFFRAMP?depositWalletAddress=UQAddress"
            )
        )
    }
}
