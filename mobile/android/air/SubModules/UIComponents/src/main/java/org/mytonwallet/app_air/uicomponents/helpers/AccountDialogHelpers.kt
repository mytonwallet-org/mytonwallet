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
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.secureStorage.WSecureStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.resetAccounts
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.pushNotifications.AirPushNotifications
import org.mytonwallet.app_air.walletcore.stores.AccountStore

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
                                AccountStore.renameAccount(account, newWalletName)
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
                LocaleController.getString("Sign Out"),
                {
                    signout(window, account, notifyAccountChange = true)
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
                LocaleController.getString("Sign Out"),
                {
                    val accountsToRemove =
                        (accounts.filter { it.accountId != AccountStore.activeAccountId } +
                            accounts.firstOrNull { it.accountId == AccountStore.activeAccountId }).filterNotNull()

                    fun removeNextAccount(index: Int = 0) {
                        if (index >= accountsToRemove.size) {
                            WalletCore.notifyEvent(
                                WalletEvent.AccountChangedInApp(
                                    persistedAccountsModified = true
                                )
                            )
                            return
                        }
                        signout(
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

        private fun signout(
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
            // Instantly switch to another account if account is active and in main home screen
            val switchInstantly =
                !AccountStore.isPushedTemporary && AccountStore.activeAccountId == removingAccountId
            val nextAccountId =
                if (switchInstantly) accountIds.find { it !== AccountStore.activeAccountId }!! else null
            if (nextAccountId == null && WGlobalStorage.getActiveAccountId() == removingAccountId) {
                // Permanent active account is being removed with no replacement, replace it!
                //  This happens when user pushes a temporary-wallet and remove the active (permanent) account.
                WGlobalStorage.setActiveAccountId(
                    accountIds.find { it !== AccountStore.activeAccountId },
                    true
                )
            }
            AccountStore.removeAccount(
                removingAccountId,
                nextAccountId,
                isNextAccountPushedTemporary = false,
                onCompletion = { done, error ->
                    if (done == true) {
                        if (notifyAccountChange)
                            WalletCore.notifyEvent(
                                WalletEvent.AccountChangedInApp(
                                    persistedAccountsModified = true
                                )
                            )
                        callback?.invoke()
                    } else {
                        window.topViewController?.showError(error)
                    }
                })
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
                Logger.d(Logger.LogTag.ACCOUNT, "removeAllWallets: Resetting accounts")
                WGlobalStorage.deleteAllWallets()
                WSecureStorage.deleteAllWalletValues()
                WalletContextManager.delegate?.restartApp()
            }
        }
    }
}
