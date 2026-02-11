package org.mytonwallet.app_air.uicomponents.commonViews.cells.activity

import android.content.Context
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import java.util.Date

class ActivityDateLabel(context: Context) : WLabel(context) {

    init {
        id = generateViewId()
        setStyle(14f, WFont.DemiBold)
        setOnClickListener { }
        setPadding(20.dp, 16.dp, 20.dp, 0)
    }

    private var isFirst = false
    fun configure(dt: Date, isFirst: Boolean) {
        this.isFirst = isFirst
        setUserFriendlyDate(dt)
    }

    override fun updateTheme() {
        super.updateTheme()

        setTextColor(WColor.Tint.color)

        setBackgroundColor(
            WColor.Background.color,
            if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f,
            0f
        )
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, 40.dp.exactly)
    }

}
