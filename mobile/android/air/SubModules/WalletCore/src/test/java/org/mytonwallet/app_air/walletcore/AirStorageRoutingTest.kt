package org.mytonwallet.app_air.walletcore

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AirStorageRoutingTest {
    @Test
    fun persistentAppKeysUseSecureStorage() {
        val keys = listOf(
            "accounts",
            "stateVersion",
            "currentAccountId",
            "clientId",
            "referrer",
            "langCode",
            "dapps",
            "dappMethods:lastAccountId",
            "windowId",
            "windowState",
            "isTonProxyEnabled",
            "isDeeplinkHookEnabled",
            "sseLastEventId"
        )

        keys.forEach {
            assertTrue(it, JSWebViewBridge.JsWebInterface.usesSecureStorage(it))
        }
    }

    @Test
    fun sdkOnlyKeysDoNotUseSecureStorage() {
        val keys = listOf(
            "agentMessages",
            "agentConversationId",
            "headlessBalanceSnapshots",
            "walletOperationIntents",
            "activeCexSwapReconciliationState",
            "knownTonAggregatorTraceIds",
            "knownTonAggregatorTraceProjections"
        )

        keys.forEach {
            assertFalse(it, JSWebViewBridge.JsWebInterface.usesSecureStorage(it))
        }
    }

    @Test
    fun unknownKeysUseSecureStorage() {
        assertTrue(JSWebViewBridge.JsWebInterface.usesSecureStorage("futureStorageKey"))
    }
}
