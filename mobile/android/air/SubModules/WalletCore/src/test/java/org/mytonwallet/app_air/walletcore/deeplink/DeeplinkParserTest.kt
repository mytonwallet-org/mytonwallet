package org.mytonwallet.app_air.walletcore.deeplink

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeeplinkParserTest {
    @Test
    fun parsesWalletConnectSessionRequestIdentity() {
        val deeplink = DeeplinkParser.walletConnectSessionRequest(
            requestId = "42",
            sessionTopic = "session-topic"
        )

        assertTrue(deeplink is Deeplink.WalletConnectSessionRequest)
        deeplink as Deeplink.WalletConnectSessionRequest
        assertEquals("session-topic", deeplink.sessionTopic)
    }

    @Test
    fun rejectsIncompleteWalletConnectSessionRequestIdentity() {
        assertNull(
            DeeplinkParser.walletConnectSessionRequest(
                requestId = "42",
                sessionTopic = null
            )
        )
        assertNull(
            DeeplinkParser.walletConnectSessionRequest(
                requestId = null,
                sessionTopic = "session-topic"
            )
        )
    }
}
