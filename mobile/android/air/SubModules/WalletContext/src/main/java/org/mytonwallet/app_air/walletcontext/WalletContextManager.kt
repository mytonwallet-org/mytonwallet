package org.mytonwallet.app_air.walletcontext

import android.content.Context
import android.content.Intent
import android.view.View
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletcontext.helpers.WordCheckMode
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode

interface WalletContextManagerDelegate {
    fun restartApp()
    fun getAddAccountVC(network: MBlockchainNetwork): Any
    fun getWalletAddedVC(isNew: Boolean): Any
    fun getWordCheckVC(
        network: MBlockchainNetwork,
        words: Array<String>,
        initialWordIndices: List<Int>,
        mode: WordCheckMode
    ): Any

    fun getImportLedgerVC(network: MBlockchainNetwork): Any
    fun getAddViewAccountVC(network: MBlockchainNetwork): Any

    fun getWalletsTabsVC(viewMode: MWalletSettingsViewMode): Any

    fun themeChanged(animated: Boolean = true)
    fun protectedModeChanged()
    fun lockScreen()
    fun isAppUnlocked(): Boolean
    fun handleDeeplink(deeplink: String): Boolean
    fun openASingleWallet(
        network: MBlockchainNetwork,
        addressByChainString: Map<String, String>,
        name: String?
    )

    fun walletIsReady()
    fun isWalletReady(): Boolean
    fun appResumed()
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

    val packageId = if (DEBUG_MODE) "org.mytonwallet.app.debug" else "org.mytonwallet.app"
    fun getMainActivityIntent(context: Context): Intent {
        return context.packageManager.getLaunchIntentForPackage(packageId)!!.apply {
            putExtra("switchToLegacy", true)
        }
    }
}
