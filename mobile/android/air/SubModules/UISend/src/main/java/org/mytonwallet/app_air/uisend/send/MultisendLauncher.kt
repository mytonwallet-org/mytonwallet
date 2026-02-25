package org.mytonwallet.app_air.uisend.send

import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.helpers.SubprojectHelpers
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig

object MultisendLauncher {
    private const val MULTISEND_URL = "https://multisend.mytonwallet.io/"

    fun launch(
        caller: WViewController,
    ) {
        val window = caller.window ?: return
        val url = SubprojectHelpers.appendSubprojectContext(MULTISEND_URL)

        val nav = WNavigationController(window)
        val browserVC = InAppBrowserVC(
            caller.view.context,
            null,
            InAppBrowserConfig(
                url = url,
                title = LocaleController.getString("Multisend"),
                injectDappConnect = true,
                injectDarkModeStyles = true,
                topBarColorMode = InAppBrowserConfig.TopBarColorMode.SYSTEM,
                forceCloseOnBack = true,
            )
        )
        nav.setRoot(browserVC)
        window.present(nav)
    }
}
