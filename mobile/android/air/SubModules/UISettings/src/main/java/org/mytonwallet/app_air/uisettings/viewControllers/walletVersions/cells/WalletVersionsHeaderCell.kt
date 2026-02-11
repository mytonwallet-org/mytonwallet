package org.mytonwallet.app_air.uisettings.viewControllers.walletVersions.cells

import android.content.Context
import android.text.SpannableStringBuilder
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class WalletVersionsHeaderCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    private val titleLabel = HeaderCell(context).apply {
        configure(
            LocaleController.getString("Current Wallet Version"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.FIRST_ITEM
        )
    }

    private val walletVersionLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        text = AccountStore.walletVersionsData?.currentVersion
    }

    private val walletAddressLabel = WLabel(context).apply {
        setStyle(14f)
        text =
            SpannableStringBuilder(AccountStore.activeAccount?.tonAddress?.formatStartEndAddress()).apply {
                styleDots()
            }
    }

    private val topContainerView = WView(context).apply {
        addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(walletVersionLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(walletAddressLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toStart(titleLabel)
            toTop(titleLabel)
            toStart(walletVersionLabel, 20f)
            toTop(walletVersionLabel, 48f)
            toStart(walletAddressLabel, 20f)
            toTop(walletAddressLabel, 72f)
            toBottom(walletAddressLabel, 14f)
        }
    }

    private val othersLabel = HeaderCell(context).apply {
        configure(
            LocaleController.getString("Tokens on Other Versions"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.NORMAL
        )
    }

    private val bottomContainerView = WView(context).apply {
        addView(othersLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            toStart(othersLabel)
            toTop(othersLabel)
            toBottom(othersLabel)
        }
    }

    init {
        addView(topContainerView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(bottomContainerView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        setConstraints {
            toTop(topContainerView)
            topToBottom(bottomContainerView, topContainerView, ViewConstants.GAP.toFloat())
            toBottom(bottomContainerView)
        }

        updateTheme()
    }

    override fun updateTheme() {
        topContainerView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.TOOLBAR_RADIUS.dp,
            ViewConstants.BLOCK_RADIUS.dp,
        )
        bottomContainerView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f
        )
        walletVersionLabel.setTextColor(WColor.PrimaryText.color)
        walletAddressLabel.setTextColor(WColor.SecondaryText.color)
    }
}
