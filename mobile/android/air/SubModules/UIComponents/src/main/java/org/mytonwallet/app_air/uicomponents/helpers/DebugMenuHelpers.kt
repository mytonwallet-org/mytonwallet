package org.mytonwallet.app_air.uicomponents.helpers

import android.content.Context
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletbasecontext.logger.Logger

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
                popupWidth = WRAP_CONTENT,
                aboveView = false
            )
        }
    }
}
