package org.mytonwallet.app_air.uisettings.viewControllers.walletVersions.cells

import android.content.Context
import android.text.SpannableStringBuilder
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp
import org.mytonwallet.app_air.walletcore.stores.AccountStore

class WalletVersionsHeaderCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    private val titleLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        text =
            LocaleController.getString("Current Wallet Version")
    }

    private val walletVersionLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        text = AccountStore.walletVersionsData?.currentVersion
    }

    private val walletAddressLabel = WLabel(context).apply {
        setStyle(14f)
        text =
            SpannableStringBuilder(AccountStore.activeAccount?.tonAddress?.formatStartEndAddress()).apply {
                updateDotsTypeface()
            }
    }

    private val topContainerView = WView(context).apply {
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(walletVersionLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(walletAddressLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toStart(titleLabel, 20f)
            toTop(titleLabel, 16f)
            toStart(walletVersionLabel, 20f)
            toTop(walletVersionLabel, 62f)
            toStart(walletAddressLabel, 20f)
            toTop(walletAddressLabel, 86f)
            toBottom(walletAddressLabel, 14f)
        }
    }

    private val othersLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        text =
            LocaleController.getString("Tokens on Other Versions")
    }

    private val bottomContainerView = WView(context).apply {
        addView(othersLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toStart(othersLabel, 20f)
            toTop(othersLabel, 16f)
            toBottom(othersLabel, 8f)
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
        if (ThemeManager.uiMode.hasRoundedCorners) {
            topContainerView.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.TOP_RADIUS.dp,
                ViewConstants.BIG_RADIUS.dp,
            )
            bottomContainerView.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BIG_RADIUS.dp,
                0f
            )
        } else {
            topContainerView.background = SeparatorBackgroundDrawable().apply {
                backgroundWColor = WColor.Background
            }
            bottomContainerView.setBackgroundColor(WColor.Background.color)
        }
        titleLabel.setTextColor(WColor.Tint.color)
        walletVersionLabel.setTextColor(WColor.PrimaryText.color)
        walletAddressLabel.setTextColor(WColor.SecondaryText.color)
        othersLabel.setTextColor(WColor.Tint.color)
    }

    fun configure(exploreSite: ApiDapp) {
        titleLabel.text = exploreSite.name
    }
}
