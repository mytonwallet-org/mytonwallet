package org.mytonwallet.app_air.walletcore.models

data class InAppBrowserConfig(
    val url: String,
    val title: String? = null,
    val thumbnail: String? = null,
    val injectTonConnectBridge: Boolean,
    val forceCloseOnBack: Boolean = false,
    val injectDarkModeStyles: Boolean = false,
)
