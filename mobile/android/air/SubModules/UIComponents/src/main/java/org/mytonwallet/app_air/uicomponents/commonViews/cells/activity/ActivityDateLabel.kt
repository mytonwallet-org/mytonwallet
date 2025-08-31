package org.mytonwallet.app_air.uicomponents.commonViews.cells.activity

import android.content.Context
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import java.util.Date

class ActivityDateLabel(context: Context) : WLabel(context) {

    init {
        id = generateViewId()
        setStyle(16f, WFont.Medium)
        setOnClickListener { }
        setPadding(16.dp, 16.dp, 16.dp, 0)
    }

    fun configure(dt: Date, isFirst: Boolean) {
        setUserFriendlyDate(dt)
        setTextColor(WColor.PrimaryText.color)

        setBackgroundColor(
            WColor.Background.color,
            if (isFirst) ViewConstants.BIG_RADIUS.dp else 0f,
            0f
        )
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(48.dp, MeasureSpec.EXACTLY))
    }

}
