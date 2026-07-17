package org.mytonwallet.app_air.walletcontext

import android.content.Context
import android.content.Intent
import android.view.View
import org.mytonwallet.app_air.walletcontext.helpers.WordCheckMode
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import java.lang.ref.WeakReference

enum class DeeplinkOpenSource {
    OS_EXTERNAL,
    IN_APP_BROWSER,
    INTERNAL_UI,
    QR_SCAN,
    AGENT;

    val requiresFreshAuth: Boolean
        get() = this != INTERNAL_UI

    val canRouteOfframp: Boolean
        get() = this == OS_EXTERNAL || this == INTERNAL_UI || this == AGENT
}

interface WalletContextManagerDelegate {
    fun restartApp()
    fun getAddAccountVC(network: MBlockchainNetwork): Any
    fun getWalletAddedVC(isNew: Boolean, importedAccountsCount: Int = 1): Any
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
    fun handleDeeplink(
        deeplink: String,
        source: DeeplinkOpenSource = DeeplinkOpenSource.OS_EXTERNAL
    ): Boolean
    fun openASingleWallet(
        network: MBlockchainNetwork,
        addressByChainString: Map<String, String>,
        name: String?
    )

    fun walletIsReady()
    fun isWalletReady(): Boolean
    fun showError(error: String?)
    fun switchToLegacy()
    fun recreateBridge()

    fun bindQrCodeButton(
        context: Context,
        button: View,
        onResult: (String) -> Unit,
        parseDeepLinks: Boolean = true,
    )
}

object WalletContextManager {
    var delegate: WeakReference<WalletContextManagerDelegate>? = null
        private set

    private var pendingSwitchToLegacy = false

    fun scheduleSwitchToLegacy() {
        delegate?.get()?.switchToLegacy() ?: run { pendingSwitchToLegacy = true }
    }

    fun setDelegate(delegate: WalletContextManagerDelegate?) {
        this.delegate = delegate?.let { WeakReference(it) }
        if (delegate != null && pendingSwitchToLegacy) {
            pendingSwitchToLegacy = false
            delegate.switchToLegacy()
        }
    }

    fun getMainActivityIntent(context: Context): Intent {
        val launchIntent = checkNotNull(
            context.packageManager.getLaunchIntentForPackage(context.packageName)
        ) { "No launch intent for own package" }
        return launchIntent.apply {
            putExtra("switchToLegacy", true)
        }
    }
}
