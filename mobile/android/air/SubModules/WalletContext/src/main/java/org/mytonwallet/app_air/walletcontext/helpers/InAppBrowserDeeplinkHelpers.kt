package org.mytonwallet.app_air.walletcontext.helpers

import java.net.URI

object InAppBrowserDeeplinkHelpers {
    private const val OFFRAMP_HOST = "offramp"
    private val WALLET_SELF_SCHEMES = setOf("mtw", "gramwallet")

    fun checkIsInAppBrowserOfframpSelfDeeplink(url: String): Boolean {
        val uri = runCatching { URI(url) }.getOrNull() ?: return false
        val scheme = uri.scheme?.lowercase() ?: return false
        val host = uri.host?.lowercase() ?: return false

        return host == OFFRAMP_HOST && scheme in WALLET_SELF_SCHEMES
    }
}
