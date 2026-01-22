package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.content.Context
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView

class HeaderSpaceCell(context: Context) : WCell(context), WThemedView {
    override fun setupViews() {
        super.setupViews()
        updateTheme()
    }

    override fun updateTheme() {
    }
}
