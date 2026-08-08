package org.mytonwallet.app_air.walletcore.helpers

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DappDeeplinkReturnTrackerTest {
    @After
    fun tearDown() {
        DappDeeplinkReturnTracker.reset()
    }

    @Test
    fun externalWalletConnectDeeplinkReturnsAfterMatchingConnectRequest() {
        DappDeeplinkReturnTracker.expectWalletConnect(
            "wc:pairing-topic@2?relay-protocol=irn&symKey=key",
            shouldReturn = true
        )

        DappDeeplinkReturnTracker.bindWalletConnectRequest("pairing-topic", "promise")

        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
    }

    @Test
    fun inAppBrowserWalletConnectDeeplinkDoesNotReturnFromWalletTask() {
        DappDeeplinkReturnTracker.expectWalletConnect(
            "wc:pairing-topic@2?relay-protocol=irn&symKey=key",
            shouldReturn = false
        )

        DappDeeplinkReturnTracker.bindWalletConnectRequest("pairing-topic", "promise")

        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
    }

    @Test
    fun unrelatedWalletConnectRequestDoesNotBindPendingDeeplink() {
        DappDeeplinkReturnTracker.expectWalletConnect(
            "wc:pairing-topic@2?relay-protocol=irn&symKey=key",
            shouldReturn = true
        )

        DappDeeplinkReturnTracker.bindWalletConnectRequest("other-topic", "other-promise")
        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("other-promise"))

        DappDeeplinkReturnTracker.bindWalletConnectRequest("pairing-topic", "promise")
        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
    }

    @Test
    fun externalWalletConnectSessionRequestReturnsAfterMatchingCompletion() {
        DappDeeplinkReturnTracker.expectWalletConnectSessionRequest(
            "session-topic",
            shouldReturn = true
        )

        DappDeeplinkReturnTracker.bindWalletConnectSessionRequest(
            "session-topic",
            "promise"
        )

        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
    }

    @Test
    fun walletConnectSessionRequestCanArriveBeforeItsDeeplink() {
        DappDeeplinkReturnTracker.bindWalletConnectSessionRequest(
            "session-topic",
            "promise"
        )

        DappDeeplinkReturnTracker.expectWalletConnectSessionRequest(
            "session-topic",
            shouldReturn = true
        )

        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
    }

    @Test
    fun overlappingWalletConnectSessionRequestsReturnIndependently() {
        DappDeeplinkReturnTracker.expectWalletConnectSessionRequest(
            "session-a",
            shouldReturn = true
        )
        DappDeeplinkReturnTracker.expectWalletConnectSessionRequest(
            "session-b",
            shouldReturn = true
        )

        DappDeeplinkReturnTracker.bindWalletConnectSessionRequest(
            "session-b",
            "promise-b"
        )
        DappDeeplinkReturnTracker.bindWalletConnectSessionRequest(
            "session-a",
            "promise-a"
        )

        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-a"))
        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-b"))
    }

    @Test
    fun overlappingRequestsFromSameWalletConnectSessionAreQueued() {
        DappDeeplinkReturnTracker.expectWalletConnectSessionRequest(
            "session-topic",
            shouldReturn = true
        )
        DappDeeplinkReturnTracker.expectWalletConnectSessionRequest(
            "session-topic",
            shouldReturn = true
        )

        DappDeeplinkReturnTracker.bindWalletConnectSessionRequest(
            "session-topic",
            "promise-a"
        )
        DappDeeplinkReturnTracker.bindWalletConnectSessionRequest(
            "session-topic",
            "promise-b"
        )

        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-b"))
        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-a"))
    }

    @Test
    fun inAppWalletConnectSessionRequestDoesNotReturnFromWalletTask() {
        DappDeeplinkReturnTracker.expectWalletConnectSessionRequest(
            "session-topic",
            shouldReturn = false
        )
        DappDeeplinkReturnTracker.bindWalletConnectSessionRequest(
            "session-topic",
            "promise"
        )

        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
    }

    @Test
    fun completedUnmatchedWalletConnectRequestCannotBindLaterDeeplink() {
        DappDeeplinkReturnTracker.bindWalletConnectSessionRequest(
            "session-topic",
            "promise"
        )

        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
        DappDeeplinkReturnTracker.expectWalletConnectSessionRequest(
            "session-topic",
            shouldReturn = true
        )
        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
    }

    @Test
    fun externalTonConnectBackReturnsAfterMatchingIdentifier() {
        DappDeeplinkReturnTracker.expectTonConnect(
            "dapp-client",
            shouldReturn = true
        )

        DappDeeplinkReturnTracker.bindTonConnectRequest("dapp-client", "promise")

        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
    }

    @Test
    fun unrelatedTonConnectRequestKeepsPendingReturn() {
        DappDeeplinkReturnTracker.expectTonConnect(
            "dapp-client",
            shouldReturn = true
        )

        DappDeeplinkReturnTracker.bindTonConnectRequest("other-client", "other-promise")
        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("other-promise"))

        DappDeeplinkReturnTracker.bindTonConnectRequest("dapp-client", "promise")
        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
    }

    @Test
    fun nonBackTonConnectStrategyLeavesReturnToSdk() {
        DappDeeplinkReturnTracker.expectTonConnect("dapp-client", shouldReturn = false)
        DappDeeplinkReturnTracker.bindTonConnectRequest("dapp-client", "promise")

        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("promise"))
    }

    @Test
    fun nonBackRequestDoesNotClearAnotherPendingReturn() {
        DappDeeplinkReturnTracker.expectTonConnect("client-a", shouldReturn = true)
        DappDeeplinkReturnTracker.expectTonConnect("client-b", shouldReturn = false)

        DappDeeplinkReturnTracker.bindTonConnectRequest("client-a", "promise-a")
        DappDeeplinkReturnTracker.bindTonConnectRequest("client-b", "promise-b")

        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-a"))
        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-b"))
    }

    @Test
    fun overlappingRequestsReturnIndependently() {
        DappDeeplinkReturnTracker.expectTonConnect("client-a", shouldReturn = true)
        DappDeeplinkReturnTracker.bindTonConnectRequest("client-a", "promise-a")

        DappDeeplinkReturnTracker.expectTonConnect("client-b", shouldReturn = true)
        DappDeeplinkReturnTracker.bindTonConnectRequest("client-b", "promise-b")

        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-b"))
        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-a"))
        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-a"))
        assertFalse(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-b"))
    }

    @Test
    fun completionDoesNotClearAnotherPendingRequest() {
        DappDeeplinkReturnTracker.expectTonConnect("client-a", shouldReturn = true)
        DappDeeplinkReturnTracker.bindTonConnectRequest("client-a", "promise-a")

        DappDeeplinkReturnTracker.expectTonConnect("client-b", shouldReturn = true)

        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-a"))

        DappDeeplinkReturnTracker.bindTonConnectRequest("client-b", "promise-b")
        assertTrue(DappDeeplinkReturnTracker.consumeCompletedRequest("promise-b"))
    }

    @Test
    fun pairingTopicRequiresWalletConnectUri() {
        assertEquals(
            "pairing-topic",
            DappDeeplinkReturnTracker.extractPairingTopic(
                "WC:pairing-topic@2?relay-protocol=irn"
            )
        )
        assertEquals(
            null,
            DappDeeplinkReturnTracker.extractPairingTopic(
                "https://example.com/wc?uri=pairing-topic"
            )
        )
        assertEquals(null, DappDeeplinkReturnTracker.extractPairingTopic("wc:@2"))
    }
}
