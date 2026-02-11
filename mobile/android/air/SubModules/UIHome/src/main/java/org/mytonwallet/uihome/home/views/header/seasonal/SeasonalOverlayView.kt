package org.mytonwallet.uihome.home.views.header.seasonal

import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.stores.ConfigStore

class SeasonalOverlayView(context: Context) : FrameLayout(context) {

    init {
        clipChildren = false
    }

    fun updateSeasonalTheme() {
        removeAllViews()

        if (WGlobalStorage.getIsSeasonalThemingDisabled()) {
            visibility = GONE
            return
        }

        val theme = ConfigStore.getEffectiveSeasonalTheme()
        if (theme == null) {
            visibility = GONE
            return
        }

        visibility = VISIBLE
        when (theme) {
            ConfigStore.SeasonalTheme.NEW_YEAR -> {
                addView(
                    NewYearGarlandView(context),
                    LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                        gravity = Gravity.TOP
                    }
                )
            }
            ConfigStore.SeasonalTheme.VALENTINE -> {
                addView(
                    ValentineDecorationView(context),
                    LayoutParams(70.dp, 48.dp).apply {
                        gravity = Gravity.TOP or Gravity.START
                        topMargin = 5.dp
                        leftMargin = 2.dp
                    }
                )
            }
        }
    }
}
