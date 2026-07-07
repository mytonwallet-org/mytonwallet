package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVM

@SuppressLint("ViewConstructor")
class SearchWalletCell(
    context: Context,
    private val onTapOwnWallet: (match: ExploreVM.MyWalletMatch) -> Unit,
    private val onTapWalletInfo: (match: ExploreVM.WalletInfoMatch) -> Unit,
) : WCell(context, LayoutParams(MATCH_PARENT, 60.dp)), WThemedView {

    private val iconView: AccountIconView by lazy {
        AccountIconView(context, AccountIconView.Usage.ViewItem(10f.dp))
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(adaptiveFontSize(), WFont.Medium)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MIDDLE
            setTextColor(WColor.PrimaryText)
        }
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(12f, WFont.Regular)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MIDDLE
            setTextColor(WColor.SecondaryText)
        }
    }

    override fun setupViews() {
        super.setupViews()
        addView(iconView, LayoutParams(24.dp, 24.dp))
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(iconView, 18f)
            toCenterY(iconView)
            toStart(titleLabel, 56f)
            toTop(titleLabel, 9.5f)
            toEnd(titleLabel, 12f)
            toStart(subtitleLabel, 56f)
            topToBottom(subtitleLabel, titleLabel, 1f)
            toEnd(subtitleLabel, 12f)
        }
    }

    private var isLastItem = false

    fun configure(match: ExploreVM.MyWalletMatch, isLastItem: Boolean) {
        this.isLastItem = isLastItem
        val account = match.account
        iconView.config(account)
        val name = account.name.takeIf { it.isNotEmpty() }
        titleLabel.text = name ?: (match.address ?: "").formatStartEndAddress()
        subtitleLabel.text = (match.address ?: "").formatStartEndAddress()
        setOnClickListener { onTapOwnWallet(match) }
        updateTheme()
    }

    fun configure(match: ExploreVM.WalletInfoMatch, isLastItem: Boolean) {
        this.isLastItem = isLastItem
        val name = match.name?.takeIf { it.isNotEmpty() }
        iconView.config(null, name, match.address)
        titleLabel.text = name ?: match.address.formatStartEndAddress()
        subtitleLabel.text = if (name != null) {
            val shortAddress = match.address.formatStartEndAddress()
            match.domain?.let { "$it · $shortAddress" } ?: shortAddress
        } else {
            match.chain.displayName
        }
        setOnClickListener { onTapWalletInfo(match) }
        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLastItem) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        addRippleEffect(
            WColor.BackgroundRipple.color,
            0f,
            if (isLastItem) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
    }
}
