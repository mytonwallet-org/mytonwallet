package org.mytonwallet.app_air.walletcore.models

import java.lang.ref.WeakReference

data class InAppBrowserConfig(
    val url: String,
    val title: String? = null,
    val thumbnail: String? = null,
    val injectTonConnectBridge: Boolean,
    val forceCloseOnBack: Boolean = false,
    val injectDarkModeStyles: Boolean = false,
    val saveInVisitedHistory: Boolean = false,
    val options: List<Option>? = null,
    val selectedOption: String? = null,
) {
    data class Option(
        val identifier: String,
        val title: String,
        val onClick: (browserVC: WeakReference<*>) -> Unit
    )
}
