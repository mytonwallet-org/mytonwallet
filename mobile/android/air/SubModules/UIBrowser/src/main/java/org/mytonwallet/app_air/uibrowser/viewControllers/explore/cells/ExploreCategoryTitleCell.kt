package org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color

@SuppressLint("ViewConstructor")
class ExploreCategoryTitleCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {
    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(17f, WFont.Medium)
        lbl.maxLines = 1
        lbl
    }

    private val containerView: WView by lazy {
        val v = WView(context).apply {
            addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            setConstraints {
                toStart(titleLabel)
                toCenterY(titleLabel)
            }
        }
        v
    }

    init {
        addView(containerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    override fun updateTheme() {
        titleLabel.setTextColor(WColor.PrimaryText.color)
    }

    fun configure(title: String, bottomPadding: Int) {
        containerView.setPadding(24.dp, 16.dp, 24.dp, bottomPadding)
        titleLabel.text = title
        updateTheme()
    }

}
