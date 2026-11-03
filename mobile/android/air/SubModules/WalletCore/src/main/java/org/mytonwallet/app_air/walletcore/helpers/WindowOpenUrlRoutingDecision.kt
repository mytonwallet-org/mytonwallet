package org.mytonwallet.app_air.walletcore.helpers

import java.util.Locale
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcontext.helpers.InAppBrowserDeeplinkHelpers

internal enum class WindowOpenUrlRoutingDecision {
    CONSUME,
    LOAD_URL,
    OPEN_NON_WEB_URL,
    IGNORE;

    companion object {
        private val schemeRegex = Regex("[a-z][a-z0-9+.-]*")

        // Only http(s) URLs are loaded: `WebView.loadUrl` runs a `javascript:` URL in whatever
        // document the main frame shows.
        fun resolve(
            url: String,
            handleDeeplink: (String, DeeplinkOpenSource) -> Boolean
        ): WindowOpenUrlRoutingDecision {
            val scheme = url.substringBefore(':', missingDelimiterValue = "").lowercase(Locale.US)
            if (!schemeRegex.matches(scheme) || scheme == "javascript") {
                return IGNORE
            }

            if (InAppBrowserDeeplinkHelpers.checkIsInAppBrowserOfframpSelfDeeplink(url)) {
                return CONSUME
            }

            val isHandled = handleDeeplink(url, DeeplinkOpenSource.IN_APP_BROWSER)
            if (isHandled) {
                return CONSUME
            }

            return if (scheme == "http" || scheme == "https") LOAD_URL else OPEN_NON_WEB_URL
        }
    }
}
