package org.mytonwallet.app_air.uiassets.viewControllers.token

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.View.GONE
import android.view.View.INVISIBLE
import android.view.View.VISIBLE
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.DecelerateInterpolator
import android.widget.LinearLayout
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.math.BigInteger
import java.util.Date
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVC
import org.mytonwallet.app_air.uiassets.viewControllers.token.cells.TokenChartCell
import org.mytonwallet.app_air.uiassets.viewControllers.token.cells.TokenInfoCell
import org.mytonwallet.app_air.uiassets.viewControllers.token.views.TokenHeaderView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter.WRecyclerViewDataSource
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.executeWithLowPriority
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.EmptyCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderSpaceCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonContainer
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonHeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivityCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uireceive.ReceiveVC
import org.mytonwallet.app_air.uisend.send.MultisendLauncher
import org.mytonwallet.app_air.uisend.send.SellWithCardLauncher
import org.mytonwallet.app_air.uisend.send.SendVC
import org.mytonwallet.app_air.uistake.earn.EarnRootVC
import org.mytonwallet.app_air.uistake.staking.StakingVC
import org.mytonwallet.app_air.uistake.staking.StakingViewModel
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.uitransaction.viewControllers.transaction.TransactionVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.isSameDayAs
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class TokenVC(context: Context, private val account: MAccount, var token: MToken) :
    WViewController(context),
    WRecyclerViewDataSource,
    TokenVM.Delegate,
    WThemedView,
    WProtectedView {
    @Suppress("PropertyName")
    override val TAG = "Token"

    private val isLpToken: Boolean
        get() = token.isLpToken

    private val tokenInfoRow: Int
        get() = if (isLpToken) 2 else 3

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = true

    override val displayedAccount =
        DisplayedAccount(account.accountId, AccountStore.isPushedTemporary)

    private val px232 = 232.dp
    private val px116 = 116.dp

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val ACTIONS_CELL = WCell.Type(2)
        val CHART_CELL = WCell.Type(3)
        val TRANSACTION_CELL = WCell.Type(4)
        val EMPTY_VIEW_CELL = WCell.Type(5)
        val TRANSACTION_SMALL_CELL = WCell.Type(6)
        val TRANSACTION_SMALL_FIRST_IN_DAY_CELL = WCell.Type(7)

        val SKELETON_HEADER_CELL = WCell.Type(8)
        val SKELETON_CELL = WCell.Type(9)
        val INFO_CELL = WCell.Type(10)

        const val HEADER_SECTION = 0
        const val TRANSACTION_SECTION = 1
        const val EMPTY_VIEW_SECTION = 2
        const val LOADING_SECTION = 3

        const val LARGE_INT = 10000
    }

    private var tokenChartCell: TokenChartCell? = null
    private var tokenInfoCell: TokenInfoCell? = null

    private val tokenVM by lazy {
        TokenVM(context, account.accountId, token, WeakReference(this))
    }

    private val areTradeActionsAvailable: Boolean
        get() = account.supportsSwap && !isLpToken

    private fun isSellAllowed(): Boolean =
        account.supportsBuyWithCard && ConfigStore.isLimited != true

    private fun openSellWithCard(tokenSlug: String) {
        if (!isSellAllowed()) return
        SellWithCardLauncher.launch(
            caller = WeakReference(this),
            account = account,
            tokenSlug = tokenSlug
        )
    }

    @Volatile
    private var showingTransactions: List<MApiTransaction>? = null

    private var dataSource: WRecyclerViewDataSource? = object : WRecyclerViewDataSource {
        override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 2

        override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int =
            if (section == 0) 1 else 100

        override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
            when (indexPath.section) {
                HEADER_SECTION -> {
                    HEADER_CELL
                }

                else -> {
                    if (indexPath.row == 0) SKELETON_HEADER_CELL else SKELETON_CELL
                }
            }

        override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
            when (cellType) {
                HEADER_CELL -> {
                    HeaderSpaceCell(context).apply { alpha = 0f }
                }

                SKELETON_HEADER_CELL -> {
                    SkeletonHeaderCell(context, 48.dp)
                }

                else -> {
                    SkeletonCell(context)
                }
            }

        override fun recyclerViewConfigureCell(
            rv: RecyclerView,
            cellHolder: WCell.Holder,
            indexPath: IndexPath
        ) {
            when (cellHolder.cell) {
                is HeaderSpaceCell -> {
                    val cellLayoutParams = cellHolder.cell.layoutParams
                    val layoutManager =
                        recyclerView.layoutManager as LinearLayoutManagerAccurateOffset
                    val height =
                        (navigationController?.getSystemBars()?.top ?: 0) +
                            TokenHeaderView.navDefaultHeight +
                            headerView.contentHeight +
                            (tokenChartCell?.height ?: 0) +
                            (
                                tokenInfoCell?.height?.takeIf { it > 0 }
                                    ?: TokenInfoCell.collapsedCellHeight
                                ) +
                            (
                                layoutManager.getItemHeight(1) ?: 0
                                )
                    cellLayoutParams.height = height
                    cellHolder.cell.layoutParams = cellLayoutParams
                }

                is SkeletonHeaderCell -> {
                    (cellHolder.cell as SkeletonHeaderCell).updateTheme()
                }

                is SkeletonCell -> {
                    (cellHolder.cell as SkeletonCell).apply {
                        configure(indexPath.row, isFirst = false, isLast = false)
                        updateTheme()
                    }
                }
            }
        }
    }

    private val rvSkeletonAdapter =
        WRecyclerViewAdapter(
            WeakReference(dataSource),
            arrayOf(HEADER_CELL, SKELETON_HEADER_CELL, SKELETON_CELL)
        )

    private val skeletonRecyclerView: WRecyclerView by lazy {
        val rv = object : WRecyclerView(this) {
            override fun onTouchEvent(event: MotionEvent): Boolean = false
        }
        rv.adapter = rvSkeletonAdapter
        rv.setLayoutManager(LinearLayoutManager(context))
        rv.setItemAnimator(null)
        rv.alpha = 0f
        rv.visibility = GONE
        rv
    }

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                HEADER_CELL,
                ACTIONS_CELL,
                CHART_CELL,
                INFO_CELL,
                TRANSACTION_CELL,
                TRANSACTION_SMALL_CELL,
                TRANSACTION_SMALL_FIRST_IN_DAY_CELL,
                EMPTY_VIEW_CELL,
                SKELETON_CELL
            )
        ).apply {
            setHasStableIds(true)
        }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            if (showingTransactions == null) return
            val layoutManager =
                recyclerView.layoutManager as LinearLayoutManagerAccurateOffset
            updateScroll(
                if (layoutManager.findFirstVisibleItemPosition() < 2) {
                    recyclerView.computeVerticalScrollOffset()
                } else {
                    LARGE_INT
                }
            )
            val computedOffset = recyclerView.computeVerticalScrollOffset()
            if (dy > 2 && computedOffset > 100) {
                hideTradeButtons()
            } else if (dy < -2 || computedOffset < 100) {
                showTradeButtons()
            }
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                executeWithLowPriority {
                    if (recyclerView.scrollState == RecyclerView.SCROLL_STATE_IDLE) {
                        heavyAnimationDone()
                    }
                }
                adjustScrollingPosition()
            } else {
                heavyAnimationInProgress()
                if (recyclerView.computeVerticalScrollOffset() == 0) pauseBlurViews()
            }
        }
    }

    private var headerCell: HeaderSpaceCell? = null

    private val recyclerView = WRecyclerView(context).apply {
        adapter = rvAdapter
        val layoutManager = object : LinearLayoutManagerAccurateOffset(context) {
            override fun canScrollVertically(): Boolean = !skeletonView.isVisible
        }
        layoutManager.isSmoothScrollbarEnabled = true
        setLayoutManager(layoutManager)
        addOnScrollListener(scrollListener)
        setOnOverScrollListener { _, _, offset, _ ->
            updateScroll(
                -offset.toInt() + computeVerticalScrollOffset()
            )
            if (emptyView != null) {
                view.setConstraints {
                    topToBottomPx(emptyView!!, headerView, offset.toInt())
                }
            }
        }
        setItemAnimator(null)
        clipToPadding = false
    }

    override val topBlurView: View?
        get() = topBlurReversedCornerView

    private val topBlurReversedCornerView = ReversedCornerView(
        context,
        ReversedCornerView.Config(
            blurRootView = recyclerView
        )
    )

    private val headerView: TokenHeaderView by lazy {
        navigationBar = run {
            val navBar = WNavigationBar(
                this,
                defaultHeight = TokenHeaderView.NAV_DEFAULT_HEIGHT_DP,
                contentMarginTop = 2.dp
            )
            navBar.setTitleGravity(Gravity.CENTER)
            navBar
        }
        TokenHeaderView(
            navigationController!!,
            navigationBar!!,
            account.accountId,
            token
        ) {
            (tokenVM.tokenInfoState as? TokenVM.TokenInfoState.Details)?.info
        }
    }

    private val skeletonView = SkeletonView(context)

    private var actionsView: HeaderActionsView? = null

    private val buyButton = WButton(context, WButton.Type.PRIMARY).apply {
        text = LocaleController.getString("Buy")
        customTint = WColor.Buy.color
        setOnClickListener { presentSwap(isBuying = true) }
    }

    private val sellButton = WButton(context, WButton.Type.PRIMARY).apply {
        text = LocaleController.getString("Sell")
        customTint = WColor.Sell.color
        setOnClickListener { presentSwap(isBuying = false) }
    }

    private val tradeButtonsView = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.HORIZONTAL
        addView(
            buyButton,
            LinearLayout.LayoutParams(0, 50.dp, 1f)
        )
        addView(
            sellButton,
            LinearLayout.LayoutParams(0, 50.dp, 1f).apply {
                marginStart = 12.dp
            }
        )
    }

    private var tradeButtonsVisibilityFraction = 1f
    private var tradeButtonsVisibilityTarget = 1f
    private var tradeButtonsVisibilityAnimator: ValueAnimator? = null

    private fun tradeButtonsBottomMargin(): Int = 10.dp + (window?.systemBars?.bottom ?: 0)

    private fun updateTradeButtonsLayout() {
        if (tradeButtonsView.parent == null) return
        val horizontalMargin = ViewConstants.HORIZONTAL_PADDINGS.dp + 10.dp
        view.setConstraints {
            toStartPx(
                tradeButtonsView,
                horizontalMargin + additionalTabletPadding + systemBarStartInset
            )
            toEndPx(tradeButtonsView, horizontalMargin + systemBarEndInset)
            toBottomPx(tradeButtonsView, tradeButtonsBottomMargin())
        }
        renderTradeButtonsVisibility()
    }

    private fun updateTradeButtons() {
        sellButton.isVisible =
            (
                BalanceStore.getBalances(account.accountId)?.get(token.slug)
                    ?: BigInteger.ZERO
                ) > BigInteger.ZERO
    }

    private fun renderTradeButtonsVisibility() {
        tradeButtonsView.alpha = tradeButtonsVisibilityFraction
        tradeButtonsView.translationY =
            (50.dp + tradeButtonsBottomMargin()) * (1f - tradeButtonsVisibilityFraction)
    }

    private fun showTradeButtons() {
        if (!areTradeActionsAvailable || tradeButtonsVisibilityTarget == 1f) return
        buyButton.isClickable = true
        sellButton.isClickable = true
        tradeButtonsVisibilityAnimator?.cancel()
        tradeButtonsVisibilityAnimator =
            ValueAnimator.ofFloat(tradeButtonsVisibilityFraction, 1f).apply {
                duration =
                    (
                        AnimationConstants.VERY_QUICK_ANIMATION *
                            (1f - tradeButtonsVisibilityFraction)
                        ).toLong()
                interpolator = DecelerateInterpolator()
                addUpdateListener {
                    tradeButtonsVisibilityFraction = animatedValue as Float
                    renderTradeButtonsVisibility()
                }
                tradeButtonsVisibilityTarget = 1f
                start()
            }
    }

    private fun hideTradeButtons() {
        if (!areTradeActionsAvailable || tradeButtonsVisibilityTarget == 0f) return
        buyButton.isClickable = false
        sellButton.isClickable = false
        tradeButtonsVisibilityAnimator?.cancel()
        tradeButtonsVisibilityAnimator =
            ValueAnimator.ofFloat(tradeButtonsVisibilityFraction, 0f).apply {
                duration =
                    (
                        AnimationConstants.VERY_QUICK_ANIMATION *
                            tradeButtonsVisibilityFraction
                        ).toLong()
                interpolator = DecelerateInterpolator()
                addUpdateListener {
                    tradeButtonsVisibilityFraction = animatedValue as Float
                    renderTradeButtonsVisibility()
                }
                tradeButtonsVisibilityTarget = 0f
                start()
            }
    }

    override fun setupViews() {
        super.setupViews()

        heavyAnimationInProgress()
        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(skeletonRecyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            topBlurReversedCornerView,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                (navigationController?.getSystemBars()?.top ?: 0) +
                    TokenHeaderView.navDefaultHeight +
                    ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()
            )
        )
        view.addView(
            headerView,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                (navigationController?.getSystemBars()?.top ?: 0) +
                    TokenHeaderView.navDefaultHeight + headerView.contentHeight
            )
        )
        headerView.setPaddingLocalized(
            additionalTabletPadding + systemBarStartInset,
            0,
            systemBarEndInset,
            0
        )
        view.addView(navigationBar, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(skeletonView)
        if (areTradeActionsAvailable) {
            view.addView(tradeButtonsView, ViewGroup.LayoutParams(0, 50.dp))
        }
        view.setConstraints {
            allEdges(recyclerView)
            allEdges(skeletonRecyclerView)
            allEdges(skeletonView)
            toTop(topBlurReversedCornerView)
        }
        updateTradeButtonsLayout()
        updateTradeButtons()

        tokenVM.refreshTransactions()
        topBlurReversedCornerView.alpha = 0f

        updateSkeletonState()
        updateTheme()
    }

    override fun didSetupViews() {
        super.didSetupViews()
        if (tradeButtonsView.parent != null) tradeButtonsView.bringToFront()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        heavyAnimationDone()
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    private fun adjustScrollingPosition(): Boolean {
        val scrollOffset = recyclerView.computeVerticalScrollOffset()
        if (scrollOffset in 0..px232) {
            val canGoDown = recyclerView.canScrollVertically(1)
            if (!canGoDown) return true
            val adjustment =
                if (scrollOffset < px116) -scrollOffset else px232 - scrollOffset
            if (adjustment != 0) {
                recyclerView.smoothScrollBy(0, adjustment)
                return true
            }
        }
        return false
    }

    private fun updateSkeletonViews() {
        val skeletonViews = mutableListOf<View>()
        val skeletonViewsRadius = hashMapOf<Int, Float>()
        for (i in 1 until skeletonRecyclerView.childCount) {
            val child = skeletonRecyclerView.getChildAt(i)
            if (child is SkeletonContainer) {
                child.getChildViewMap().forEach {
                    skeletonViews.add(it.key)
                    skeletonViewsRadius[skeletonViews.lastIndex] = it.value
                }
            }
        }
        skeletonView.applyMask(skeletonViews, skeletonViewsRadius)
    }

    private fun pauseBlurViews() {
        topBlurReversedCornerView.pauseBlurring(false)
        bottomReversedCornerView?.pauseBlurring()
        if (navigationController?.tabBarController?.activeNavigationController ==
            navigationController
        ) {
            navigationController?.tabBarController?.pauseBlurring()
        }
    }

    private fun resumeBlurViews() {
        topBlurReversedCornerView.resumeBlurring()
        resumeBottomBlurViews()
    }

    private fun resumeBottomBlurViews() {
        bottomReversedCornerView?.resumeBlurring()
        navigationController?.tabBarController?.resumeBlurring()
    }

    private fun onClick(identifier: HeaderActionsView.Identifier) {
        when (identifier) {
            HeaderActionsView.Identifier.RECEIVE -> {
                val chain = MBlockchain.valueOfOrNull(token.chain) ?: return
                val receiveVC = ReceiveVC.createIfAvailable(context, chain) ?: return
                val navVC = WNavigationController(
                    window!!,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                navVC.setRoot(receiveVC)
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SEND -> {
                val navVC = WNavigationController(
                    window!!,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                navVC.setRoot(SendVC(context, token.slug))
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SELL -> {
                openSellWithCard(token.slug)
            }

            HeaderActionsView.Identifier.MULTISEND -> {
                MultisendLauncher.launch(this)
            }

            HeaderActionsView.Identifier.EARN -> {
                val hasActiveStaking =
                    AccountStore.stakingData?.hasActiveStaking(token.slug) == true
                val navVC = WNavigationController(
                    window!!,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                if (hasActiveStaking) {
                    navVC.setRoot(EarnRootVC(context, token.slug))
                } else {
                    navVC.setRoot(StakingVC(context, token.slug, StakingViewModel.Mode.STAKE))
                }
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SCROLL_TO_TOP -> {
                scrollToTop()
            }

            else -> {}
        }
    }

    private fun presentSwap(isBuying: Boolean) {
        val window = window ?: return
        val selectedAsset = MApiSwapAsset.from(token)
        val navVC = WNavigationController(
            window,
            WNavigationController.PresentationConfig.PreferredFullScreen
        )
        navVC.setRoot(
            SwapVC(
                context,
                defaultSendingToken = selectedAsset.takeUnless { isBuying },
                defaultReceivingToken = selectedAsset.takeIf { isBuying }
            )
        )
        window.present(navVC)
    }

    private var lastDy = -1
    private fun updateScroll(dy: Int) {
        if (dy == lastDy) {
            return
        }
        lastDy = dy
        headerView.updateScroll(dy)
        val actionsLayoutFadeOutPercent =
            max(0f, min(1f, 1 + (headerView.contentHeight - dy.toFloat() - 12.dp) / 92.dp))
        actionsView?.fadeInPercent = actionsLayoutFadeOutPercent
        val alpha = min(
            1f,
            max(
                0f,
                (
                    244.dp - dy + (
                        if (account.accountType ==
                            MAccount.AccountType.VIEW
                        ) {
                            0
                        } else {
                            92.dp
                        }
                        )
                    ) /
                    ViewConstants.GAP.dp.toFloat() -
                    1
            )
        )
        topBlurReversedCornerView.alpha = 1 - alpha
        if (dy > 0) {
            if (headerView.parent == headerCell) {
                view.post {
                    if (headerView.parent == headerCell) {
                        headerCell?.removeView(headerView)
                        view.addView(headerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
                        headerView.setPaddingLocalized(
                            additionalTabletPadding + systemBarStartInset,
                            0,
                            systemBarEndInset,
                            0
                        )
                        skeletonView.bringToFront()
                        navigationBar?.bringToFront()
                        topBlurViewGuideline?.bringToFront()
                    }
                }
            }
            resumeBlurViews()
        } else {
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                pauseBlurViews()
            }
            if (headerView.parent == view && headerCell != null) {
                view.post {
                    if (headerView.parent == view && headerCell != null) {
                        view.removeView(headerView)
                        headerCell?.addView(
                            headerView,
                            ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                        )
                        headerView.setPadding(0)
                        headerCell?.setConstraints {
                            toCenterX(headerView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                        }
                    }
                }
            }
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                pauseBlurViews()
            }
        }
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 4

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            HEADER_SECTION -> tokenInfoRow + 1

            TRANSACTION_SECTION -> if ((showingTransactions?.size ?: 0) > 0) {
                (showingTransactions?.size ?: 0)
            } else {
                0
            }

            EMPTY_VIEW_SECTION -> {
                return if (showingTransactions?.size == 0) 1 else 0
            }

            LOADING_SECTION -> {
                1
            }

            else -> throw Error()
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return when (indexPath.section) {
            HEADER_SECTION -> {
                when (indexPath.row) {
                    0 -> {
                        HEADER_CELL
                    }

                    1 -> {
                        ACTIONS_CELL
                    }

                    tokenInfoRow -> INFO_CELL

                    else -> CHART_CELL
                }
            }

            EMPTY_VIEW_SECTION -> {
                EMPTY_VIEW_CELL
            }

            LOADING_SECTION -> {
                SKELETON_CELL
            }

            else -> {
                val tx = showingTransactions?.getOrNull(indexPath.row)
                return tx?.let { transaction ->
                    if (transaction.isNft ||
                        (transaction as? MApiTransaction.Transaction)?.hasComment == true
                    ) {
                        TRANSACTION_CELL
                    } else if (indexPath.row == 0 || !transaction.dt.isSameDayAs(
                            showingTransactions!![indexPath.row - 1].dt
                        )
                    ) {
                        TRANSACTION_SMALL_FIRST_IN_DAY_CELL
                    } else {
                        TRANSACTION_SMALL_CELL
                    }
                } ?: HEADER_CELL
            }
        }
    }

    private fun onHeightChange(isExpanding: Boolean) {
        resumeBlurViews()
        rvSkeletonAdapter.notifyItemChanged(0)
        // Handle header height updates when recycler-view scrolled to the end and collapsing the chart
        if (!isExpanding) updateScroll(recyclerView.computeVerticalScrollOffset())
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            HEADER_CELL -> {
                if (headerCell == null) headerCell = HeaderSpaceCell(context)
                headerCell!!
            }

            ACTIONS_CELL -> {
                actionsView = HeaderActionsView(
                    context,
                    tabs = HeaderActionsView.headerTabs(context, token.isEarnAvailable)
                        .filterNot { it.identifier == HeaderActionsView.Identifier.SWAP },
                    onClick = {
                        onClick(it)
                    }
                )
                actionsView?.setPadding(0, 0, 0, 16.dp)
                actionsView?.updateActions(account, token.slug)
                if (account.accountType == MAccount.AccountType.VIEW) {
                    actionsView?.updateLayoutParams {
                        height = 0
                    }
                }
                actionsView!!
            }

            CHART_CELL -> {
                if (tokenChartCell == null) {
                    tokenChartCell = TokenChartCell(
                        recyclerView,
                        activePeriod = tokenVM.selectedPeriod,
                        onSelectedPeriodChanged = {
                            tokenVM.selectedPeriod = it
                        },
                        onAgentPrompt = ::openAgent,
                        onHeightChange = { isExpanding, _ ->
                            onHeightChange(isExpanding)
                        }
                    )
                }
                return tokenChartCell!!
            }

            INFO_CELL -> {
                if (tokenInfoCell == null) {
                    tokenInfoCell = TokenInfoCell(
                        recyclerView,
                        onHeightChange = { isExpanding, _ ->
                            onHeightChange(isExpanding)
                        },
                        onShowInfo = { title, text ->
                            showAlert(title, text)
                        }
                    )
                }
                tokenInfoCell!!
            }

            TRANSACTION_CELL -> {
                val cell =
                    ActivityCell(recyclerView, withoutTagAndComment = false, isFirstInDay = null)
                cell.allowNftMenu = true
                cell.onTap = { transaction ->
                    onTransactionTap(transaction)
                }
                cell
            }

            TRANSACTION_SMALL_CELL -> {
                val cell =
                    ActivityCell(recyclerView, withoutTagAndComment = true, isFirstInDay = false)
                cell.allowNftMenu = true
                cell.onTap = { transaction ->
                    onTransactionTap(transaction)
                }
                cell
            }

            TRANSACTION_SMALL_FIRST_IN_DAY_CELL -> {
                val cell =
                    ActivityCell(recyclerView, withoutTagAndComment = true, isFirstInDay = true)
                cell.allowNftMenu = true
                cell.onTap = { transaction ->
                    onTransactionTap(transaction)
                }
                cell
            }

            EMPTY_VIEW_CELL -> {
                EmptyCell(context)
            }

            SKELETON_CELL -> {
                SkeletonCell(context)
            }

            else -> {
                throw Error()
            }
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        if (indexPath.section == TRANSACTION_SECTION &&
            indexPath.row >= (showingTransactions?.size ?: 0) - 20
        ) {
            tokenVM.activityLoader?.useBudgetTransactions()
        }

        when (indexPath.section) {
            HEADER_SECTION -> {
                when (indexPath.row) {
                    0 -> {
                        val cellLayoutParams = RecyclerView.LayoutParams(MATCH_PARENT, 0)
                        cellLayoutParams.height =
                            (navigationController?.getSystemBars()?.top ?: 0) +
                            TokenHeaderView.navDefaultHeight +
                            headerView.contentHeight
                        cellHolder.cell.layoutParams = cellLayoutParams
                    }

                    1 -> {
                    }

                    tokenInfoRow -> {
                        val cell = cellHolder.cell as TokenInfoCell
                        cell.configure(tokenVM.tokenInfoState)
                    }

                    else -> {
                        val cell = cellHolder.cell as TokenChartCell
                        cell.configure(token, tokenVM.historyData, tokenVM.selectedPeriod)
                    }
                }
                return
            }

            TRANSACTION_SECTION -> {
                if (indexPath.row < (showingTransactions?.size ?: 0)) {
                    val homeTransactionCell = cellHolder.cell as ActivityCell
                    val transaction = showingTransactions!![indexPath.row]
                    val isFirstInDay =
                        (indexPath.row == showingTransactions!!.size - 1) ||
                            (
                                !transaction.dt.isSameDayAs(
                                    showingTransactions!![indexPath.row + 1].dt
                                ) && tokenVM.activityLoader?.loadedAll != false
                                )
                    homeTransactionCell.configure(
                        transaction,
                        account.accountId,
                        account.isMultichain,
                        ActivityCell.Positioning(
                            isFirst = indexPath.row == 0,
                            isFirstInDay = indexPath.row == 0 || !transaction.dt.isSameDayAs(
                                showingTransactions!![indexPath.row - 1].dt
                            ),
                            isLastInDay = isFirstInDay,
                            isLast =
                                indexPath.row == showingTransactions!!.size - 1 &&
                                    tokenVM.activityLoader?.loadedAll != false,
                            isAdded = isApplyingUpdate &&
                                oldTransactions?.contains(transaction.getStableId()) == false,
                            isAddedAsNewDay =
                                isFirstInDay &&
                                    (
                                        oldTransactionsFirstDt == null ||
                                            !transaction.dt.isSameDayAs(
                                                oldTransactionsFirstDt!!
                                            )
                                        )
                        )
                    )
                } else {
                    val layoutParams: ViewGroup.LayoutParams = cellHolder.cell.layoutParams
                    layoutParams.height =
                        if (tokenVM.activityLoader?.loadedAll != false) ViewConstants.GAP.dp else 0
                    cellHolder.cell.layoutParams = layoutParams
                }
            }

            EMPTY_VIEW_SECTION -> {
                (cellHolder.cell as EmptyCell).let { cell ->
                    cell.layoutParams = cell.layoutParams.apply {
                        height = (this@TokenVC.view.parent as View).height - (
                            (navigationController?.getSystemBars()?.bottom ?: 0) +
                                headerView.contentHeight
                            )
                    }
                }
            }

            LOADING_SECTION -> {
                (cellHolder.cell as SkeletonCell).apply {
                    configure(indexPath.row, false, isLast = true)
                    updateTheme()
                    visibility =
                        if (tokenVM.activityLoader?.showingTransactions == null ||
                            tokenVM.activityLoader?.loadedAll == true
                        ) {
                            INVISIBLE
                        } else {
                            VISIBLE
                        }
                }
            }
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        when (indexPath.section) {
            TRANSACTION_SECTION -> {
                if (indexPath.row < (showingTransactions?.size ?: 0)) {
                    return showingTransactions!![indexPath.row].getStableId()
                }
            }
        }
        return super.recyclerViewCellItemId(rv, indexPath)
    }

    override fun updateTheme() {
        super.updateTheme()
        recyclerView.setBackgroundColor(WColor.SecondaryBackground.color)
        updateSkeletonState()
        headerView.updateTheme()
        actionsView?.updateTheme()
        tokenInfoCell?.updateTheme()
        rvAdapter.reloadData()
    }

    override fun updateProtectedView() {
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val bottomInset = (navigationController?.bottomInset ?: 0) +
            if (areTradeActionsAvailable) 60.dp else 0
        recyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            bottomInset
        )
        skeletonRecyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset,
            skeletonRecyclerView.paddingTop,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            skeletonRecyclerView.paddingBottom
        )
        if (topBlurReversedCornerView.layoutParams != null) {
            topBlurReversedCornerView.updateLayoutParams {
                height = (navigationController?.getSystemBars()?.top ?: 0) +
                    TokenHeaderView.navDefaultHeight +
                    ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()
            }
        }
        if (headerView.layoutParams != null) {
            headerView.updateLayoutParams {
                height = (navigationController?.getSystemBars()?.top ?: 0) +
                    TokenHeaderView.navDefaultHeight + headerView.contentHeight
            }
        }
        if (headerView.parent == headerCell) {
            headerCell?.setConstraints {
                toCenterX(headerView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            }
        } else {
            headerView.setPaddingLocalized(
                additionalTabletPadding + systemBarStartInset,
                0,
                systemBarEndInset,
                0
            )
        }
        rvAdapter.notifyItemChanged(0)
        rvSkeletonAdapter.notifyItemChanged(0)
        actionsView?.insetsUpdated()
        updateTradeButtonsLayout()
    }

    private fun onTransactionTap(transaction: MApiTransaction) {
        window?.let { window ->
            val transactionNav = WNavigationController(
                window,
                WNavigationController.PresentationConfig(
                    style = WNavigationController.PresentationStyle.BottomSheet
                )
            )
            transactionNav.setRoot(TransactionVC(context, account.accountId, transaction))
            window.present(transactionNav)
        }
    }

    private fun openAgent(prompt: String) {
        val navigationController = navigationController ?: return
        if (navigationController.tabBarController?.switchToAgent(prompt) == true) return
        navigationController.push(AgentVC(context, initialPrompt = prompt))
    }

    private var emptyView: WEmptyView? = null
    private var oldTransactions: Set<String>? = null
    private var oldTransactionsFirstDt: Date? = null
    private var isApplyingUpdate = false

    override fun dataUpdated(isUpdateEvent: Boolean) {
        showingTransactions = tokenVM.activityLoader?.showingTransactions
        updateSkeletonState()
        isApplyingUpdate = isUpdateEvent && oldTransactions != null
        rvAdapter.reloadData()
        view.post {
            isApplyingUpdate = false
            showingTransactions?.let { showingTransactions ->
                oldTransactions =
                    showingTransactions.map { it.getStableId() }.toSet()
                oldTransactionsFirstDt = showingTransactions.firstOrNull()?.dt
            } ?: run {
                oldTransactions = null
                oldTransactionsFirstDt = null
            }
        }
    }

    override fun loadedAll() {
        dataUpdated(isUpdateEvent = false)
    }

    override fun priceDataUpdated() {
        token = TokenStore.getToken(token.slug) ?: token
        updateSkeletonState()
        updateTradeButtons()
        headerView.reloadData()
        if (!isLpToken) {
            recyclerView.post {
                rvAdapter.notifyItemChanged(2)
            }
        }
    }

    override fun tokenInfoUpdated() {
        recyclerView.post {
            rvAdapter.notifyItemChanged(tokenInfoRow)
            rvSkeletonAdapter.notifyItemChanged(0)
        }
    }

    override fun stateChanged() {
    }

    override fun accountChanged() {
        if (isDestroyed) return
        if (!AccountStore.isPushedTemporary && AccountStore.activeAccountId != account.accountId) {
            navigationController?.pop(animated = false)
        }
    }

    override fun accountRemoved() {
        navigationController?.removeViewController(this)
    }

    override fun cacheNotFound() {
        rvSkeletonAdapter.reloadData()
        view.post {
            updateSkeletonViews()
            skeletonAlpha = 1f
            skeletonRecyclerView.visibility = VISIBLE
            skeletonRecyclerView.alpha = 1f
            skeletonView.startAnimating()
        }
    }

    private var skeletonAlpha = 0f
    private fun updateSkeletonState() {
        if (skeletonAlpha > 0f &&
            showingTransactions != null &&
            (
                (showingTransactions?.size ?: 0) > 0 ||
                    tokenVM.activityLoader?.loadedAll == true
                )
        ) {
            skeletonAlpha = 0f
            skeletonView.fadeOut(onCompletion = {
                skeletonView.stopAnimating()
            })
            skeletonRecyclerView.fadeOut {
                if (skeletonAlpha == 0f) skeletonRecyclerView.visibility = GONE
            }
        }
    }

    override fun onDestroy() {
        tradeButtonsVisibilityAnimator?.cancel()
        buyButton.setOnClickListener(null)
        sellButton.setOnClickListener(null)
        super.onDestroy()
        dataSource = null
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.setOnOverScrollListener(null)
        recyclerView.layoutManager = null
        recyclerView.adapter = null
        recyclerView.removeAllViews()
        skeletonRecyclerView.adapter = null
        skeletonRecyclerView.removeAllViews()
        tokenChartCell?.onDestroy()
        tokenInfoCell?.onDestroy()
        actionsView?.onDestroy()
        tokenVM.onDestroy()
    }
}
