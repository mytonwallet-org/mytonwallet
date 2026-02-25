package org.mytonwallet.app_air.walletcore.models

import java.lang.ref.WeakReference

data class InAppBrowserConfig(
    val url: String,
    val title: String? = null,
    val thumbnail: String? = null,
    val injectDappConnect: Boolean,
    val forceCloseOnBack: Boolean = false,
    val injectDarkModeStyles: Boolean = false,
    val saveInVisitedHistory: Boolean = false,
    val options: List<Option>? = null,
    val selectedOption: String? = null,
    val topBarColorMode: TopBarColorMode = TopBarColorMode.CONTENT_BASED,
    val topBarColor: Int? = null,
    val optionsOnTitle: Boolean = false,
) {
    enum class TopBarColorMode {
        SYSTEM,
        CONTENT_BASED,
        FIXED,
    }

    data class Option(
        val identifier: String,
        val title: String,
        val subtitle: String? = null,
        val onClick: (browserVC: WeakReference<*>) -> Unit
    )
}
