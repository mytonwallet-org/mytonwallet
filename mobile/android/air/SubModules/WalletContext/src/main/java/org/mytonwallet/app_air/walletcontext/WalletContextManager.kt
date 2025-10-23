package org.mytonwallet.app_air.walletcontext

import android.content.Context
import android.content.Intent
import android.view.View
import org.mytonwallet.app_air.walletcontext.helpers.WordCheckMode

interface WalletContextManagerDelegate {
    fun restartApp()
    fun getAddAccountVC(): Any
    fun getWalletAddedVC(isNew: Boolean): Any
    fun getWordCheckVC(
        words: Array<String>,
        initialWordIndices: List<Int>,
        mode: WordCheckMode
    ): Any

    fun themeChanged()
    fun protectedModeChanged()
    fun lockScreen()
    fun isAppUnlocked(): Boolean
    fun handleDeeplink(deeplink: String): Boolean
    fun walletIsReady()
    fun isWalletReady(): Boolean
    fun switchToLegacy()

    fun bindQrCodeButton(
        context: Context,
        button: View,
        onResult: (String) -> Unit,
        parseDeepLinks: Boolean = true,
    )
}

object WalletContextManager {
    var delegate: WalletContextManagerDelegate? = null
        private set

    fun setDelegate(delegate: WalletContextManagerDelegate?) {
        this.delegate = delegate
    }

    fun getMainActivityIntent(context: Context): Intent {
        return context.packageManager.getLaunchIntentForPackage("org.mytonwallet.app")!!.apply {
            putExtra("switchToLegacy", true)
        }
    }
}
