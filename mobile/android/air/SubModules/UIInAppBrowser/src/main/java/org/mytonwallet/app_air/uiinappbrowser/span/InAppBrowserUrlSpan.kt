package org.mytonwallet.app_air.uiinappbrowser.span

import android.text.style.URLSpan
import android.view.View
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig

class InAppBrowserUrlSpan(
    url: String,
    private val tabBarController: WNavigationController.ITabBarController?
) :
    URLSpan(url) {
    override fun onClick(widget: View) {
        val context = widget.context
        val parentWindow = context as? WWindow
            ?: return super.onClick(widget)

        val inAppBrowserVC = InAppBrowserVC(
            context,
            tabBarController,
            InAppBrowserConfig(
                url = url,
                injectDappConnect = true
            )
        )
        val nav = WNavigationController(parentWindow)
        nav.setRoot(inAppBrowserVC)
        parentWindow.present(nav)
    }
}
