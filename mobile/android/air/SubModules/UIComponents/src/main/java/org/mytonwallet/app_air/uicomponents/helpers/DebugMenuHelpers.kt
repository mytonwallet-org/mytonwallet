package org.mytonwallet.app_air.uicomponents.helpers

import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.stores.ConfigStore

class DebugMenuHelpers {
    companion object {
        fun present(
            window: WWindow,
            view: View,
        ) {
            WMenuPopup.present(
                view,
                buildList {
                    add(WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(icon = null, title = "Share Log File"),
                    ) {
                        Logger.shareLogFile(window)
                    })
                    add(WMenuPopup.Item(
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
                    })
                    if (DEBUG_MODE) {
                        add(WMenuPopup.Item(
                            WMenuPopup.Item.Config.Item(
                                icon = null,
                                title = "Seasonal Theme: ${ConfigStore.seasonalThemeOverride?.value ?: "None"}"
                            ),
                        ) {
                            presentSeasonalThemeOverrideMenu(view)
                        })
                    }
                },
                popupWidth = WRAP_CONTENT,
                positioning = WMenuPopup.Positioning.ABOVE,
                windowBackgroundStyle = BackgroundStyle.Cutout.fromView(view, roundRadius = 16f.dp)
            )
        }

        private fun presentSeasonalThemeOverrideMenu(view: View) {
            WMenuPopup.present(
                view,
                listOf(
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(icon = null, title = "None"),
                    ) {
                        ConfigStore.seasonalThemeOverride = null
                        WalletCore.notifyEvent(WalletEvent.SeasonalThemeChanged)
                    },
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(icon = null, title = "New Year"),
                    ) {
                        ConfigStore.seasonalThemeOverride = ConfigStore.SeasonalTheme.NEW_YEAR
                        WalletCore.notifyEvent(WalletEvent.SeasonalThemeChanged)
                    },
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(icon = null, title = "Valentine"),
                    ) {
                        ConfigStore.seasonalThemeOverride = ConfigStore.SeasonalTheme.VALENTINE
                        WalletCore.notifyEvent(WalletEvent.SeasonalThemeChanged)
                    }
                ),
                popupWidth = WRAP_CONTENT,
                positioning = WMenuPopup.Positioning.ABOVE,
                windowBackgroundStyle = BackgroundStyle.Cutout.fromView(view, roundRadius = 16f.dp)
            )
        }
    }
}
