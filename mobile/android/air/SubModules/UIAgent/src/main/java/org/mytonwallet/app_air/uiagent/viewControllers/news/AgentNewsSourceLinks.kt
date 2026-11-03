package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast
import java.net.URI
import java.net.URL
import org.mytonwallet.app_air.uiagent.agentV2.AgentTextLinks
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uiinappbrowser.CustomTabsBrowser
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig

internal object AgentNewsSourceLinks {
    fun open(context: Context, window: WWindow?, url: String) {
        if (!isOpenable(url)) {
            showUnsupportedLink(context)
            return
        }
        if (AgentTextLinks.isAppScreenLink(url)) {
            WalletCore.notifyEvent(WalletEvent.OpenUrl(url, source = DeeplinkOpenSource.AGENT))
        } else if (isTelegram(url)) {
            try {
                window?.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            } catch (_: Exception) {
                showUnsupportedLink(context)
            }
        } else if (url.startsWith("http:", ignoreCase = true)) {
            CustomTabsBrowser.open(context, url)
        } else {
            val currentWindow = window ?: return
            val navigation = WNavigationController(currentWindow)
            navigation.setRoot(
                InAppBrowserVC(context, InAppBrowserConfig(url = url, injectDappConnect = false))
            )
            currentWindow.present(navigation)
        }
    }

    fun isOpenable(url: String): Boolean {
        if (AgentTextLinks.isOpenable(url)) return true
        if (url.any { it.isWhitespace() || it == '\\' || it.isISOControl() }) return false
        return runCatching {
            if (url.startsWith("http:", ignoreCase = true)) {
                val parsed = URL(url)
                !parsed.host.isNullOrEmpty() && parsed.userInfo == null
            } else {
                val parsed = URI(url)
                parsed.scheme.equals("tg", ignoreCase = true) &&
                    !parsed.host.isNullOrEmpty() && parsed.rawUserInfo == null
            }
        }.getOrDefault(false)
    }

    fun isTelegram(url: String): Boolean = runCatching {
        val uri = URI(url)
        uri.scheme.equals("tg", ignoreCase = true) ||
            uri.host?.lowercase() in setOf("t.me", "telegram.me", "telegram.dog")
    }.getOrDefault(false)

    private fun showUnsupportedLink(context: Context) {
        Toast.makeText(
            context,
            LocaleController.getString("Unsupported link"),
            Toast.LENGTH_SHORT
        ).show()
    }
}
