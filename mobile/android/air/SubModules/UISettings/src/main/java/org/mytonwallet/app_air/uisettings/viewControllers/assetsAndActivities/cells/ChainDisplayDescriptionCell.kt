package org.mytonwallet.app_air.uisettings.viewControllers.assetsAndActivities.cells

import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor

class ChainDisplayDescriptionCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private val label = WLabel(context).apply {
        setStyle(13f, WFont.Regular)
        setTextColor(WColor.SecondaryText)
    }

    override fun setupViews() {
        super.setupViews()
        addView(label, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(label, 20f)
            toEnd(label, 20f)
            toTop(label, 8f)
            toBottom(label, 16f)
        }
    }

    fun configure(text: String) {
        label.text = text
    }

    override fun updateTheme() {
        label.setTextColor(WColor.SecondaryText)
    }
}
