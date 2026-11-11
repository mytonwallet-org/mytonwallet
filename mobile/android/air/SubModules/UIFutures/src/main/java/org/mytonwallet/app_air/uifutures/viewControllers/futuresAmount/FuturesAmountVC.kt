package org.mytonwallet.app_air.uifutures.viewControllers.futuresAmount

import android.annotation.SuppressLint
import android.content.Context
import android.text.SpannableStringBuilder
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.AccountSelectorView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setOnMenuClickListener
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toPriceString
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.FuturesEditPositionView
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.FuturesModifyReviewVC
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.FuturesPositionChange
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.FuturesQuoteResult
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.futuresExplanation
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.prepareFuturesQuote
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeDirection
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsDraftRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsNativePosition
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.PerpsStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
abstract class FuturesAmountVC(context: Context) :
    WViewController(context),
    WalletCore.EventObserver {
    override val shouldDisplayBottomBar = false

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)
    protected val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var estimateJob: Job? = null
    private var reviewJob: Job? = null

    /** Set while a funding trade covers the screen, so balance and price updates do not re-quote. */
    protected var isEstimateRefreshSuspended = false
        private set

    /** Set when a balance change arrives while another screen covers this one. */
    private var hasPendingFundingCheck = false

    protected abstract val model: FuturesAmountModel
    protected abstract val amountView: FuturesEditPositionView
    protected abstract val navTitle: String
    protected abstract val displayName: String

    protected abstract val reviewedPosition: MApiPerpsNativePosition?
    protected abstract val explanationKeys: List<String>

    protected abstract fun menuItems(): List<WMenuPopup.Item>

    protected abstract fun scheduleEstimate()

    /** Checks funding again after a funding trade closes. */
    protected abstract fun refreshFunding()

    /** Checks funding again after a balance change, when funding blocks the order. */
    protected abstract fun refreshBlockedFunding()

    protected abstract fun reviewRequest(): ReviewRequest

    protected class ReviewRequest(
        val draft: MApiPerpsDraftRequest,
        val onRejected: (FuturesQuoteResult) -> Unit
    )

    private val accountSelectorView by lazy {
        AccountSelectorView(context, accountsProvider = {
            emptyList()
        }, onAccountSelected = {}).apply {
            isSwitchable = false
        }
    }

    private val infoButton by lazy {
        WImageButton(context).apply {
            updateColors(WColor.PrimaryLightText, WColor.BackgroundRipple)
            setImageDrawable(
                context.getDrawableCompat(
                    org.mytonwallet.app_air.icons.R.drawable.ic_token_trade_top_info
                )
            )
            setPaddingDp(8)
            contentDescription = LocaleController.getString("Info")
            setOnMenuClickListener { presentInfoMenu() }
        }
    }

    override fun setupViews() {
        super.setupViews()
        setTopBlur(visible = false, animated = false)
        setupNavBar(true)
        navigationBar?.setTitleGravity(Gravity.CENTER)
        navigationBar?.addCloseButton()
        AccountStore.activeAccount?.let { accountSelectorView.config(it) }
        navigationBar?.addLeadingView(
            FrameLayout(context).apply {
                id = View.generateViewId()
                setPaddingRelative(8.dp, 0, 0, 0)
                addView(accountSelectorView)
            }
        )
        navigationBar?.addTrailingView(infoButton, ConstraintLayout.LayoutParams(40.dp, 40.dp))
        infoButton.translationX = 8.dp.toFloat() * if (LocaleController.isRTL) -1f else 1f
        setNavTitle(navTitle)
        updatePriceSubtitle()
        WalletCore.registerObserver(this)

        view.addView(amountView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.setConstraints {
            toTop(amountView)
            toBottom(amountView)
            toCenterX(amountView)
        }
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        amountView.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        amountView.topInset = (navigationController?.getSystemBars()?.top ?: 0) +
            WNavigationBar.DEFAULT_HEIGHT.dp
        amountView.bottomInset = navigationController?.getSystemBars()?.bottom ?: 0
        amountView.setPaddingRelative(systemBarStartInset, 0, systemBarEndInset, 0)
        amountView.requestLayout()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        PerpsStore.watch(this)
    }

    override fun viewDidEnterForeground() {
        super.viewDidEnterForeground()
        if (!hasPendingFundingCheck || isEstimateRefreshSuspended) return
        hasPendingFundingCheck = false
        refreshBlockedFunding()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        PerpsStore.unwatch(this)
    }

    override fun onDestroy() {
        WalletCore.unregisterObserver(this)
        scope.cancel()
        super.onDestroy()
    }

    protected fun updatePriceSubtitle() {
        setNavSubtitle("${LocaleController.getString("Price")} ${model.markPrice.toPriceString()}")
    }

    protected fun onInputChanged() {
        cancelReview()
        amountView.render()
        scheduleEstimate()
    }

    protected fun onFundingSelected() {
        cancelReview()
        amountView.render()
        refreshFunding()
    }

    // Re-quotes on each refresh while shown, as iOS does
    protected fun refreshEstimate() {
        if (model.isPreparingReview || isDisappeared || isEstimateRefreshSuspended) return
        scheduleEstimate()
    }

    /** Opens a trade buying the token a funding hint asks for, then checks funding again. */
    protected fun presentFundsBuy(tokenSlug: String) {
        if (isEstimateRefreshSuspended) return
        if (AccountStore.accountById(displayedAccount.accountId)?.supportsSwap != true) {
            showAlert(null, LocaleController.getString("Swap is not supported on this account."))
            return
        }
        val window = window ?: return
        val token = TokenStore.getToken(tokenSlug) ?: return
        val navVC = object : WNavigationController(window, PresentationConfig.PreferredFullScreen) {
            override val centeredWindowMinHeight: Int
                get() = TokenTradeVC.centeredWindowMinHeight

            override fun onDestroy() {
                super.onDestroy()
                isEstimateRefreshSuspended = false
                hasPendingFundingCheck = false
                refreshFunding()
            }
        }
        val tradeVC = TokenTradeVC(context, MApiSwapAsset.from(token), TokenTradeDirection.BUY)
        tradeVC.displayedAccount = displayedAccount
        tradeVC.isAccountSwitchable = false
        navVC.setRoot(tradeVC)
        cancelEstimate()
        isEstimateRefreshSuspended = true
        window.present(navVC)
    }

    // Balance updates check funding only while nothing covers the screen
    protected fun onBalanceChanged() {
        val isOnTop = navigationController?.viewControllers?.lastOrNull() === this &&
            window?.navigationControllers?.lastOrNull { !it.isDismissed } === navigationController
        if (isOnTop) {
            refreshBlockedFunding()
        } else {
            hasPendingFundingCheck = true
            amountView.render()
        }
    }

    // The funding hint's action appears once its token loads
    protected fun onTokensChanged() {
        if (model.fundsHint != null) amountView.render()
    }

    protected fun estimate(isDebounced: Boolean = true, load: suspend () -> Unit) {
        estimateJob?.cancel()
        estimateJob = scope.launch {
            if (isDebounced) delay(ESTIMATE_DEBOUNCE_MS)
            load()
            amountView.render()
        }
    }

    protected fun cancelEstimate() {
        estimateJob?.cancel()
    }

    protected fun openReview() {
        val accountId = displayedAccount.accountId ?: return
        if (!model.canReview || reviewJob?.isActive == true) return
        val request = reviewRequest()
        model.isPreparingReview = true
        amountView.render()
        reviewJob = scope.launch {
            val result = try {
                prepareFuturesQuote(accountId, request.draft)
            } finally {
                model.isPreparingReview = false
            }
            val quote = result.quote
            if (quote == null || FuturesPositionChange.of(quote) == null) {
                request.onRejected(result)
            } else {
                push(
                    FuturesModifyReviewVC(
                        context,
                        accountId,
                        reviewedPosition,
                        displayName,
                        quote,
                        request.draft
                    )
                )
            }
            amountView.render()
        }
    }

    private fun cancelReview() {
        reviewJob?.cancel()
        model.isPreparingReview = false
    }

    protected fun menuItem(titleKey: String, value: String?) = WMenuPopup.Item(
        WMenuPopup.Item.Config.Item(
            icon = null,
            title = LocaleController.getString(titleKey),
            subtitle = value ?: "—"
        )
    )

    private fun presentInfoMenu() {
        val explanation = explanationView()
        explanation.measure(
            View.MeasureSpec.makeMeasureSpec(INFO_MENU_WIDTH.dp, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val items = menuItems() + WMenuPopup.Item(
            WMenuPopup.Item.Config.CustomView(explanation, explanation.measuredHeight)
        )
        WMenuPopup.present(
            infoButton,
            items,
            popupWidth = INFO_MENU_WIDTH.dp,
            positioning = WMenuPopup.Positioning.ALIGNED,
            windowBackgroundStyle = WMenuPopup.BackgroundStyle.Cutout.fromView(
                infoButton,
                roundRadius = infoButton.height / 2f
            ),
            backdropStyle = WMenuPopup.BackdropStyle.Transparent
        )
    }

    private fun explanationView() = FrameLayout(context).apply {
        addView(
            WLabel(context).apply {
                setStyle(15f)
                setTextColor(WColor.SecondaryText.color)
                text = SpannableStringBuilder().apply {
                    explanationKeys.forEachIndexed { index, key ->
                        if (index > 0) append("\n\n")
                        append(futuresExplanation(key))
                    }
                }
                setPadding(20.dp, 12.dp, 20.dp, 16.dp)
            },
            FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
    }

    private companion object {
        const val ESTIMATE_DEBOUNCE_MS = 300L
        const val INFO_MENU_WIDTH = 260
    }
}
