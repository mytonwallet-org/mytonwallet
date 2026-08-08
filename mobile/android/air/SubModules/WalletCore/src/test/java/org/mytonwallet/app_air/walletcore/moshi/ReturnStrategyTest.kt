package org.mytonwallet.app_air.walletcore.moshi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class ReturnStrategyTest {
    @Test
    fun defaultsToBack() {
        assertSame(ReturnStrategy.Back, ReturnStrategy.fromDeeplinkValue(null))
        assertSame(ReturnStrategy.Back, ReturnStrategy.fromDeeplinkValue(""))
        assertSame(ReturnStrategy.Back, ReturnStrategy.fromDeeplinkValue("back"))
    }

    @Test
    fun resolvesNoneAndLegacyEmpty() {
        assertSame(ReturnStrategy.None, ReturnStrategy.fromDeeplinkValue("none"))
        assertSame(ReturnStrategy.Empty, ReturnStrategy.fromDeeplinkValue("empty"))
    }

    @Test
    fun resolvesCustomUrl() {
        assertEquals(
            ReturnStrategy.Url("mydapp://connected"),
            ReturnStrategy.fromDeeplinkValue("mydapp://connected")
        )
    }
}
