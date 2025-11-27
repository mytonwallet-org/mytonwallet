package org.mytonwallet.app_air.uicomponents.helpers

import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WEditText
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialogButton
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.api.removeAccount
import org.mytonwallet.app_air.walletcore.api.resetAccounts
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore
import org.mytonwallet.app_air.walletcore.stores.AddressStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.DappsStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore

class AccountDialogHelpers {
    companion object {
        fun presentRename(
            viewController: WViewController,
            account: MAccount,
        ) {
            val context = viewController.context
            val input = object : WEditText(context, null, false) {
                init {
                    setSingleLine()
                    setPadding(8.dp, 8.dp, 8.dp, 8.dp)
                    updateTheme()
                }

                override fun updateTheme() {
                    setBackgroundColor(WColor.SecondaryBackground.color, 10f.dp)
                }
            }.apply {
                hint = LocaleController.getString("Wallet Name")
                setText(account.name)
            }
            val container = FrameLayout(context).apply {
                setPadding(24.dp, 0, 24.dp, 0)
                addView(input, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            }

            WDialog(
                container,
                WDialog.Config(
                    title = LocaleController.getString("Rename Wallet"),
                    actionButton = WDialogButton.Config(
                        title = LocaleController.getString("OK"),
                        onTap = {
                            viewController.view.hideKeyboard()
                            val newWalletName = input.text.toString().trim()
                            if (newWalletName.isNotEmpty()) {
                                account.name = newWalletName
                                WGlobalStorage.save(
                                    account.accountId,
                                    newWalletName
                                )
                                AddressStore.updatedAccountName(
                                    account.accountId,
                                    newWalletName
                                )
                                if (AccountStore.activeAccountId == account.accountId) {
                                    AccountStore.activeAccount?.name = newWalletName
                                }
                                AirPushNotifications.accountNameChanged(account)
                                WalletCore.notifyEvent(WalletEvent.AccountNameChanged)
                            }
                        }
                    )
                )
            ).presentOn(viewController)
        }

        fun presentSignOut(window: WWindow, account: MAccount) {
            val vc = window.topViewController ?: return
            vc.showAlert(
                LocaleController.getString("Sign Out"),
                LocaleController.getString("\$logout_warning")
                    .toProcessedSpannableStringBuilder(),
                LocaleController.getString("Log Out"),
                {
                    signOutPressed(window, account, notifyAccountChange = true)
                },
                LocaleController.getString("Cancel"),
                preferPrimary = false,
                primaryIsDanger = true
            )
        }

        fun presentSignOut(window: WWindow, accounts: List<MAccount>) {
            val vc = window.topViewController ?: return
            vc.showAlert(
                LocaleController.getString("Sign Out"),
                LocaleController.getString("\$logout_warning")
                    .toProcessedSpannableStringBuilder(),
                LocaleController.getString("Log Out"),
                {
                    val accountsToRemove =
                        (accounts.filter { it.accountId != AccountStore.activeAccountId } +
                            accounts.firstOrNull { it.accountId == AccountStore.activeAccountId }).filterNotNull()

                    fun removeNextAccount(index: Int = 0) {
                        if (index >= accountsToRemove.size) {
                            WalletCore.notifyEvent(WalletEvent.AccountChangedInApp(accountsModified = true))
                            return
                        }
                        signOutPressed(
                            window,
                            accountsToRemove[index],
                            notifyAccountChange = false
                        ) {
                            removeNextAccount(index + 1)
                        }
                    }
                    removeNextAccount()
                },
                LocaleController.getString("Cancel"),
                preferPrimary = false,
                primaryIsDanger = true
            )
        }

        private fun signOutPressed(
            window: WWindow,
            removingAccount: MAccount,
            notifyAccountChange: Boolean,
            callback: (() -> Unit)? = null
        ) {
            val accountIds = WGlobalStorage.accountIds()
            if (accountIds.size < 2) {
                // it is the last account id, delete all data and restart app
                removeAllWallets(window)
            } else {
                removeWallet(window, removingAccount, notifyAccountChange, callback)
            }
        }

        private fun removeWallet(
            window: WWindow,
            removingAccount: MAccount,
            notifyAccountChange: Boolean,
            callback: (() -> Unit)?
        ) {
            val removingAccountId = removingAccount.accountId
            val accountIds = WGlobalStorage.accountIds()
            val nextAccountId =
                if (AccountStore.activeAccountId == removingAccountId) accountIds.find { it !== AccountStore.activeAccountId }!! else null
            WalletCore.removeAccount(removingAccountId, nextAccountId) { done, error ->
                if (done == true) {
                    Logger.d(Logger.LogTag.ACCOUNT, "Remove account: $removingAccountId")
                    ActivityStore.removeAccount(removingAccountId)
                    DappsStore.removeAccount(removingAccountId)
                    NftStore.setNfts(
                        null,
                        removingAccountId,
                        notifyObservers = false,
                        isReorder = false
                    )
                    WGlobalStorage.removeAccount(removingAccountId)
                    StakingStore.setStakingState(removingAccountId, null)
                    BalanceStore.removeBalances(removingAccountId)
                    WCacheStorage.clean(removingAccountId)
                    AirPushNotifications.unsubscribe(removingAccount) {}
                    nextAccountId?.let {
                        WalletCore.activateAccount(
                            nextAccountId,
                            notifySDK = false
                        ) { activeAccount, err ->
                            if (activeAccount == null || err != null) {
                                removeAllWallets(window)
                                return@activateAccount
                            }
                            if (notifyAccountChange)
                                WalletCore.notifyEvent(
                                    WalletEvent.AccountChangedInApp(
                                        accountsModified = true
                                    )
                                )
                        }
                    } ?: run {
                        if (notifyAccountChange)
                            WalletCore.notifyEvent(WalletEvent.AccountChangedInApp(accountsModified = true))
                    }
                    callback?.invoke()
                } else {
                    window.topViewController?.showError(error)
                }
            }
        }

        private fun removeAllWallets(window: WWindow) {
            val vc = window.topViewController ?: return
            val view = vc.view
            view.lockView()
            AccountStore.activeAccount?.let { acc ->
                AirPushNotifications.unsubscribe(acc) {}
            }
            WalletCore.resetAccounts { ok, err ->
                if (ok != true || err != null) {
                    view.unlockView()
                    vc.showError(err)
                }
                Logger.d(Logger.LogTag.ACCOUNT, "Reset accounts from settings")
                WGlobalStorage.setActiveAccountId(null)
                WGlobalStorage.deleteAllWallets()
                WSecureStorage.deleteAllWalletValues()
                WalletContextManager.delegate?.restartApp()
            }
        }
    }
}
