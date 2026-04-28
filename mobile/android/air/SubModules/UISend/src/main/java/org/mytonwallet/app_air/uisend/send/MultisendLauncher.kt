package org.mytonwallet.app_air.uisend.send

import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.helpers.SubprojectHelpers
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig

object MultisendLauncher {
    fun launch(
        caller: WViewController,
    ) {
        val window = caller.window ?: return
        val multisendUrl = caller.view.context.getString(BaseR.string.app_multisend_url)
        if (multisendUrl.isEmpty()) return
        val url = SubprojectHelpers.appendSubprojectContext(multisendUrl)

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
                allowDownloads = true,
            )
        )
        nav.setRoot(browserVC)
        window.present(nav)
    }
}
