package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.content.Context
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class TitleSubtitleCell(
    context: Context,
) : WCell(context), WThemedView {

    private val ripple = WRippleDrawable.create(0f)

    private var identifier: String = ""
    var onTap: ((identifier: String) -> Unit)? = null

    private val iconView: IconView by lazy {
        val iv = IconView(context)
        iv
    }

    private val topLeftLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    private val bottomLeftLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(13f)
        lbl
    }

    init {
        background = ripple
        layoutParams.apply {
            height = 60.dp
        }
        addView(iconView, LayoutParams(50.dp, 50.dp))
        addView(topLeftLabel)
        addView(bottomLeftLabel)
        setConstraints {
            toTop(iconView, 6f)
            toBottom(iconView, 6f)
            toStart(iconView, 12f)
            toTop(topLeftLabel, 8f)
            toStart(topLeftLabel, 60f)
            toBottom(bottomLeftLabel, 8f)
            toStart(bottomLeftLabel, 60f)
        }

        setOnClickListener {
            onTap?.invoke(identifier)
        }

        updateTheme()
    }

    override fun updateTheme() {
        ripple.backgroundColor = WColor.Background.color
        ripple.rippleColor = WColor.SecondaryBackground.color
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        bottomLeftLabel.setTextColor(WColor.SecondaryText.color)
    }

    fun configure(tokenBalance: MTokenBalance, isLast: Boolean) {
        val token = TokenStore.getToken(tokenBalance.token)
        identifier = token?.slug ?: ""
        iconView.config(token)
        topLeftLabel.text = token?.name
        bottomLeftLabel.setAmount(
            tokenBalance.amountValue,
            token?.decimals ?: 9,
            token?.symbol ?: "",
            token?.decimals ?: 9,
            true
        )
    }

}
