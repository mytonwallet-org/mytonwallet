package org.mytonwallet.app_air.walletcore

import org.junit.Assert.assertEquals
import org.junit.Test

class AirStorageRoutingTest {
    @Test
    fun walletKeysUseSecureStorage() {
        val keys = listOf(
            "accounts",
            "stateVersion",
            "currentAccountId",
            "installMetadata",
            "installAttribution",
            "langCode",
            "dapps",
            "dappMethods:lastAccountId",
            "windowId",
            "windowState",
            "isTonProxyEnabled",
            "isDeeplinkHookEnabled",
            "sseLastEventId",
            "sseDelivery"
        )

        keys.forEach {
            assertEquals(it, AirStorageRoute.SECURE, AirStorageRouting.routeOf(it))
        }
    }

    @Test
    fun sdkOnlyKeysUseSdkStorage() {
        listOf("agentMessages", "agentConversationId", "headlessBalanceSnapshots").forEach {
            assertEquals(it, AirStorageRoute.SDK, AirStorageRouting.routeOf(it))
        }
    }

    @Test
    fun clientIdentityKeysUseInstallationStorage() {
        listOf("clientId", "referrer").forEach {
            assertEquals(it, AirStorageRoute.INSTALLATION, AirStorageRouting.routeOf(it))
        }
    }

    @Test
    fun unknownKeysUseSecureStorage() {
        assertEquals(AirStorageRoute.SECURE, AirStorageRouting.routeOf("futureStorageKey"))
    }
}
