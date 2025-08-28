package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.content.Context
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color

class HeaderCell(
    context: Context,
) : WCell(context), WThemedView {

    private var titleColor: Int = WColor.PrimaryText.color

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    init {
        layoutParams.apply {
            height = 48.dp
        }
        addView(titleLabel)
        setConstraints {
            toStart(titleLabel, 20f)
            toTop(titleLabel, 16f)
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color)
        titleLabel.setTextColor(titleColor)
    }

    fun configure(title: String, titleColor: Int? = null) {
        titleLabel.text = title
        if (titleColor != null) {
            this.titleColor = titleColor
            titleLabel.setTextColor(titleColor)
        }
    }

}
