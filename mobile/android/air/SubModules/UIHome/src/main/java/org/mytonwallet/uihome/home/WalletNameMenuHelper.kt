package org.mytonwallet.uihome.home

import android.view.View
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.AccountDialogHelpers
import org.mytonwallet.app_air.uicomponents.widgets.frameAsPath
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uisettings.viewControllers.walletCustomization.WalletCustomizationVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.models.MAccount

object WalletNameMenuHelper {
    fun present(
        viewController: WViewController,
        anchor: View,
        account: MAccount,
        onManageWallets: () -> Unit,
    ) {
        WMenuPopup.present(
            anchor,
            listOf(
                WMenuPopup.Item(
                    icon = org.mytonwallet.uihome.R.drawable.ic_pen,
                    title = LocaleController.getString("Rename"),
                    onTap = {
                        AccountDialogHelpers.presentRename(viewController, account)
                    }),
                WMenuPopup.Item(
                    icon = org.mytonwallet.uihome.R.drawable.ic_customize,
                    title = LocaleController.getString("Customize"),
                    onTap = {
                        val window = viewController.window ?: return@Item
                        val navVC = WNavigationController(
                            window,
                            WNavigationController.PresentationConfig.PreferredFullScreen
                        )
                        navVC.setRoot(
                            WalletCustomizationVC(viewController.context, account.accountId)
                        )
                        window.present(navVC)
                    }),
                WMenuPopup.Item(
                    icon = org.mytonwallet.app_air.icons.R.drawable.ic_manage_30,
                    title = LocaleController.getString("Manage Wallets"),
                    onTap = {
                        onManageWallets()
                    }),
            ),
            popupWidth = 220.dp,
            yOffset = (-20).dp,
            positioning = WMenuPopup.Positioning.BELOW,
            centerHorizontally = true,
            windowBackgroundStyle = WMenuPopup.BackgroundStyle.Cutout(
                anchor.frameAsPath(
                    roundRadius = 16f.dp,
                    leftOffset = 8f.dp,
                    topOffset = (-16f).dp,
                    rightOffset = 8f.dp,
                    bottomOffset = (-20f).dp
                )
            ),
            backdropStyle = WMenuPopup.BackdropStyle.BlurDimmed,
        )
    }
}
