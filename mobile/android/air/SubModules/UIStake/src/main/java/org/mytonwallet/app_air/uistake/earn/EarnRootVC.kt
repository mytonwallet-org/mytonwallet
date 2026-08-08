package org.mytonwallet.app_air.uistake.earn

import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.core.graphics.toColorInt
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.max
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.AccountSelectorView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.uistake.staking.StakingVC
import org.mytonwallet.app_air.uistake.staking.StakingViewModel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.STAKED_USDE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore

class EarnRootVC(context: Context, private val tokenSlug: String = TONCOIN_SLUG) :
    WViewController(context),
    WalletCore.EventObserver {
    @Suppress("PropertyName")
    override val TAG = "EarnRoot"

    override var displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayTopBar = false

    private val onScrollListener = { recyclerView: RecyclerView ->
        updateBlurViews(recyclerView)
        segmentView.updateBlurViews(recyclerView)
    }

    private val tonVC = EarnVC(
        context = context,
        tokenSlug = TONCOIN_SLUG,
        onScroll = onScrollListener
    )

    private val mycoinVC =
        if (AccountStore.stakingData?.hasActiveStaking(MYCOIN_SLUG) == true) {
            EarnVC(
                context = context,
                tokenSlug = MYCOIN_SLUG,
                onScroll = onScrollListener
            )
        } else {
            null
        }

    private val usdeVC =
        if (BalanceStore.hasTokenInBalances(
                AccountStore.activeAccountId,
                USDE_SLUG,
                STAKED_USDE_SLUG
            )
        ) {
            EarnVC(
                context = context,
                tokenSlug = USDE_SLUG,
                onScroll = onScrollListener
            )
        } else {
            null
        }

    private val segmentView: WSegmentedController by lazy {
        val viewControllers =
            mutableListOf(
                WSegmentedControllerItem(
                    tonVC,
                    null,
                    "#0098EB".toColorInt()
                )
            ).apply {
                if (mycoinVC != null) {
                    add(
                        WSegmentedControllerItem(
                            mycoinVC,
                            null,
                            "#4C84D7".toColorInt()
                        )
                    )
                }
                if (usdeVC != null) {
                    add(
                        WSegmentedControllerItem(
                            usdeVC,
                            null,
                            "#606060".toColorInt()
                        )
                    )
                }
            }
        val segmentedController = WSegmentedController(
            navigationController!!,
            viewControllers,
            defaultSelectedIndex =
                max(
                    0,
                    viewControllers.indexOfFirst {
                        (it.viewController as EarnVC).tokenSlug ==
                            tokenSlug
                    }
                ),
            applySideGutters = false,
            forceCenterTabs = true,
            pilledTabs = true
        )
        segmentedController.addCloseButton()
        segmentedController
    }

    private val accountSelectorView by lazy {
        AccountSelectorView(
            context,
            accountsProvider = { switchableAccounts() },
            onAccountSelected = ::switchAccount
        )
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
        if (mycoinVC == null && usdeVC == null) {
            view.addView(
                titleLabel,
                LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
            )
        }

        view.setConstraints {
            toTopPx(titleLabel, (navigationController?.getSystemBars()?.top ?: 0) + 16.dp)
            toStartPx(titleLabel, systemBarStartInset)
            toEnd(titleLabel)
            allEdges(segmentView)
        }

        if (isAccountSwitchingAllowed()) {
            AccountStore.activeAccount?.let { accountSelectorView.config(it) }
            segmentView.addLeadingView(accountSelectorView, 75.dp, 48.dp)
        }

        WalletCore.registerObserver(this)
        updateTheme()
    }

    private fun switchableAccounts(): List<MAccount> = WalletCore.getAllAccounts().filter {
        it.supportsEarn
    }

    private fun isAccountSwitchingAllowed(): Boolean = !AccountStore.isPushedTemporary &&
        navigationController?.viewControllers?.firstOrNull() == this &&
        switchableAccounts().any { it.accountId != AccountStore.activeAccountId }

    private fun switchAccount(account: MAccount) {
        accountSelectorView.setLoading(true)
        WalletCore.ensureAccountActivated(account.accountId) { accountChanged ->
            if (accountChanged) {
                WalletCore.notifyEvent(
                    WalletEvent.AccountChangedInApp(persistedAccountsModified = false)
                )
            }
            view.post { onAccountSwitched(account) }
        }
    }

    private fun onAccountSwitched(account: MAccount) {
        displayedAccount = DisplayedAccount(account.accountId, isPushedTemporary = false)
        accountSelectorView.setLoading(false)
        accountSelectorView.config(account)
        val activeStakingTokenSlug = AccountStore.stakingData?.activeStakingTokenSlug()
        val nav = navigationController ?: return
        updateWithCrossFade {
            nav.replaceRoot(
                if (activeStakingTokenSlug != null) {
                    EarnRootVC(context, activeStakingTokenSlug)
                } else {
                    StakingVC(context, TONCOIN_SLUG, StakingViewModel.Mode.STAKE)
                }
            )
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        titleLabel.setTextColor(WColor.PrimaryText.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        segmentView.insetsUpdated()
        if (titleLabel.parent != null) {
            view.setConstraints {
                toTopPx(titleLabel, (navigationController?.getSystemBars()?.top ?: 0) + 16.dp)
                toStartPx(titleLabel, systemBarStartInset)
                toEnd(titleLabel)
            }
        }
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
