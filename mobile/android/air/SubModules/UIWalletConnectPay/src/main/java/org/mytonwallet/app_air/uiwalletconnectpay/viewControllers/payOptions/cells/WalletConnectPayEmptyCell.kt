package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.payOptions.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

/**
 * Empty-state card shown when the wallet has no eligible tokens for the payment.
 */
@SuppressLint("ViewConstructor")
class WalletConnectPayEmptyCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    private val titleLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        text = LocaleController.getString("You don't have any eligible tokens for this payment")
        gravity = Gravity.CENTER
    }

    private val subtitleLabel = WLabel(context).apply {
        setStyle(14f, WFont.Regular)
        setTextColor(WColor.SecondaryText)
        text = LocaleController.getString("Buy, swap, or receive a supported token to continue.")
        gravity = Gravity.CENTER
    }

    private val card = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        setPadding(16.dp, 15.dp, 16.dp, 15.dp)
        addView(titleLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            subtitleLabel, LinearLayout.LayoutParams(
                MATCH_PARENT, WRAP_CONTENT
            ).apply { topMargin = 8.dp }
        )
    }

    init {
        addView(card, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            toTop(card)
            toCenterX(card)
            toBottom(card)
        }
    }

    override fun updateTheme() {
        titleLabel.setTextColor(WColor.PrimaryText.color)
        card.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
    }

    fun configure(shouldSwitchWallet: Boolean = false) {
        titleLabel.text = LocaleController.getString(
            if (shouldSwitchWallet) "No matching chains" else "You don't have any eligible tokens for this payment"
        )
        subtitleLabel.text = LocaleController.getString(
            if (shouldSwitchWallet) "Select multichain wallet" else "Buy, swap, or receive a supported token to continue."
        )
        updateTheme()
    }
}
