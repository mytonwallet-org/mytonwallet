package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.content.Context
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.TokenStore

class TitleSubtitleCell(
    context: Context,
) : WCell(context), WThemedView {

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

    private val separator: WView by lazy {
        val v = WView(context)
        v
    }

    init {
        layoutParams.apply {
            height = 64.dp
        }
        addView(iconView, LayoutParams(53.dp, 48.dp))
        addView(topLeftLabel)
        addView(bottomLeftLabel)
        addView(separator, LayoutParams(0, 1))
        setConstraints {
            toTop(iconView, 8f)
            toBottom(iconView, 8f)
            toStart(iconView, 12f)
            toTop(topLeftLabel, 10f)
            startToEnd(topLeftLabel, iconView, 7f)
            toBottom(bottomLeftLabel, 10f)
            startToEnd(bottomLeftLabel, iconView, 7f)
            toBottom(separator)
            toStart(separator, 72f)
            toEnd(separator)
        }

        setOnClickListener {
            onTap?.invoke(identifier)
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color)
        addRippleEffect(WColor.SecondaryBackground.color)
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        bottomLeftLabel.setTextColor(WColor.SecondaryText.color)
        separator.setBackgroundColor(WColor.Separator.color)
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
        separator.visibility = if (isLast) INVISIBLE else VISIBLE
    }

}
