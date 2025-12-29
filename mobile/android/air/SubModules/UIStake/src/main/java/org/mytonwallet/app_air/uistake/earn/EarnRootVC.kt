package org.mytonwallet.app_air.uistake.earn

import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import kotlin.math.max

class EarnRootVC(context: Context, private val tokenSlug: String = TONCOIN_SLUG) :
    WViewController(context), WalletCore.EventObserver {
    override val TAG = "EarnRoot"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayTopBar = false

    private val tonVC = EarnVC(context, TONCOIN_SLUG, onScroll = { recyclerView ->
        updateBlurViews(recyclerView)
        segmentView.updateBlurViews(recyclerView)
    })
    private val mycoinVC =
        if (BalanceStore.getBalances(AccountStore.activeAccountId)?.get(MYCOIN_SLUG) != null)
            EarnVC(context, MYCOIN_SLUG, onScroll = { recyclerView ->
                updateBlurViews(recyclerView)
                segmentView.updateBlurViews(recyclerView)
            }) else null
    private val usdeVC =
        if (BalanceStore.getBalances(AccountStore.activeAccountId)?.get(USDE_SLUG) != null)
            EarnVC(context, USDE_SLUG, onScroll = { recyclerView ->
                updateBlurViews(recyclerView)
                segmentView.updateBlurViews(recyclerView)
            }) else null

    private val segmentView: WSegmentedController by lazy {
        val viewControllers = mutableListOf(WSegmentedControllerItem(tonVC, null)).apply {
            if (mycoinVC != null) add(WSegmentedControllerItem(mycoinVC, null))
            if (usdeVC != null) add(WSegmentedControllerItem(usdeVC, null))
        }
        val segmentedController = WSegmentedController(
            navigationController!!,
            viewControllers,
            defaultSelectedIndex =
                max(
                    0,
                    viewControllers.indexOfFirst { (it.viewController as EarnVC).tokenSlug == tokenSlug }
                ),
            applySideGutters = false,
            forceCenterTabs = true
        )
        segmentedController.addCloseButton()
        segmentedController
    }

    val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(22F, WFont.Medium)
        lbl.gravity = Gravity.START
        lbl.text =
            LocaleController.getString("Earn")
        lbl
    }

    override fun setupViews() {
        super.setupViews()

        view.addView(segmentView, LayoutParams(0, 0))
        if (mycoinVC == null) view.addView(
            titleLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )

        view.setConstraints {
            toTopPx(titleLabel, (navigationController?.getSystemBars()?.top ?: 0) + 16.dp)
            toStart(titleLabel, 20f)
            allEdges(segmentView)
        }

        WalletCore.registerObserver(this)
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {}
            is WalletEvent.StakingDataUpdated -> {}
            else -> {}
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        segmentView.onDestroy()
    }
}
