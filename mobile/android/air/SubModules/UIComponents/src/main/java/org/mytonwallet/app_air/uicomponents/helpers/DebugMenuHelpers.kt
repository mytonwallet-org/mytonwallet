package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.view.View
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletcontext.helpers.logger.Logger

class DebugMenuHelpers {
    companion object {
        fun present(
            context: Context,
            view: View,
        ) {
            WMenuPopup.present(
                view,
                listOf(
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(icon = null, title = "Share Log File"),
                    ) {
                        Logger.shareLogFile(context)
                    }
                ),
                popupWidth = 196.dp,
                aboveView = false
            )
        }
    }
}
