package org.mytonwallet.app_air.uicomponents.helpers

import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork

class DebugMenuHelpers {
    companion object {
        fun present(
            window: WWindow,
            view: View,
        ) {
            WMenuPopup.present(
                view,
                listOf(
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(icon = null, title = "Share Log File"),
                    ) {
                        Logger.shareLogFile(window)
                    },
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(icon = null, title = "Add Testnet Wallet"),
                    ) {
                        val nav = WNavigationController(
                            window,
                            WNavigationController.PresentationConfig(
                                overFullScreen = false,
                                isBottomSheet = true,
                                aboveKeyboard = true
                            )
                        )
                        nav.setRoot(
                            WalletContextManager.delegate?.getAddAccountVC(MBlockchainNetwork.TESTNET) as WViewController
                        )
                        window.present(nav)
                    }
                ),
                popupWidth = WRAP_CONTENT,
                aboveView = false
            )
        }
    }
}
