package org.mytonwallet.app_air.uitonconnect

import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uitonconnect.viewControllers.connect.TonConnectRequestConnectVC
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.requestSend.TonConnectRequestSendVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.helpers.TonConnectHelper
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.ApiConnectionType
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
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
        if (AccountStore.activeAccount?.accountType == MAccount.AccountType.VIEW) {
            window.topViewController?.showAlert(
                LocaleController.getString("Error"),
                LocaleController.getString("Action is not possible on a view-only wallet.")
            )
            return
        }
        WalletCore.call(
            ApiMethod.DApp.TonConnectHandleDeepLink(
                url = link,
                identifier = TonConnectHelper.generateId()
            )
        ) { _, _ -> }
    }

    override fun onBridgeUpdate(update: ApiUpdate) {
        when (update) {
            is ApiUpdate.ApiUpdateDappConnect -> {
                window.doOnWalletReady {
                    val loadingVC = loadingConnectRequestViewController?.get()
                    if (loadingVC?.isDisappeared == false) {
                        loadingVC.setDappUpdate(update)
                        loadingConnectRequestViewController = null
                    } else {
                        val navVC = WNavigationController(
                            window, WNavigationController.PresentationConfig(
                                overFullScreen = false,
                                isBottomSheet = true
                            )
                        )
                        navVC.setRoot(TonConnectRequestConnectVC(window, update))
                        window.present(navVC)
                    }
                }
            }

            is ApiUpdate.ApiUpdateDappSendTransactions -> {
                WalletCore.ensureAccountActivated(update.accountId) { accountChanged ->
                    window.doOnWalletReady {
                        val loadingVC = loadingSendRequestViewController?.get()
                        if (accountChanged) {
                            while (window.navigationControllers.size > 1 && window.navigationControllers[1].viewControllers.lastOrNull() != loadingVC)
                                window.dismissNav(1)
                        }
                        if (loadingVC?.isDisappeared == false) {
                            loadingVC.setUpdate(update)
                            loadingSendRequestViewController = null
                        } else {
                            val navVC = WNavigationController(window)
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
                    val loadingVC = loadingSendRequestViewController?.get()
                    if (accountChanged) {
                        while (window.navigationControllers.size > 1 && window.navigationControllers[1].viewControllers.lastOrNull() != loadingVC)
                            window.dismissNav(1)
                    }
                    if (loadingVC?.isDisappeared == false) {
                        loadingVC.setUpdate(update)
                        loadingSendRequestViewController = null
                    } else {
                        val navVC = WNavigationController(window)
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

            else -> {}
        }
    }

    fun onCreate() {
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateDappConnect::class.java, this)
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateDappSendTransactions::class.java, this)
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateDappSignData::class.java, this)
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
    }
}
