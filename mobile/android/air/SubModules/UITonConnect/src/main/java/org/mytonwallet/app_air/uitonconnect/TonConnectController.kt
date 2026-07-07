package org.mytonwallet.app_air.uitonconnect

import android.content.Intent
import android.net.Uri
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.uitonconnect.viewControllers.connect.TonConnectRequestConnectVC
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.requestSend.TonConnectRequestSendVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.helpers.TonConnectHelper
import org.mytonwallet.app_air.walletcore.moshi.ApiConnectionType
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import java.lang.ref.WeakReference

class TonConnectController(private val window: WWindow) : WalletCore.UpdatesObserver {
    companion object {
        private var loadingConnectRequestViewController: WeakReference<TonConnectRequestConnectVC>? =
            null
        private var loadingSendRequestViewController: WeakReference<TonConnectRequestSendVC>? = null

        fun setLoadingConnectRequestViewController(vc: TonConnectRequestConnectVC): Boolean {
            if (loadingConnectRequestViewController?.get()?.isDisappeared == false)
                return false // A loading screen already shown
            loadingConnectRequestViewController = WeakReference(vc)
            return true
        }

        fun setLoadingSendRequestViewController(vc: TonConnectRequestSendVC): Boolean {
            if (loadingSendRequestViewController?.get()?.isDisappeared == false)
                return false // A loading screen already shown
            loadingSendRequestViewController = WeakReference(vc)
            return true
        }
    }

    fun connectStart(link: String) {
        WalletCore.call(
            ApiMethod.DApp.TonConnectHandleDeepLink(
                url = link,
                identifier = TonConnectHelper.generateId()
            )
        ) { _, err ->
            if (err != null) {
                Logger.e(Logger.LogTag.TON_CONNECT, "handleDeeplink: $err")
            }
        }
    }

    override fun onBridgeUpdate(update: ApiUpdate) {
        when (update) {
            is ApiUpdate.ApiUpdateDappConnect -> {
                window.doOnWalletReady {
                    WalletCore.recordTonConnectEvent(
                        "wallet-connect-request-ui-displayed",
                        update.promiseId
                    )
                    // Reuse a connect modal that's already shown (e.g. a connect deeplink tapped twice) so a
                    // second request replaces the first in place instead of stacking a new sheet.
                    val existingVC =
                        loadingConnectRequestViewController?.get()?.takeIf { !it.isDisappeared }
                            ?: window.navigationControllers
                                .flatMap { it.viewControllers }
                                .lastOrNull { it is TonConnectRequestConnectVC && !it.isDisappeared }
                                as? TonConnectRequestConnectVC
                    if (existingVC != null) {
                        existingVC.setDappUpdate(update)
                        loadingConnectRequestViewController = null
                    } else {
                        val navVC = WNavigationController(
                            window, WNavigationController.PresentationConfig(
                                style = WNavigationController.PresentationStyle.BottomSheet
                            )
                        )
                        navVC.setRoot(TonConnectRequestConnectVC(window, update))
                        window.presentOnWalletReady(navVC)
                    }
                }
            }

            is ApiUpdate.ApiUpdateDappSendTransactions -> {
                WalletCore.ensureAccountActivated(update.accountId) { accountChanged ->
                    window.doOnWalletReady {
                        WalletCore.recordTonConnectEvent(
                            "wallet-transaction-confirmation-ui-displayed",
                            update.promiseId
                        )
                        val loadingVC = loadingSendRequestViewController?.get()
                        if (accountChanged) {
                            while (window.navigationControllers.size > 1 && window.navigationControllers[1].viewControllers.lastOrNull() != loadingVC)
                                window.dismissNav(1)
                        }
                        if (loadingVC?.isDisappeared == false) {
                            loadingVC.setUpdate(update)
                            loadingSendRequestViewController = null
                        } else {
                            val navVC = WNavigationController(
                                window,
                                WNavigationController.PresentationConfig.PreferredFullScreen
                            )
                            navVC.setRoot(
                                TonConnectRequestSendVC(
                                    window,
                                    ApiConnectionType.SEND_TRANSACTION,
                                    update
                                )
                            )
                            window.presentOnWalletReady(navVC)
                        }
                    }
                }
            }

            is ApiUpdate.ApiUpdateDappSignData -> {
                WalletCore.ensureAccountActivated(update.accountId) { accountChanged ->
                    WalletCore.recordTonConnectEvent(
                        "wallet-sign-data-confirmation-ui-displayed",
                        update.promiseId
                    )
                    val loadingVC = loadingSendRequestViewController?.get()
                    if (accountChanged) {
                        while (window.navigationControllers.size > 1 && window.navigationControllers[1].viewControllers.lastOrNull() != loadingVC)
                            window.dismissNav(1)
                    }
                    if (loadingVC?.isDisappeared == false) {
                        loadingVC.setUpdate(update)
                        loadingSendRequestViewController = null
                    } else {
                        val navVC = WNavigationController(
                            window,
                            WNavigationController.PresentationConfig.PreferredFullScreen
                        )
                        navVC.setRoot(
                            TonConnectRequestSendVC(
                                window,
                                ApiConnectionType.SIGN_DATA,
                                update
                            )
                        )
                        window.presentOnWalletReady(navVC)
                    }
                }
            }

            is ApiUpdate.ApiUpdateDappAlreadyConnected -> {
                val url = update.url
                window.topViewController?.showAlert(
                    title = LocaleController.getString("Already Connected"),
                    text = LocaleController.getString("Return to the dapp to proceed, or reconnect."),
                    button = LocaleController.getString("OK"),
                    buttonPressed = { url?.let { openExternalUri(Uri.parse(it)) } },
                    secondaryButton = if (url != null) LocaleController.getString("Cancel") else null
                )
            }

            is ApiUpdate.ApiUpdateDappDisconnected -> {
                val url = update.url
                window.topViewController?.showAlert(
                    title = LocaleController.getString("Dapp Disconnected"),
                    text = LocaleController.getString("Please reconnect your wallet from the dapp."),
                    button = LocaleController.getString("OK"),
                    buttonPressed = { url?.let { openExternalUri(Uri.parse(it)) } },
                    secondaryButton = if (url != null) LocaleController.getString("Cancel") else null
                )
            }

            else -> {}
        }
    }

    fun onCreate() {
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateDappConnect::class.java, this)
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateDappSendTransactions::class.java, this)
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateDappSignData::class.java, this)
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateDappAlreadyConnected::class.java, this)
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateDappDisconnected::class.java, this)
    }

    fun onDestroy() {
        WalletCore.unsubscribeFromApiUpdates(ApiUpdate.ApiUpdateDappConnect::class.java, this)
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateDappSendTransactions::class.java,
            this
        )
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateDappSignData::class.java,
            this
        )
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateDappAlreadyConnected::class.java,
            this
        )
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateDappDisconnected::class.java,
            this
        )
    }

    private fun openExternalUri(uri: Uri) {
        window.startActivityCatching(Intent(Intent.ACTION_VIEW, uri))
    }
}
