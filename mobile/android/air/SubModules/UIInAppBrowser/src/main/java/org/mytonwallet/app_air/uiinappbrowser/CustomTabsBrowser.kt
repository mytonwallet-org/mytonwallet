package org.mytonwallet.app_air.uiinappbrowser

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.browser.customtabs.CustomTabColorSchemeParams
import androidx.browser.customtabs.CustomTabsIntent
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import androidx.core.net.toUri

object CustomTabsBrowser {
    fun open(context: Context, url: String) {
        val uri = url.toUri()
        val toolbarColor = WColor.Background.color
        val colorScheme = if (ThemeManager.isDark) {
            CustomTabsIntent.COLOR_SCHEME_DARK
        } else {
            CustomTabsIntent.COLOR_SCHEME_LIGHT
        }
        val params = CustomTabColorSchemeParams.Builder()
            .setToolbarColor(toolbarColor)
            .build()
        val intent = CustomTabsIntent.Builder()
            .setShowTitle(true)
            .setDefaultColorSchemeParams(params)
            .setColorScheme(colorScheme)
            .build()

        if (context !is Activity) {
            intent.intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            intent.launchUrl(context, uri)
        } catch (_: SecurityException) {
            val fallback = Intent(Intent.ACTION_VIEW, uri)
            fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(fallback)
            } catch (_: Exception) {
            }
        }
    }
}
