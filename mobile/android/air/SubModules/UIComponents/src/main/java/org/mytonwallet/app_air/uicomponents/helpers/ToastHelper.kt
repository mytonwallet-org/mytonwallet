package org.mytonwallet.app_air.uicomponents.helpers

import androidx.annotation.DrawableRes
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.toast.ToastManager
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount

object ToastHelper {
    fun notifyViewWalletAdded(
        viewController: WViewController,
        account: MAccount? = null,
        accountId: String? = account?.accountId,
    ) {
        notifyWalletAction(
            viewController = viewController,
            accountId = accountId,
            iconResId = org.mytonwallet.app_air.walletcontext.R.drawable.ic_plus_thick,
            text = LocaleController.getString("View Wallet Added")
        )
    }

    fun notifyWalletImported(
        viewController: WViewController,
        account: MAccount? = null,
        accountId: String? = account?.accountId,
    ) {
        notifyWalletAction(
            viewController = viewController,
            accountId = accountId,
            iconResId = org.mytonwallet.app_air.walletcontext.R.drawable.ic_plus_thick,
            text = LocaleController.getString("Wallet Imported")
        )
    }

    fun notifyWalletCreated(
        viewController: WViewController,
        account: MAccount? = null,
        accountId: String? = account?.accountId,
    ) {
        notifyWalletAction(
            viewController = viewController,
            accountId = accountId,
            iconResId = org.mytonwallet.app_air.walletcontext.R.drawable.ic_plus_thick,
            text = LocaleController.getString("Wallet Created")
        )
    }

    fun notifySubwalletAdded(
        viewController: WViewController,
        account: MAccount? = null,
        accountId: String? = account?.accountId,
    ) {
        notifyWalletAction(
            viewController = viewController,
            accountId = accountId,
            iconResId = org.mytonwallet.app_air.walletcontext.R.drawable.ic_plus_thick,
            text = LocaleController.getString("Subwallet Added")
        )
    }

    fun notifySubwalletCreated(
        viewController: WViewController,
        account: MAccount? = null,
        accountId: String? = account?.accountId,
    ) {
        notifyWalletAction(
            viewController = viewController,
            accountId = accountId,
            iconResId = org.mytonwallet.app_air.walletcontext.R.drawable.ic_plus_thick,
            text = LocaleController.getString("Subwallet Created")
        )
    }

    fun notifySubwalletSwitched(
        viewController: WViewController,
        account: MAccount? = null,
        accountId: String? = account?.accountId,
    ) {
        notifyWalletAction(
            viewController = viewController,
            accountId = accountId,
            iconResId = org.mytonwallet.app_air.icons.R.drawable.ic_swap_30,
            text = LocaleController.getString("Subwallet Switched")
        )
    }

    private fun notifyWalletAction(
        viewController: WViewController,
        accountId: String?,
        @DrawableRes iconResId: Int,
        text: CharSequence,
    ) {
        val window = viewController.window
        ToastManager.show(
            ToastManager.Toast(
                iconResId = iconResId,
                text = text,
                actionTitle = accountId?.let { LocaleController.getString("Set Name") },
                onAction = accountId?.let { resolvedAccountId ->
                    {
                        window?.let { resolvedWindow ->
                            WalletCore.getAllAccounts()
                                .firstOrNull { it.accountId == resolvedAccountId }
                                ?.let { account ->
                                    resolvedWindow.topViewController?.let { viewController ->
                                        AccountDialogHelpers.presentRename(viewController, account)
                                    }
                                }
                        }
                    }
                }
            )
        )
    }
}
