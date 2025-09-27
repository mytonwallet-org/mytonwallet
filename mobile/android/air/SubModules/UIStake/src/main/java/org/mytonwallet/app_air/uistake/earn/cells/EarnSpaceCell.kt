package org.mytonwallet.app_air.uistake.earn.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class EarnSpaceCell(context: Context, val isTransparent: Boolean = false) : WCell(context),
    WThemedView {

    override fun updateTheme() {
        setBackgroundColor(
            if (isTransparent) Color.TRANSPARENT else WColor.SecondaryBackground.color
        )
    }

}
