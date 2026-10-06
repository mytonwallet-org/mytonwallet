package org.mytonwallet.app_air.uiswap.screens.tokenTrade

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiswap.screens.swap.views.SwapCexProviderInfoView
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapCexEstimateResponse
import org.mytonwallet.app_air.walletcore.stores.AccountStore

@SuppressLint("ViewConstructor")
class TokenTradeProviderVC(context: Context, private val estimate: MApiSwapCexEstimateResponse) :
    WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "TokenTradeProvider"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayTopBar = false

    private val infoView = SwapCexProviderInfoView(context).apply {
        id = View.generateViewId()
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(estimate.providerName ?: "")
        setupNavBar(true)
        navigationBar?.addCloseButton()

        infoView.setProviderInfo(
            estimate.providerName,
            estimate.cexLabel,
            estimate.termsOfUseUrl,
            estimate.privacyPolicyUrl,
            estimate.amlKycPolicyUrl
        )
        infoView.expanded = true
        view.addView(
            infoView,
            ConstraintLayout.LayoutParams(0, ConstraintLayout.LayoutParams.WRAP_CONTENT)
        )
        view.setConstraints {
            navigationBar?.let { topToBottom(infoView, it, 8f) }
            toCenterX(infoView, 16f)
            toBottom(infoView, 16f)
        }
        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setPadding(0, 0, 0, navigationController?.getSystemBars()?.bottom ?: 0)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(
            WColor.SecondaryBackground.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f
        )
        infoView.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
    }
}
