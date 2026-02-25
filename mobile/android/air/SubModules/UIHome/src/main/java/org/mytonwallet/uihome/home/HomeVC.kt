package org.mytonwallet.uihome.home

import android.content.Context
import android.view.MotionEvent
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.webkit.URLUtil
import android.widget.FrameLayout
import android.widget.Toast
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.updateLayoutParams
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.sqscan.screen.QrScannerDialog
import org.mytonwallet.app_air.uicomponents.base.ISortableView
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.executeWithLowPriority
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderSpaceCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.DirectionalTouchHandler
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uireceive.ReceiveVC
import org.mytonwallet.app_air.uisend.send.MultisendLauncher
import org.mytonwallet.app_air.uisend.send.SellWithCardLauncher
import org.mytonwallet.app_air.uisend.send.SendVC
import org.mytonwallet.app_air.uistake.earn.EarnRootVC
import org.mytonwallet.app_air.uistake.earn.EarnViewModel
import org.mytonwallet.app_air.uistake.earn.EarnViewModelFactory
import org.mytonwallet.app_air.uistake.staking.StakingVC
import org.mytonwallet.app_air.uistake.staking.StakingViewModel
import org.mytonwallet.app_air.uiswap.screens.cex.SwapSendAddressOutputVC
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.uitonconnect.TonConnectController
import org.mytonwallet.app_air.uitransaction.viewControllers.transaction.TransactionVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.requestDAppList
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MScreenMode
import org.mytonwallet.app_air.walletcore.models.SwapType
import org.mytonwallet.app_air.walletcore.moshi.ApiSwapStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.uihome.home.views.ActivityListView
import org.mytonwallet.uihome.home.views.UpdateStatusView
import org.mytonwallet.uihome.home.views.header.HomeHeaderView
import org.mytonwallet.uihome.home.views.header.StickyHeaderView
import org.mytonwallet.uihome.walletsTabs.WalletsTabsVC
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.absoluteValue
import kotlin.math.min
import kotlin.math.roundToInt

class HomeVC(context: Context, private val mode: MScreenMode) :
    WViewControllerWithModelStore(context),
    HomeVM.Delegate,
    ActivityListView.DataSource, ActivityListView.Delegate,
    WThemedView, WProtectedView, ISortableView {
    override val TAG = "Home"

    private val px92 = 92.dp

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = mode is MScreenMode.SingleWallet

    override val isSwipeBackAllowed = false
    override val isEdgeSwipeBackAllowed = mode is MScreenMode.SingleWallet

    override val displayedAccount: DisplayedAccount?
        get() {
            return DisplayedAccount(
                homeVM.showingAccount?.accountId,
                mode is MScreenMode.SingleWallet
            )
        }
    // override val shouldMonitorFrames = true

    private val homeVM by lazy {
        HomeVM(mode, this)
    }

    private var rvMode = HomeHeaderView.DEFAULT_MODE

    private val earnToncoinViewModel by lazy {
        ViewModelProvider(
            window!!,
            EarnViewModelFactory(TONCOIN_SLUG)
        )[EarnViewModel.alias(TONCOIN_SLUG), EarnViewModel::class.java]
    }
    private val earnMycoinViewModel by lazy {
        ViewModelProvider(
            window!!,
            EarnViewModelFactory(MYCOIN_SLUG)
        )[EarnViewModel.alias(MYCOIN_SLUG), EarnViewModel::class.java]
    }

    private val tonConnectController by lazy {
        TonConnectController(window!!)
    }

    private fun isSellAllowed(): Boolean {
        return homeVM.showingAccount?.supportsBuyWithCard == true && ConfigStore.isLimited != true
    }

    private var prevActivityListView =
        ActivityListView(
            context,
            WeakReference(this),
            WeakReference(this)
        ).apply {
            isInvisible = true
        }
    private var currentActivityListView =
        ActivityListView(
            context,
            WeakReference(this),
            WeakReference(this)
        )
    private var nextActivityListView =
        ActivityListView(
            context,
            WeakReference(this),
            WeakReference(this)
        ).apply {
            isInvisible = true
        }
    private val allActivityListViews =
        listOf(prevActivityListView, currentActivityListView, nextActivityListView)
    private val activityListViewsContainer = WFrameLayout(context).apply {
        addView(prevActivityListView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(currentActivityListView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(nextActivityListView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    private val headerCell: HeaderSpaceCell?
        get() {
            return currentActivityListView.headerCell
        }
    private val actionsCell: WCell?
        get() {
            return currentActivityListView.actionsCell
        }
    private var swipeItemsOffset = 0
    private var swipeFadeInPercent = 1f
    private var actionsLayoutFadeInPercent = 0f

    private val touchHandler by lazy {
        DirectionalTouchHandler(
            verticalView = activityListViewsContainer,
            horizontalView = headerView,
            interceptedViews = listOf(),
            interceptedByVerticalScrollViews = listOf(),
            isDirectionalScrollAllowed = { isVertical, event ->
                isVertical || (event?.y ?: 0f) < activityListViewHeaderHeight()
            },
            horizontalScrollAngle = 70.0
        ).apply {
            onScrollDetected = { isVertical ->
                if (isVertical) {
                    moveHeaderViewToCell()
                } else {
                    moveHeaderViewToParent()
                }
            }
            onScrollEnd = { wasVertical ->
                if (!wasVertical && headerView.mode == HomeHeaderView.Mode.Expanded) {
                    moveHeaderViewToCell()
                }
            }
        }
    }
    override val view: ContainerView by lazy {
        object : ContainerView(WeakReference(this)) {
            private var isPassingToDirectionalTouchHandler = false
            override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
                if (ev.action == MotionEvent.ACTION_DOWN) {
                    isPassingToDirectionalTouchHandler =
                        headerView.mode == HomeHeaderView.Mode.Expanded && ev.y < activityListViewHeaderHeight()
                    if (!isPassingToDirectionalTouchHandler) {
                        if (headerView.mode == HomeHeaderView.Mode.Expanded) moveHeaderViewToCell()
                    }
                }
                return if (isPassingToDirectionalTouchHandler)
                    touchHandler.dispatchTouch(view, ev) ?: super.dispatchTouchEvent(ev)
                else
                    super.dispatchTouchEvent(ev)
            }
        }
    }

    private val stickyHeaderView = StickyHeaderView(context, mode) { onClick(it) }

    override val headerView: HomeHeaderView by lazy {
        val v = HomeHeaderView(
            window!!,
            if (mode is MScreenMode.SingleWallet) arrayOf(mode.accountId) else null,
            stickyHeaderView.updateStatusView,
            onModeChange = { animated ->
                if (animated) {
                    currentActivityListView.recyclerView.setBounceBackSkipValue(if (rvMode == headerView.mode) 0 else headerView.diffPx.toInt())
                } else {
                    headerModeChanged()
                }
                stickyHeaderView.update(
                    headerView.mode,
                    if (stickyHeaderView.updateStatusView.state != null &&
                        stickyHeaderView.updateStatusView.state !is UpdateStatusView.State.Updated
                    )
                        stickyHeaderView.updateStatusView.state!!
                    else UpdateStatusView.State.Updated(homeVM.showingAccount?.name ?: ""),
                    true
                )
            },
            onExpandPressed = {
                expand()
                allActivityListViews.forEach {
                    it.recyclerView.removeOverScroll()
                }
            },
            onHeaderPressed = {
                scrollToTop()
            },
            onHorizontalScrollListener = { progress, verticalOffset, actionsFadeInPercent ->
                if (currentActivityListView.isInvisible)
                    currentActivityListView.isInvisible = false
                currentActivityListView.updateAlpha(1 - abs(progress))
                if (progress == 0f) {
                    actionsView.translationY = 0f
                    view.post {
                        configureActivityLists(
                            shouldLoadNewWallets = true,
                            skipSkeletonOnCache = true
                        )
                        moveActionsViewToCell()
                    }
                } else {
                    moveActionsViewToParent()
                    actionsView.translationY = swipeItemsOffset.toFloat()
                    endSorting()
                }
                this.swipeFadeInPercent = actionsFadeInPercent
                swipeItemsOffset = verticalOffset
                currentActivityListView.updateHeaderHeights()
                if (progress > 0.02) {
                    nextActivityListView.isInvisible = false
                    nextActivityListView.updateAlpha(progress)
                    nextActivityListView.updateHeaderHeights()
                } else {
                    nextActivityListView.updateAlpha(0f)
                    nextActivityListView.isInvisible = true
                }
                if (progress < -0.02) {
                    prevActivityListView.isInvisible = false
                    prevActivityListView.updateAlpha(-progress)
                    prevActivityListView.updateHeaderHeights()
                } else {
                    prevActivityListView.updateAlpha(0f)
                    prevActivityListView.isInvisible = true
                }
                updateActionsAlpha()
            })
        v.apply {
            background = null
        }
    }

    private var actionsView = HeaderActionsView(
        context,
        HeaderActionsView.headerTabs(context, true),
        onClick = {
            if (currentActivityListView.skeletonVisible)
                return@HeaderActionsView
            onClick(it)
        },
    ).apply {
        setPadding(0, 0, 0, 16.dp)
    }

    private fun openSellWithCard(tokenSlug: String) {
        if (!isSellAllowed()) return
        val activeAccount = headerView.centerAccount ?: homeVM.showingAccount ?: return
        SellWithCardLauncher.launch(
            caller = WeakReference(this),
            account = activeAccount,
            tokenSlug = tokenSlug,
        )
    }

    private fun onClick(identifier: HeaderActionsView.Identifier) {
        when (identifier) {
            HeaderActionsView.Identifier.BACK -> {
                navigationController?.pop()
            }

            HeaderActionsView.Identifier.LOCK_APP -> {
                WalletContextManager.delegate?.lockScreen()
            }

            HeaderActionsView.Identifier.TOGGLE_SENSITIVE_DATA_PROTECTION -> {
                WGlobalStorage.toggleSensitiveDataHidden()
            }

            HeaderActionsView.Identifier.RECEIVE -> {
                val navVC = WNavigationController(window!!)
                navVC.setRoot(
                    ReceiveVC(
                        context,
                        homeVM.showingAccount?.firstChain ?: MBlockchain.ton
                    )
                )
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SEND -> {
                val navVC = WNavigationController(window!!)
                navVC.setRoot(SendVC(context))
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SELL -> {
                openSellWithCard(TONCOIN_SLUG)
            }

            HeaderActionsView.Identifier.MULTISEND -> {
                MultisendLauncher.launch(this)
            }

            HeaderActionsView.Identifier.SWAP -> {
                val navVC = WNavigationController(window!!)
                navVC.setRoot(SwapVC(context))
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SCAN_QR -> {
                if (currentActivityListView.skeletonVisible)
                    return
                QrScannerDialog.build(context) { qr ->
                    for (blockchain in MBlockchain.supportedChains) {
                        if (blockchain.isValidAddress(qr)) {
                            val navVC = WNavigationController(window!!)
                            navVC.setRoot(
                                SendVC(
                                    context, blockchain.nativeSlug, SendVC.InitialValues(
                                        address = qr
                                    )
                                )
                            )
                            window?.present(navVC)
                            return@build
                        }
                    }
                    val validDeeplink = WalletContextManager.delegate?.handleDeeplink(qr)
                    if (validDeeplink == true)
                        return@build
                    if (URLUtil.isValidUrl(qr)) {
                        tonConnectController.connectStart(qr)
                        return@build
                    }
                    Toast.makeText(
                        context,
                        LocaleController.getString("This QR Code is not supported"),
                        Toast.LENGTH_SHORT
                    ).show()
                }.show()
            }

            HeaderActionsView.Identifier.EARN -> {
                if (!homeVM.isGeneralDataAvailable) return

                val activeStakingTokenSlug = AccountStore.stakingData?.activeStakingTokenSlug()
                val navVC = WNavigationController(window!!)
                if (activeStakingTokenSlug != null) {
                    navVC.setRoot(EarnRootVC(context, tokenSlug = activeStakingTokenSlug))
                } else {
                    navVC.setRoot(StakingVC(context, TONCOIN_SLUG, StakingViewModel.Mode.STAKE))
                }
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SCROLL_TO_TOP -> {
                scrollToTop()
            }

            HeaderActionsView.Identifier.WALLET_SETTINGS -> {
                if (headerView.mode == HomeHeaderView.Mode.Collapsed)
                    return
                val navVC = WNavigationController(
                    window!!, WNavigationController.PresentationConfig(
                        overFullScreen = false,
                        isBottomSheet = true
                    )
                )
                navVC.setRoot(
                    WalletsTabsVC(
                        context,
                        WGlobalStorage.getAccountSelectorViewMode() ?: MWalletSettingsViewMode.GRID
                    )
                )
                window?.present(navVC)
            }

            else -> {
                throw Error()
            }
        }
    }

    private val topBlurReversedCornerView = ReversedCornerView(
        context, ReversedCornerView.Config(blurRootView = activityListViewsContainer)
    ).apply {
        isGone = true
    }

    override fun setupViews() {
        super.setupViews()

        view.addView(activityListViewsContainer, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            topBlurReversedCornerView,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                (navigationController?.getSystemBars()?.top ?: 0) +
                    HomeHeaderView.navDefaultHeight +
                    ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()
            )
        )
        view.addView(headerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(stickyHeaderView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.setConstraints {
            toTopPx(stickyHeaderView, navigationController?.getSystemBars()?.top ?: 0)
            toCenterX(stickyHeaderView)
            toTop(topBlurReversedCornerView)
        }

        view.alpha = 0f
        view.post {
            moveActionsViewToCell()
            view.fadeIn()
            allActivityListViews.forEach {
                it.recyclerView.setMaxOverscrollOffset(headerView.diffPx)
            }
        }

        WalletCore.doOnBridgeReady {
            homeVM.setupObservers()
            updateHeaderCards(false)
            updateBalance(false)
            configureAccountViews(shouldLoadNewWallets = true, skipSkeletonOnCache = false)
        }

        if (mode == MScreenMode.Default)
            tonConnectController.onCreate()

        updateTheme()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        topBlurReversedCornerView.resumeBlurring()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        headerView.viewWillDisappear()
    }

    override fun didSetupViews() {
        super.didSetupViews()
        setBottomBlurSeparator(false)
    }

    private fun expand() {
        if (headerView.mode == HomeHeaderView.Mode.Expanded)
            return
        currentActivityListView.expandingProgrammatically = true
        topBlurReversedCornerView.pauseBlurring(false)
        topBlurReversedCornerView.isGone = true
        currentActivityListView.recyclerView.scrollToOverScroll(
            (headerView.expandedContentHeight -
                headerView.collapsedHeight).toInt()
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        homeVM.destroy()
        if (mode is MScreenMode.SingleWallet && AccountStore.isPushedTemporary)
            homeVM.removeTemporaryAccount()
        actionsView.onDestroy()
        headerView.onDestroy()
        tonConnectController.onDestroy()
        allActivityListViews.forEach {
            it.onDestroy()
        }
        currentActivityListView.homeAssetsCell?.onDestroy()
    }

    // Header view is moved to recycler-view cell, to keep over-scroll effect
    fun moveHeaderViewToCell() {
        if (headerView.parent != headerCell &&
            currentActivityListView.recyclerView.computeVerticalScrollOffset() == 0 &&
            headerView.mode == HomeHeaderView.Mode.Expanded
        ) {
            (headerView.parent as? ViewGroup)?.removeView(headerView)
            headerCell?.addView(headerView)
            headerCell?.setConstraints {
                toCenterX(headerView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            }
        }
    }

    // Header view is moved to parent view, to cross-fade content without effecting header
    private fun moveHeaderViewToParent() {
        if (headerView.parent != view) {
            (headerView.parent as? ViewGroup)?.removeView(headerView)
            view.addView(
                headerView,
                ViewGroup.LayoutParams(
                    MATCH_PARENT,
                    headerCell?.height ?: WRAP_CONTENT
                )
            )
            sortViews()
        }
    }

    // Header view is moved to recycler-view cell whenever user overscroll, to keep over-scroll effect
    private fun moveActionsViewToCell() {
        actionsView.updateActions(headerView.centerAccount ?: homeVM.showingAccount)
        view.post {
            if (actionsView.parent != actionsCell) {
                (actionsView.parent as? ViewGroup)?.removeView(actionsView)
                actionsCell?.addView(
                    actionsView,
                    FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                )
            }
        }
    }

    // Actions view is moved to parent view, to cross-fade content without effecting this view
    private fun moveActionsViewToParent() {
        actionsView.updateActions(headerView.centerAccount ?: homeVM.showingAccount)
        if (actionsView.parent != view) {
            (actionsView.parent as? ViewGroup)?.removeView(actionsView)
            view.addView(
                actionsView,
                FrameLayout.LayoutParams(
                    view.width - ViewConstants.HORIZONTAL_PADDINGS.dp * 2,
                    HeaderActionsView.HEIGHT.dp
                )
            )
            view.setConstraints {
                toCenterX(actionsView)
                toTopPx(actionsView, headerView.height)
            }
        }
    }

    // Sort views in hierarchy to keep all the buttons clickable
    private fun sortViews() {
        if (rvMode == HomeHeaderView.Mode.Expanded) {
            stickyHeaderView.bringToFront()
            navigationBar?.bringToFront()
        } else {
            headerView.bringToFront()
        }
    }

    override fun updateScroll(dy: Int, velocity: Float?, isGoingBack: Boolean) {
        if (dy > 1) { // Ignore 1 pixel to prevent ui glitches
            if (headerView.mode == HomeHeaderView.Mode.Collapsed) {
                resumeBlurViews()
                moveHeaderViewToParent()
            }
        } else {
            if (currentActivityListView.recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE ||
                currentActivityListView.recyclerView.getOverScrollOffset() > 0
            ) {
                pauseBlurViews()
            }
        }
        val scrollY =
            dy - (if (rvMode == HomeHeaderView.Mode.Expanded) headerView.diffPx else 0f).roundToInt()
        // Do NOT accept negative scrollY values if user is not dragging anymore and dy >= 0, to prevent ui jumps/glitches.
        val acceptNegativeScrollY =
            dy < 0 ||
                headerView.mode == HomeHeaderView.Mode.Expanded ||
                currentActivityListView.recyclerView.scrollState == RecyclerView.SCROLL_STATE_DRAGGING
        if (!acceptNegativeScrollY && scrollY < 0) {
            currentActivityListView.scrollEnded(0)
            currentActivityListView.recyclerView.stopScroll()
            currentActivityListView.recyclerView.scrollTo(0, 0)
        }
        headerView.updateScroll(
            if (acceptNegativeScrollY) scrollY else scrollY.coerceAtLeast(0),
            velocity,
            isGoingBack
        )
        if (headerView.parent == headerCell) {
            headerView.y = dy.toFloat()
        } else {
            headerView.y = 0f
        }

        actionsLayoutFadeInPercent =
            1 - (if (scrollY > px92) (scrollY - px92) / px92.toFloat() else 0f).coerceIn(0f, 1f)
        updateActionsAlpha()
    }

    override fun scrollToTop() {
        super.scrollToTop()
        currentActivityListView.scrollToTop()
    }

    private val pausedBlurViews: Boolean
        get() {
            return !topBlurReversedCornerView.isPlaying ||
                (bottomReversedCornerView?.let { !it.isPlaying }
                    ?: navigationController?.tabBarController?.pausedBlurViews
                    ?: false)
        }

    override fun pauseBlurViews() {
        if (rvMode == HomeHeaderView.Mode.Expanded ||
            headerView.mode == HomeHeaderView.Mode.Expanded
        ) {
            if (pausedBlurViews)
                return
            topBlurReversedCornerView.pauseBlurring(false)
            topBlurReversedCornerView.isGone = true
            bottomReversedCornerView?.pauseBlurring()
            if (navigationController?.tabBarController?.activeNavigationController == navigationController)
                navigationController?.tabBarController?.pauseBlurring()
        }
    }

    private val resumedBlurViews: Boolean
        get() {
            return topBlurReversedCornerView.isPlaying &&
                (bottomReversedCornerView?.isPlaying
                    ?: navigationController?.tabBarController?.pausedBlurViews?.let { !it }
                    ?: false)
        }

    private fun resumeBlurViews() {
        if (resumedBlurViews)
            return
        topBlurReversedCornerView.isGone = false
        topBlurReversedCornerView.resumeBlurring()
        resumeBottomBlurViews()
    }

    override fun resumeBottomBlurViews() {
        bottomReversedCornerView?.resumeBlurring()
        navigationController?.tabBarController?.resumeBlurring()
    }

    private var minHeaderHeight =
        ((navigationController?.getSystemBars()?.top ?: 0) + HomeHeaderView.navDefaultHeight)

    private fun updateTopReversedCornerViewHeight() {
        topBlurReversedCornerView.updateLayoutParams {
            height = (navigationController?.getSystemBars()?.top ?: 0) +
                HomeHeaderView.navDefaultHeight +
                ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        topBlurReversedCornerView.alpha = 1f
        activityListViewsContainer.setBackgroundColor(WColor.SecondaryBackground.color)
        allActivityListViews.forEach {
            it.updateTheme()
        }
        updateTopReversedCornerViewHeight()
        currentActivityListView.homeAssetsCell?.updateSegmentItemsTheme()
        if (headerView.parent is WCell)
            headerView.updateTheme()
        if (actionsView.parent is WCell)
            actionsView.updateTheme()
    }

    // Configure lists
    var renderedAccounts = ""
    private fun configureActivityLists(
        shouldLoadNewWallets: Boolean,
        skipSkeletonOnCache: Boolean
    ) {
        val activeAccount = headerView.centerAccount ?: homeVM.showingAccount ?: return
        homeVM.loadedAccountId = activeAccount.accountId
        val accountIds = WGlobalStorage.accountIds()
        val activeAccountIndex = accountIds.indexOf(activeAccount.accountId)
        val prevAccountId = accountIds.getOrNull(activeAccountIndex - 1)
        val nextAccountId = accountIds.getOrNull(activeAccountIndex + 1)
        if (shouldLoadNewWallets) {
            val newRenderedAccounts =
                "$prevAccountId${activeAccount.accountId}$nextAccountId"
            if (renderedAccounts == newRenderedAccounts)
                return
            renderedAccounts = newRenderedAccounts
        }

        // Recycle the activity list views to prevent unnecessary `configure` calls
        val activityListViewsCopy =
            mutableListOf(
                prevActivityListView,
                currentActivityListView,
                nextActivityListView
            )

        fun getViewForAccountId(id: String?): ActivityListView<HomeVC>? {
            return activityListViewsCopy.firstOrNull { activityListView ->
                activityListView.showingAccountId == id
            }
        }

        val prevView = getViewForAccountId(prevAccountId)
        if (prevView != null) activityListViewsCopy.remove(prevView)
        val currentView = getViewForAccountId(activeAccount.accountId)
        if (currentView != null) activityListViewsCopy.remove(currentView)
        val nextView = getViewForAccountId(nextAccountId)
        if (nextView != null) activityListViewsCopy.remove(nextView)

        prevActivityListView =
            (prevView ?: activityListViewsCopy.removeFirstOrNull()!!.apply {
                configure(
                    prevAccountId,
                    shouldLoadNewWallets,
                    skipSkeletonOnCache = skipSkeletonOnCache
                )
            }).apply {
                if (swipeItemsOffset == 0)
                    isInvisible = true
                instantScrollToTop()
            }
        currentActivityListView =
            (currentView ?: activityListViewsCopy.removeFirstOrNull()!!.apply {
                configure(
                    activeAccount.accountId,
                    shouldLoadNewWallets,
                    skipSkeletonOnCache = skipSkeletonOnCache
                )
            }).apply {
                isInvisible = false
                instantScrollToTop(shouldLoadNewWallets)
                if (swipeItemsOffset == 0)
                    alpha = 1f
            }
        nextActivityListView = (nextView ?: activityListViewsCopy.removeFirstOrNull()!!.apply {
            configure(
                nextAccountId,
                shouldLoadNewWallets,
                skipSkeletonOnCache = skipSkeletonOnCache
            )
        }).apply {
            if (swipeItemsOffset == 0)
                isInvisible = true
            instantScrollToTop()
        }
    }

    override fun updateProtectedView() {
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        headerView.insetsUpdated()
        minHeaderHeight =
            ((navigationController?.getSystemBars()?.top ?: 0) + HomeHeaderView.navDefaultHeight)
        allActivityListViews.forEach {
            it.insetsUpdated()
        }
        topBlurReversedCornerView.setHorizontalPadding(ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat())
        actionsView.insetsUpdated()
    }

    override fun onTransactionTap(accountId: String, transaction: MApiTransaction) {
        window?.let { window ->
            val isWaitingToPaySwap = (transaction is MApiTransaction.Swap) &&
                transaction.status == ApiSwapStatus.PENDING &&
                transaction.swapType == SwapType.CROSS_CHAIN_TO_WALLET &&
                transaction.cex?.status?.uiStatus == MApiTransaction.UIStatus.PENDING

            val transactionNav: WNavigationController
            if (isWaitingToPaySwap) {
                transactionNav = WNavigationController(window)
                transactionNav.setRoot(
                    SwapSendAddressOutputVC(
                        context,
                        transaction.fromToken!!,
                        transaction.toToken!!,
                        transaction.fromAmount.absoluteValue
                            .toBigInteger(transaction.fromToken!!.decimals),
                        transaction.toAmount
                            .toBigInteger(transaction.toToken!!.decimals),
                        transaction.cex?.payinAddress ?: "",
                        transaction.cex?.transactionId ?: ""
                    )
                )
            } else {
                transactionNav = WNavigationController(
                    window, WNavigationController.PresentationConfig(
                        overFullScreen = false,
                        isBottomSheet = true
                    )
                )
                transactionNav.setRoot(TransactionVC(context, accountId, transaction))
            }
            window.present(transactionNav)
        }
    }

    override fun update(state: UpdateStatusView.State, animated: Boolean) {
        if (homeVM.isGeneralDataAvailable && !homeVM.calledReady) {
            homeVM.calledReady = true
            WalletContextManager.delegate?.walletIsReady()
        }
        val accountNotLoadedYet = !homeVM.isGeneralDataAvailable &&
            state == UpdateStatusView.State.Updating &&
            stickyHeaderView.updateStatusView.state is UpdateStatusView.State.Updated
        if (accountNotLoadedYet)
            return
        headerView.update(state, animated)
        stickyHeaderView.update(headerView.mode, state, animated)
    }

    override fun updateHeaderCards(expand: Boolean) {
        homeVM.showingAccount?.let {
            headerView.updateAccountData(it)
            if (expand) {
                headerView.isExpandAllowed = true
                headerView.expand(animated = false, velocity = null)
                pauseBlurViews()
            } else
                headerView.layoutCardView()
        }
    }

    override fun updateBalance(accountChangedFromOtherScreens: Boolean) {
        if (!homeVM.isGeneralDataAvailable && headerView.isShowingSkeletons) {
            return
        }
        headerView.updateBalance(
            homeVM.showingAccount?.name ?: "",
            !accountChangedFromOtherScreens
        )
    }

    override fun reloadCard() {
        headerView.updateCardImage()
    }

    override fun reloadCardAddress(accountId: String) {
        headerView.updateAddressLabel(accountId)
    }

    override fun transactionsUpdated(isUpdateEvent: Boolean) {
        allActivityListViews.forEach {
            it.transactionsUpdated(isUpdateEvent)
        }
    }

    override fun loadStakingData() {
        if (!homeVM.isGeneralDataAvailable) return

        if (homeVM.showingAccount?.isViewOnly == false)
            executeWithLowPriority {
                earnToncoinViewModel.loadOrRefreshStakingData()
                earnMycoinViewModel.loadOrRefreshStakingData()
            }
    }

    override fun stakingDataUpdated() {
        actionsView.updateActions(headerView.centerAccount ?: homeVM.showingAccount)
    }

    override fun headerModeChanged() {
        rvMode = headerView.mode
        allActivityListViews.forEach {
            it.headerModeChanged()
        }
        sortViews()
    }

    private fun updateActionsAlpha() {
        actionsView.fadeInPercent =
            min(
                swipeFadeInPercent,
                if (headerView.centerAccount?.isViewOnly == true) 0f else actionsLayoutFadeInPercent
            )
    }

    override fun configureAccountViews(
        shouldLoadNewWallets: Boolean,
        skipSkeletonOnCache: Boolean
    ) {
        stickyHeaderView.updateActions()
        accountConfigChanged()
        val account = headerView.centerAccount ?: homeVM.showingAccount
        actionsView.updateActions(account)
        updateActionsAlpha()
        configureActivityLists(shouldLoadNewWallets, skipSkeletonOnCache)
        if (shouldLoadNewWallets) {
            accountNameChanged(
                (headerView.centerAccount ?: homeVM.showingAccount)?.name ?: "",
                false
            )
            currentActivityListView.updateHeaderHeights()
            moveActionsViewToCell()
        }
        loadStakingData()
    }

    // Nft tabs could be updated, should reload tabs
    override fun reloadTabs() {
        currentActivityListView.homeAssetsCell?.reloadTabs(resetSelection = false)
    }

    override fun accountNameChanged(accountName: String, animated: Boolean) {
        headerView.updateAccountName(accountName)
        if (stickyHeaderView.updateStatusView.state is UpdateStatusView.State.Updated) {
            stickyHeaderView.updateStatusView.setState(
                UpdateStatusView.State.Updated(accountName),
                animated
            )
            stickyHeaderView.updateStatusView.setAppearance(
                headerView.mode == HomeHeaderView.Mode.Expanded,
                animated
            )
        } else {
            stickyHeaderView.updateStatusView.setAppearance(true, animated)
        }
    }

    override fun accountConfigChanged() {
        headerView.updateMintIconVisibility()
    }

    override fun seasonalThemeChanged() {
        headerView.updateSeasonalTheme()
    }

    override fun accountWillChange(fromHome: Boolean) {
        configureAccountViews(shouldLoadNewWallets = !fromHome, skipSkeletonOnCache = fromHome)
        if (fromHome) {
            accountNameChanged(headerView.centerAccount?.name ?: "", true)
        } else {
            // Account will change from another screen, invalidate swipeFadeInPercent
            swipeFadeInPercent = 1f
            moveHeaderViewToParent()
        }
    }

    override fun removeScreenFromStack() {
        navigationController?.removeViewController(this)
    }

    override fun popToRoot() {
        navigationController?.popToRoot(false)
    }

    override fun startSorting() {
        currentActivityListView.homeAssetsCell?.startSorting()
        stickyHeaderView.enterActionMode(onResult = { save ->
            currentActivityListView.homeAssetsCell?.endSorting(save)
        })
    }

    override fun endSorting() {
        endSorting(true)
    }

    private fun endSorting(save: Boolean) {
        currentActivityListView.homeAssetsCell?.endSorting(save)
        stickyHeaderView.exitActionMode()
    }

    override fun onBackPressed(): Boolean {
        if (currentActivityListView.homeAssetsCell?.isInDragMode == true) {
            endSorting(false)
            return false
        }
        return super.onBackPressed()
    }

    // Return header height to activity list viewer
    override fun activityListViewHeaderHeight(): Int {
        return (window?.systemBars?.top ?: 0) +
            HomeHeaderView.navDefaultHeight +
            if (rvMode == HomeHeaderView.Mode.Expanded)
                headerView.expandedContentHeight.toInt()
            else
                headerView.collapsedHeight
    }

    override fun swipeItemsOffset(): Int {
        return swipeItemsOffset
    }

    override fun activityListReserveActionsCell(): Boolean {
        return headerView.centerAccount?.isViewOnly != true
    }

    override fun recyclerViewModeValue(): HomeHeaderView.Mode {
        return rvMode
    }
}
