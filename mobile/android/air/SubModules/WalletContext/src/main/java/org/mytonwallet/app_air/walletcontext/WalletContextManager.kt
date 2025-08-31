package org.mytonwallet.app_air.walletcontext

import android.content.Context
import android.content.Intent

interface WalletContextManagerDelegate {
    fun restartApp()
    fun getAddAccountVC(): Any
    fun getTabsVC(): Any
    fun themeChanged()
    fun protectedModeChanged()
    fun lockScreen()
    fun isAppUnlocked(): Boolean
    fun handleDeeplink(deeplink: String): Boolean
    fun walletIsReady()
    fun isWalletReady(): Boolean
    fun switchToLegacy()
}

val DEBUG_MODE = BuildConfig.DEBUG_MODE!!

object WalletContextManager {
    var delegate: WalletContextManagerDelegate? = null

    fun getMainActivityIntent(context: Context): Intent {
        return context.packageManager.getLaunchIntentForPackage("org.mytonwallet.app")!!.apply {
            putExtra("switchToLegacy", true)
        }
    }
}
