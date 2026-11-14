package org.mytonwallet.app_air.walletcore

import org.mytonwallet.app_air.walletcontext.sdkStorage.WSdkInstallationStorage

internal enum class AirStorageRoute { SECURE, SDK, INSTALLATION }

internal object AirStorageRouting {
    private val sdkKeys = setOf(
        "agentMessages",
        "agentConversationId",
        "headlessBalanceSnapshots"
    )

    fun routeOf(key: String): AirStorageRoute = when (key) {
        in WSdkInstallationStorage.keys -> AirStorageRoute.INSTALLATION
        in sdkKeys -> AirStorageRoute.SDK
        else -> AirStorageRoute.SECURE
    }
}
