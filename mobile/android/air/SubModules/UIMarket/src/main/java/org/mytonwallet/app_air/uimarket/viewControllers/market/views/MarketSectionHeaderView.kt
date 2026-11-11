package org.mytonwallet.app_air.uimarket.viewControllers.market.views

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class MarketSectionHeaderView(context: Context, private val onSeeAll: () -> Unit) :
    WView(context),
    WThemedView {

    private val titleLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        translationY = 1f.dp
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER_VERTICAL
    }

    private val seeAllLabel = WLabel(context).apply {
        id = UIComponentsR.id.market_see_all
        setStyle(14f, WFont.Regular)
        translationY = 1f.dp
        text = LocaleController.getString("See All")
        gravity = Gravity.CENTER
        setOnClickListener { onSeeAll() }
    }

    init {
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(seeAllLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toStart(titleLabel, 20f)
            toCenterY(titleLabel)
            endToStart(titleLabel, seeAllLabel, 8f)
            toEnd(seeAllLabel, 20f)
            toCenterY(seeAllLabel)
            constrainedWidth(titleLabel.id, true)
            setHorizontalBias(titleLabel.id, 0f)
        }
        updateTheme()
    }

    fun configure(title: String, showsSeeAll: Boolean) {
        titleLabel.text = LocaleController.getString(title)
        titleLabel.contentDescription = titleLabel.text
        seeAllLabel.isGone = !showsSeeAll
    }

    override fun updateTheme() {
        titleLabel.setTextColor(WColor.Tint.color)
        seeAllLabel.setTextColor(WColor.Tint.color)
    }
}
