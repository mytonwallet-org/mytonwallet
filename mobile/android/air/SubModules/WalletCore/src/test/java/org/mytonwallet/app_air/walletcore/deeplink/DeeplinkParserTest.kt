package org.mytonwallet.app_air.walletcore.deeplink

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DeeplinkParserTest {
    @Test
    fun detectsWalletConnectSessionRequestIdentity() {
        assertTrue(
            DeeplinkParser.isWalletConnectSessionRequest(setOf("requestId", "sessionTopic"))
        )
        assertTrue(
            DeeplinkParser.isWalletConnectSessionRequest(setOf("topic", "wc_ev"))
        )
        assertTrue(
            DeeplinkParser.isWalletConnectSessionRequest(setOf("topic", "message"))
        )
    }

    @Test
    fun rejectsIncompleteWalletConnectSessionRequestIdentity() {
        assertFalse(DeeplinkParser.isWalletConnectSessionRequest(setOf("requestId")))
        assertFalse(DeeplinkParser.isWalletConnectSessionRequest(setOf("sessionTopic")))
        assertFalse(DeeplinkParser.isWalletConnectSessionRequest(setOf("topic")))
        assertFalse(DeeplinkParser.isWalletConnectSessionRequest(setOf("message")))
        assertFalse(DeeplinkParser.isWalletConnectSessionRequest(setOf("uri")))
    }

    @Test
    fun recognizesMintCardCommands() {
        assertTrue(DeeplinkParser.mintCardDeeplink("nft-card") is Deeplink.MintCard)
        assertTrue(DeeplinkParser.mintCardDeeplink("mint") is Deeplink.MintCard)
        assertNull(DeeplinkParser.mintCardDeeplink("card"))
    }
}
