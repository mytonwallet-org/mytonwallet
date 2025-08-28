package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.content.Context
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color

class HeaderSpaceCell(context: Context) : WCell(context), WThemedView {
    override fun setupViews() {
        super.setupViews()
        updateTheme()
    }

    override fun updateTheme() {
        if (!ThemeManager.uiMode.hasRoundedCorners) {
            setBackgroundColor(WColor.Background.color)
        } else {
            background = null
        }
    }
}
