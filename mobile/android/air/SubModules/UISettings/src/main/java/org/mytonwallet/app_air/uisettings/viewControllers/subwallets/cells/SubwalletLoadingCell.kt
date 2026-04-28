package org.mytonwallet.app_air.uisettings.viewControllers.subwallets.cells

import android.content.Context
import android.widget.ProgressBar
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class SubwalletLoadingCell(
    context: Context,
) : WCell(context), WThemedView {

    private val progressBar = ProgressBar(context).apply {
        id = generateViewId()
        isIndeterminate = true
    }

    private val loadingLabel = WLabel(context).apply {
        setStyle(15f, WFont.Regular)
        text = LocaleController.getString("Loading more")
    }

    init {
        layoutParams.apply {
            height = 50.dp
        }
        addView(progressBar, LayoutParams(20.dp, 20.dp))
        addView(loadingLabel)
        setConstraints {
            toStart(progressBar, 20f)
            toCenterY(progressBar)
            toCenterY(loadingLabel)
            startToEnd(loadingLabel, progressBar, 12f)
        }

        isClickable = false
        isFocusable = false

        updateTheme()
    }

    override fun updateTheme() {
        loadingLabel.setTextColor(WColor.SecondaryText.color)
    }
}
