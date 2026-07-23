package org.mytonwallet.app_air.walletbasecontext.logger

import org.junit.Assert.assertEquals
import org.junit.Test

class LoggerTest {
    @Test
    fun crashlyticsEventsContainOnlySeverityAndSubsystem() {
        assertEquals(
            "E/Swap",
            Logger.composeCrashlyticsEvent(Logger.LogLevel.ERROR, Logger.LogTag.SWAP)
        )
        assertEquals(
            "W/JSBridge",
            Logger.composeCrashlyticsEvent(
                Logger.LogLevel.WARN,
                Logger.LogTag.JS_WEBVIEW_BRIDGE
            )
        )
    }
}
