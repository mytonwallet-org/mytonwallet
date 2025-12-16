package org.mytonwallet.uihome.home

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.view.View.GONE
import android.view.View.INVISIBLE
import android.view.View.VISIBLE
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.DecelerateInterpolator
import android.webkit.URLUtil
import android.widget.Toast
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import me.everything.android.ui.overscroll.IOverScrollState
import org.mytonwallet.app_air.sqscan.screen.QrScannerDialog
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.ISortableView
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter.WRecyclerViewDataSource
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.executeWithLowPriority
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.EmptyCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderSpaceCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonContainer
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonHeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivityCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uireceive.ReceiveVC
import org.mytonwallet.app_air.uisend.send.SendVC
import org.mytonwallet.app_air.uistake.earn.EarnRootVC
import org.mytonwallet.app_air.uistake.earn.EarnViewModel
import org.mytonwallet.app_air.uistake.earn.EarnViewModelFactory
import org.mytonwallet.app_air.uiswap.screens.cex.SwapSendAddressOutputVC
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.uitonconnect.TonConnectController
import org.mytonwallet.app_air.uitransaction.viewControllers.TransactionVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.isSameDayAs
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MScreenMode
import org.mytonwallet.app_air.walletcore.models.SwapType
import org.mytonwallet.app_air.walletcore.moshi.ApiSwapStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.uihome.home.cells.HomeAssetsCell
import org.mytonwallet.uihome.home.views.UpdateStatusView
import org.mytonwallet.uihome.home.views.header.HomeHeaderView
import org.mytonwallet.uihome.home.views.header.StickyHeaderView
import org.mytonwallet.uihome.walletsTabs.WalletsTabsVC
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class HomeVC(context: Context, private val mode: MScreenMode) :
    WViewControllerWithModelStore(context),
    WRecyclerViewDataSource, HomeVM.Delegate, WThemedView, WProtectedView, ISortableView {
    override val TAG = "Home"

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val ACTIONS_CELL = WCell.Type(2)
        val ASSETS_CELL = WCell.Type(3)
        val TRANSACTION_CELL = WCell.Type(4)
        val EMPTY_VIEW_CELL = WCell.Type(5)
        val BLACK_CELL = WCell.Type(6)
        val TRANSACTION_SMALL_CELL = WCell.Type(7)

        val SKELETON_HEADER_CELL = WCell.Type(7)
        val SKELETON_CELL = WCell.Type(8)

        const val HEADER_SECTION = 0
        const val ASSETS_SECTION = 1
        const val TRANSACTION_SECTION = 2
        const val EMPTY_VIEW_SECTION = 3
        const val LOADING_SECTION = 4

        const val LARGE_INT = 10000
    }

    private val px92 = 92.dp

    private val px46 = 46.dp

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
        HomeVM(context, mode, this)
    }

    private var rvMode = HomeHeaderView.DEFAULT_MODE
    private var showActions = false

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

    @Volatile
    private var showingTransactions: List<MApiTransaction>? = null

    private val tonConnectController by lazy {
        TonConnectController(window!!)
    }

    private var homeAssetsCell: HomeAssetsCell? = null

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                HEADER_CELL,
                ACTIONS_CELL,
                ASSETS_CELL,
                TRANSACTION_CELL,
                TRANSACTION_SMALL_CELL,
                EMPTY_VIEW_CELL,
                BLACK_CELL,
                SKELETON_CELL
            )
        ).apply {
            setHasStableIds(true)
        }

    private var ignoreScrolls = false
    private var expandingProgrammatically = false
    private var headerCell: HeaderSpaceCell? = null
    private var swipeItemsOffset = 0
    private var skeletonEmptyHeaderCell: WCell? = null
    private var skeletonAlphaMinValue = 0f
    private var skeletonAlphaFromLoadValue = 0f
    private var swipeFadeOutPercent = 1f
    private var actionsLayoutFadeOutPercent = 0f
    private var scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            if (ignoreScrolls)
                return
            val firstVisibleItem =
                (recyclerView.layoutManager as LinearLayoutManagerAccurateOffset).findFirstVisibleItemPosition()
            val computedOffset =
                if (firstVisibleItem < 2) recyclerView.computeVerticalScrollOffset() else LARGE_INT
            val isHeaderFullyCollapsed = (headerView.mode == HomeHeaderView.Mode.Collapsed &&
                (rvMode == HomeHeaderView.Mode.Collapsed || computedOffset > headerView.diffPx + 100.dp))
            if (isHeaderFullyCollapsed && dy > 3 && computedOffset > 100.dp) {
                navigationController?.tabBarController?.scrollingDown()
            } else if (dy < -3 || computedOffset < 100.dp) {
                navigationController?.tabBarController?.scrollingUp()
            }
            updateScroll(computedOffset)
            //endSorting()
        }

        private var prevState = RecyclerView.SCROLL_STATE_IDLE
        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (newState == RecyclerView.SCROLL_STATE_DRAGGING && prevState == RecyclerView.SCROLL_STATE_SETTLING) {
                // Scrolling again, without going to idle => end previous scroll
                scrollEnded()
            }
            if (newState == RecyclerView.SCROLL_STATE_SETTLING || newState == RecyclerView.SCROLL_STATE_IDLE) {
                this@HomeVC.recyclerView.setBounceBackSkipValue(0)
                headerView.isExpandAllowed = false
                ignoreScrolls =
                    rvMode == HomeHeaderView.Mode.Expanded &&
                        headerView.mode == HomeHeaderView.Mode.Collapsed &&
                        recyclerView.computeVerticalScrollOffset() < headerView.diffPx
                if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                    scrollEnded()
                } else {
                    // Usual fling should be stopped, if the header is collapsed partially.
                    if (rvMode == HomeHeaderView.Mode.Expanded &&
                        headerView.mode == HomeHeaderView.Mode.Collapsed &&
                        recyclerView.computeVerticalScrollOffset() < headerView.diffPx
                    ) {
                        recyclerView.stopScroll()
                        scrollEnded()
                    }
                }
            }
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                heavyAnimationInProgress()
                if (recyclerView.computeVerticalScrollOffset() == 0) {
                    pauseBlurViews()
                }
            } else {
                executeWithLowPriority {
                    if (recyclerView.scrollState == RecyclerView.SCROLL_STATE_IDLE)
                        heavyAnimationDone()
                }
            }
            prevState = newState
        }
    }
    val rvLayoutManager = object : LinearLayoutManagerAccurateOffset(context) {
        override fun canScrollVertically(): Boolean {
            return !skeletonView.isVisible
        }
    }.apply {
        isSmoothScrollbarEnabled = true
    }
    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.clipChildren = false
        rv.clipToPadding = false
        rv.adapter = rvAdapter
        rv.setLayoutManager(rvLayoutManager)
        rv.addOnScrollListener(scrollListener)
        rv.setOnOverScrollListener { isTouchActive, newState, suggestedOffset, velocity ->
            if (showingTransactions == null || !homeVM.isGeneralDataAvailable)
                return@setOnOverScrollListener
            var offset = suggestedOffset
            if (
                (suggestedOffset > 0f && headerView.mode == HomeHeaderView.Mode.Expanded && headerView.mode == rvMode)
            ) {
                offset = 0f
                recyclerView.removeOverScroll()
            }
            if (newState == IOverScrollState.STATE_IDLE) {
                heavyAnimationDone()
            } else {
                heavyAnimationInProgress()
            }
            val isGoingBack = newState == IOverScrollState.STATE_BOUNCE_BACK
            if (isGoingBack && rvMode != headerView.mode) {
                val prevOverscroll = recyclerView.getOverScrollOffset()
                if (headerView.mode == HomeHeaderView.Mode.Expanded) {
                    recyclerView.getOverScrollOffset()
                    val newOffset =
                        if (!expandingProgrammatically) (headerView.diffPx - prevOverscroll).toInt() else 0
                    expandingProgrammatically = false
                    ignoreScrolls = true
                    recyclerView.scrollBy(0, newOffset)
                    recyclerView.post {
                        recyclerView.smoothScrollBy(0, -recyclerView.computeVerticalScrollOffset())
                    }
                } else {
                    val newOffset =
                        (headerView.collapsedHeight - headerView.expandedContentHeight - prevOverscroll).toInt()
                    ignoreScrolls = true
                    recyclerView.scrollBy(0, newOffset)
                    recyclerView.smoothScrollBy(0, -recyclerView.computeVerticalScrollOffset())
                }
                headerModeChanged()
                if (offset == 0f) {
                    ignoreScrolls = false
                }
                return@setOnOverScrollListener
            }
            if (offset == 0f)
                ignoreScrolls = false
            updateScroll(
                -offset.toInt() + recyclerView.computeVerticalScrollOffset(),
                velocity,
                isGoingBack
            )
            headerView.isExpandAllowed = isTouchActive
        }
        rv.onFlingListener = object : RecyclerView.OnFlingListener() {
            override fun onFling(velocityX: Int, velocityY: Int): Boolean {
                return if (headerView.mode == HomeHeaderView.Mode.Expanded)
                    adjustScrollingPosition()
                else
                    false
            }
        }
        rv.descendantFocusability = RecyclerView.FOCUS_BLOCK_DESCENDANTS
        rv.setPadding(0, 0, 0, navigationController?.getSystemBars()?.bottom ?: 0)
        rv.clipToPadding = false
        rv.setItemAnimator(null)
        rv
    }

    private val dataSource = object : WRecyclerViewDataSource {
        override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
            return 2
        }

        override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
            return if (section == 0) 1 else 100
        }

        override fun recyclerViewCellType(
            rv: RecyclerView,
            indexPath: IndexPath
        ): WCell.Type {
            return when (indexPath.section) {
                HEADER_SECTION -> {
                    HEADER_CELL
                }

                else -> {
                    return if (indexPath.row == 0) SKELETON_HEADER_CELL else SKELETON_CELL
                }
            }
        }

        override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
            return when (cellType) {
                HEADER_CELL -> {
                    skeletonEmptyHeaderCell = WCell(context)
                    skeletonEmptyHeaderCell!!
                }

                SKELETON_HEADER_CELL -> {
                    SkeletonHeaderCell(context)
                }

                else -> {
                    SkeletonCell(context)
                }
            }
        }

        override fun recyclerViewConfigureCell(
            rv: RecyclerView,
            cellHolder: WCell.Holder,
            indexPath: IndexPath
        ) {
            if (indexPath.section == 0) {
                updateSkeletonHeaderCellHeight()
                return
            }
            when (cellHolder.cell) {
                is SkeletonHeaderCell -> {
                    (cellHolder.cell as SkeletonHeaderCell).updateTheme()
                }

                is SkeletonCell -> {
                    (cellHolder.cell as SkeletonCell).apply {
                        configure(indexPath.row, isFirst = false, isLast = false)
                        updateTheme()
                    }
                }

                else -> {
                    (cellHolder.cell as? WThemedView)?.updateTheme()
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
            @SuppressLint("ClickableViewAccessibility")
            override fun onTouchEvent(event: MotionEvent): Boolean {
                return false
            }
        }
        rv.adapter = rvSkeletonAdapter
        rv.setLayoutManager(LinearLayoutManager(context))
        rv.setItemAnimator(null)
        rv.alpha = 0f
        rv.isGone = true
        rv
    }

    private val stickyHeaderView = StickyHeaderView(context, mode) { onClick(it) }

    private val headerView: HomeHeaderView by lazy {
        val v = HomeHeaderView(
            window!!,
            if (mode is MScreenMode.SingleWallet) arrayOf(mode.accountId) else null,
            stickyHeaderView.updateStatusView,
            onModeChange = { animated ->
                if (animated) {
                    recyclerView.setBounceBackSkipValue(if (rvMode == headerView.mode) 0 else headerView.diffPx.toInt())
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
                recyclerView.removeOverScroll()
            },
            onHeaderPressed = {
                scrollToTop()
            },
            onHorizontalScrollListener = { contentAlpha, verticalOffset, actionsFadeOutPercent ->
                this.skeletonAlphaMinValue = 1 - contentAlpha
                this.swipeFadeOutPercent = actionsFadeOutPercent
                if (skeletonAlphaMinValue < 0.02)
                    skeletonAlphaMinValue = 0f
                swipeItemsOffset = verticalOffset
                updateHeaderCellHeight()
                updateSkeletonHeaderCellHeight()
                applySkeletonAlpha()
                actionsView?.fadeOutPercent = actionsFadeOutPercent
            })
        v.apply {
            if (!ThemeManager.uiMode.hasRoundedCorners)
                setBackgroundColor(WColor.Background.color)
            else
                background = null
        }
    }

    private var actionsView: HeaderActionsView? = null

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

            HeaderActionsView.Identifier.SWAP -> {
                val navVC = WNavigationController(window!!)
                navVC.setRoot(SwapVC(context))
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SCAN_QR -> {
                if (skeletonVisible)
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

                val navVC = WNavigationController(window!!)
                navVC.setRoot(EarnRootVC(context))
                window?.present(navVC)
            }

            HeaderActionsView.Identifier.SCROLL_TO_TOP -> {
                scrollToTop()
            }

            HeaderActionsView.Identifier.WALLET_SETTINGS -> {
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
        context, ReversedCornerView.Config(blurRootView = recyclerView)
    ).apply {
        if (!ThemeManager.uiMode.hasRoundedCorners)
            alpha = 0f
        isGone = true
    }

    private val skeletonView = SkeletonView(context)

    override fun setupViews() {
        super.setupViews()

        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(skeletonRecyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            topBlurReversedCornerView,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                (navigationController?.getSystemBars()?.top ?: 0) +
                    HomeHeaderView.navDefaultHeight +
                    ViewConstants.BAR_ROUNDS.dp.roundToInt()
            )
        )
        view.addView(headerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(stickyHeaderView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(skeletonView)
        view.setConstraints {
            allEdges(recyclerView)
            allEdges(skeletonRecyclerView)
            allEdges(skeletonView)
            toTopPx(stickyHeaderView, navigationController?.getSystemBars()?.top ?: 0)
            toCenterX(stickyHeaderView)
            toTop(topBlurReversedCornerView)
        }

        updateSkeletonViews()

        view.alpha = 0f
        view.post {
            view.fadeIn()
            recyclerView.setMaxOverscrollOffset(headerView.diffPx)
        }

        WalletCore.doOnBridgeReady {
            homeVM.delegateIsReady()
            homeVM.initWalletInfo()
        }

        tonConnectController.onCreate()

        updateTheme()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        homeAssetsCell?.configure()
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
        expandingProgrammatically = true
        topBlurReversedCornerView.pauseBlurring(false)
        topBlurReversedCornerView.isGone = true
        recyclerView.scrollToOverScroll(
            (headerView.expandedContentHeight -
                headerView.collapsedHeight).toInt()
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        homeVM.destroy()
        if (mode is MScreenMode.SingleWallet && AccountStore.isPushedTemporary)
            homeVM.removeTemporaryAccount()
        actionsView?.onDestroy()
        headerView.onDestroy()
        tonConnectController.onDestroy()
        recyclerView.setOnOverScrollListener(null)
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.layoutManager = null
        recyclerView.onFlingListener = null
        recyclerView.adapter = null
        recyclerView.removeAllViews()
        skeletonRecyclerView.adapter = null
        skeletonRecyclerView.removeAllViews()
        homeAssetsCell?.onDestroy()
    }

    private fun scrollEnded(overrideOffset: Int? = null) {
        if (rvMode != headerView.mode) {
            headerModeChanged()
            if (rvLayoutManager.findFirstVisibleItemPosition() == 0) {
                // Correct the scroll offset of the recycler view
                val correctionOffset = headerView.diffPx
                val scrollOffset = overrideOffset ?: recyclerView.computeVerticalScrollOffset()
                if (correctionOffset > scrollOffset) {
                    // Go to over-scroll
                    recyclerView.scrollBy(0, -correctionOffset.toInt())
                    if (scrollOffset != 0) {
                        this@HomeVC.recyclerView.comeBackFromOverScrollValue((correctionOffset - scrollOffset).toInt())
                    }
                } else {
                    if (rvLayoutManager.findLastVisibleItemPosition() < rvAdapter.itemCount - 1) {
                        recyclerView.scrollBy(
                            0,
                            -correctionOffset.toInt()
                        )
                        adjustScrollingPosition()
                    }
                }
            }
        } else {
            adjustScrollingPosition()
            if (headerView.mode == HomeHeaderView.Mode.Expanded)
                this@HomeVC.recyclerView.removeOverScroll()
        }
    }

    private fun updateScroll(dy: Int, velocity: Float? = null, isGoingBack: Boolean = false) {
        if (dy > 1) { // Ignore 1 pixel to prevent ui glitches
            if (headerView.parent == headerCell) {
                view.post {
                    if (headerView.parent == headerCell) {
                        headerCell?.removeView(headerView)
                        view.addView(headerView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
                        stickyHeaderView.bringToFront()
                        skeletonView.bringToFront()
                        navigationBar?.bringToFront()
                        topBlurViewGuideline?.bringToFront()
                        updateScroll(dy, velocity, isGoingBack)
                    }
                }
            }
            if (headerView.mode == HomeHeaderView.Mode.Collapsed) {
                resumeBlurViews()
            }
        } else {
            if (rvMode == HomeHeaderView.Mode.Expanded &&
                headerView.parent == view &&
                headerCell != null
            ) {
                view.post {
                    if (rvMode == HomeHeaderView.Mode.Expanded &&
                        headerView.parent == view &&
                        headerCell != null
                    ) {
                        view.removeView(headerView)
                        headerCell?.addView(
                            headerView,
                            ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                        )
                        headerCell?.setConstraints {
                            toCenterX(headerView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                        }
                        updateScroll(dy, velocity, isGoingBack)
                    }
                }
            }
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE || recyclerView.getOverScrollOffset() > 0) {
                pauseBlurViews()
            }
        }
        val scrollY =
            dy - (if (rvMode == HomeHeaderView.Mode.Expanded) headerView.diffPx else 0f).roundToInt()
        // Do NOT accept negative scrollY values if user is not dragging anymore and dy >= 0, to prevent ui jumps/glitches.
        val acceptNegativeScrollY =
            dy < 0 || headerView.mode == HomeHeaderView.Mode.Expanded || recyclerView.scrollState == RecyclerView.SCROLL_STATE_DRAGGING
        if (!acceptNegativeScrollY && scrollY < 0) {
            scrollEnded(0)
            recyclerView.stopScroll()
            recyclerView.scrollTo(0, 0)
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
        headerHeightChanged()

        actionsLayoutFadeOutPercent =
            (if (scrollY > px92) (scrollY - px92) / px92.toFloat() else 0f).coerceIn(0f, 1f)
        updateActionsAlpha()
    }

    override fun scrollToTop() {
        super.scrollToTop()
        if (recyclerView.computeVerticalScrollOffset() > 0) {
            recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
        } else {
            homeAssetsCell?.scrollToFirst()
        }
    }

    override fun instantScrollToTop() {
        if (view.isAttachedToWindow && recyclerView.computeVerticalScrollOffset() == 0)
            return
        (recyclerView.layoutManager as LinearLayoutManager).scrollToPositionWithOffset(0, 0)
        updateScroll(0)
        rvAdapter.reloadData()
    }

    private fun adjustScrollingPosition(): Boolean {
        val scrollOffset = recyclerView.computeVerticalScrollOffset()
        when (rvMode) {
            HomeHeaderView.Mode.Expanded -> {
                if (scrollOffset > 0 && headerView.mode == HomeHeaderView.Mode.Expanded) {
                    recyclerView.smoothScrollBy(0, -scrollOffset)
                    return true
                }
            }

            HomeHeaderView.Mode.Collapsed -> {
                if (scrollOffset in 0..px92) {
                    val canGoDown = recyclerView.canScrollVertically(1)
                    if (!canGoDown)
                        return true
                    val adjustment =
                        if (scrollOffset < px46) -scrollOffset else px92 - scrollOffset
                    if (adjustment != 0) {
                        recyclerView.smoothScrollBy(0, adjustment)
                        return true
                    }
                }
            }
        }
        return false
    }

    private fun pauseBlurViews() {
        if (rvMode == HomeHeaderView.Mode.Expanded ||
            headerView.mode == HomeHeaderView.Mode.Expanded
        ) {
            topBlurReversedCornerView.isGone = true
            topBlurReversedCornerView.pauseBlurring(false)
            bottomReversedCornerView?.pauseBlurring()
            navigationController?.tabBarController?.pauseBlurring()
        }
    }

    private fun resumeBlurViews() {
        topBlurReversedCornerView.isGone = false
        topBlurReversedCornerView.resumeBlurring()
        resumeBottomBlurViews()
    }

    private fun resumeBottomBlurViews() {
        bottomReversedCornerView?.resumeBlurring()
        navigationController?.tabBarController?.resumeBlurring()
    }

    private var minHeaderHeight =
        ((navigationController?.getSystemBars()?.top ?: 0) + HomeHeaderView.navDefaultHeight)

    private fun headerHeightChanged(themeChanged: Boolean = false) {
        if (ThemeManager.uiMode.hasRoundedCorners) {
            if (themeChanged) {
                topBlurReversedCornerView.alpha = 1f
                headerView.background = null
                headerView.updateTheme()
            }
            return
        }
        val headerHeight = headerView.height
        val progress = (headerHeight - minHeaderHeight) / ViewConstants.GAP.dp.toFloat() - 1
        val topBlurAlpha = 1 - progress.coerceIn(0f, 1f)
        if (themeChanged || topBlurAlpha != topBlurReversedCornerView.alpha) {
            if (topBlurAlpha == 0f)
                headerView.setBackgroundColor(WColor.Background.color)
            else
                headerView.background = null
            topBlurReversedCornerView.alpha = topBlurAlpha
        }
    }

    private fun updateSkeletonViews() {
        val skeletonViews = mutableListOf<View>()
        val skeletonViewsRadius = hashMapOf<Int, Float>()
        for (i in 1 until skeletonRecyclerView.childCount) {
            val child = skeletonRecyclerView.getChildAt(i)
            if (child is SkeletonContainer)
                child.getChildViewMap().forEach {
                    skeletonViews.add(it.key)
                    skeletonViewsRadius[skeletonViews.lastIndex] = it.value
                }
        }
        skeletonView.applyMask(skeletonViews, skeletonViewsRadius)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return if (homeVM.isGeneralDataAvailable) 5 else 1
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            HEADER_SECTION -> {
                val newShowActions =
                    headerView.centerAccount?.accountType != MAccount.AccountType.VIEW
                if (showActions != newShowActions) {
                    showActions = newShowActions
                    updateHeaderCellHeight()
                }
                if (showActions) 2 else 1
            }

            ASSETS_SECTION -> if (homeVM.isGeneralDataAvailable) 2 else 0

            TRANSACTION_SECTION -> if (homeVM.isGeneralDataAvailable && (showingTransactions?.size
                    ?: 0) > 0
            ) showingTransactions!!.size else 0

            EMPTY_VIEW_SECTION -> {
                return if (
                    showingTransactions?.isEmpty() == true &&
                    homeVM.isGeneralDataAvailable
                ) 1 else 0
            }

            LOADING_SECTION -> {
                return 1
            }

            else -> throw Error()
        }
    }

    override fun recyclerViewCellType(
        rv: RecyclerView,
        indexPath: IndexPath
    ): WCell.Type {
        return when (indexPath.section) {
            HEADER_SECTION -> {
                if (indexPath.row == 0)
                    HEADER_CELL
                else
                    ACTIONS_CELL
            }

            ASSETS_SECTION -> {
                if (indexPath.row == 0)
                    ASSETS_CELL
                else
                    BLACK_CELL
            }

            EMPTY_VIEW_SECTION -> {
                EMPTY_VIEW_CELL
            }

            LOADING_SECTION -> {
                SKELETON_CELL
            }

            else -> {
                if (indexPath.row < showingTransactions!!.size) {
                    showingTransactions!![indexPath.row].let { transaction ->
                        if (transaction.isNft ||
                            (transaction as? MApiTransaction.Transaction)?.hasComment == true
                        ) TRANSACTION_CELL else TRANSACTION_SMALL_CELL
                    }
                } else
                    BLACK_CELL
            }
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            HEADER_CELL -> {
                if (headerCell == null)
                    headerCell = HeaderSpaceCell(context)
                headerCell!!
            }

            BLACK_CELL -> {
                WCell(context)
            }

            ACTIONS_CELL -> {
                actionsView = HeaderActionsView(
                    context,
                    HeaderActionsView.headerTabs(context, true),
                    onClick = {
                        if (skeletonVisible)
                            return@HeaderActionsView
                        onClick(it)
                    })
                actionsView?.setPadding(0, 0, 0, 16.dp)
                actionsView?.updateActions(headerView.centerAccount ?: homeVM.showingAccount)
                actionsView!!
            }

            ASSETS_CELL -> {
                HomeAssetsCell(
                    context,
                    window = window!!,
                    navigationController = navigationController!!,
                    screenMode = mode,
                    heightChanged = {
                        resumeBottomBlurViews()
                    },
                    onAssetsShown = {
                        homeVM.assetsShown = true
                        updateSkeletonState()
                    },
                    onReorderingRequested = {
                        startSorting()
                    },
                    onForceEndReorderingRequested = {
                        endSorting()
                    }
                )
            }

            TRANSACTION_CELL -> {
                val cell = ActivityCell(recyclerView, withoutTagAndComment = false)
                cell.onTap = { transaction ->
                    onTransactionTap(transaction)
                }
                cell
            }

            TRANSACTION_SMALL_CELL -> {
                val cell = ActivityCell(recyclerView, withoutTagAndComment = true)
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

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        return when (indexPath.section) {
            HEADER_SECTION -> {
                "header"
            }

            TRANSACTION_SECTION -> {
                if (indexPath.row < (showingTransactions?.size ?: 0))
                    showingTransactions!![indexPath.row].id
                else
                    null
            }

            else ->
                null
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
            homeVM.activityLoaderHelper?.useBudgetTransactions()
        }

        when (indexPath.section) {
            HEADER_SECTION -> {
                when (indexPath.row) {
                    0 -> {
                        updateHeaderCellHeight()
                    }

                    1 -> {
                    }
                }
                (cellHolder.cell as? WThemedView)?.updateTheme()
                return
            }

            ASSETS_SECTION -> {
                if (indexPath.row == 0) {
                    homeAssetsCell = cellHolder.cell as HomeAssetsCell
                    homeAssetsCell?.visibility =
                        if (showingTransactions == null) INVISIBLE else VISIBLE
                    homeAssetsCell?.configure()
                } else {
                    val layoutParams: ViewGroup.LayoutParams = cellHolder.cell.layoutParams
                    layoutParams.height = ViewConstants.GAP.dp
                    cellHolder.cell.layoutParams = layoutParams
                }
            }

            TRANSACTION_SECTION -> {
                if (indexPath.row < showingTransactions!!.size) {
                    val transactionCell = cellHolder.cell as ActivityCell
                    val transaction = showingTransactions!![indexPath.row]
                    transactionCell.configure(
                        transaction,
                        homeVM.showingAccount!!.accountId,
                        indexPath.row == 0,
                        indexPath.row == 0 || !transaction.dt.isSameDayAs(showingTransactions!![indexPath.row - 1].dt),
                        (indexPath.row == showingTransactions!!.size - 1) || !transaction.dt.isSameDayAs(
                            showingTransactions!![indexPath.row + 1].dt
                        ),
                        indexPath.row == showingTransactions!!.size - 1 && homeVM.activityLoaderHelper?.loadedAll != false
                    )
                } else {
                    val layoutParams: ViewGroup.LayoutParams = cellHolder.cell.layoutParams
                    layoutParams.height =
                        if (homeVM.activityLoaderHelper?.loadedAll != false) ViewConstants.GAP.dp else 0
                    cellHolder.cell.layoutParams = layoutParams
                }
            }

            EMPTY_VIEW_SECTION -> {
                (cellHolder.cell as EmptyCell).let { cell ->
                    cell.layoutParams = cell.layoutParams.apply {
                        height = (this@HomeVC.view.parent as View).height - (
                            (navigationController?.getSystemBars()?.top ?: 0) +
                                (navigationController?.getSystemBars()?.bottom ?: 0) +
                                75.dp + // TabBar
                                HomeHeaderView.navDefaultHeight +
                                ViewConstants.GAP.dp +
                                (homeAssetsCell?.height ?: 0)
                            )
                    }
                }
            }

            LOADING_SECTION -> {
                (cellHolder.cell as SkeletonCell).apply {
                    configure(indexPath.row, false, isLast = true)
                    updateTheme()
                    visibility =
                        if (homeVM.activityLoaderHelper?.showingTransactions == null ||
                            homeVM.activityLoaderHelper?.loadedAll == true
                        ) INVISIBLE else VISIBLE
                }
            }
        }
    }

    private fun updateHeaderCellHeight() {
        val newHeight = headerView.collapsedMinHeight +
            headerView.collapsedHeight +
            newTopPadding +
            swipeItemsOffset
        headerCell?.layoutParams = headerCell!!.layoutParams.apply {
            height = newHeight
        }
    }

    private fun updateSkeletonHeaderCellHeight() {
        skeletonEmptyHeaderCell?.layoutParams = skeletonEmptyHeaderCell?.layoutParams?.apply {
            height =
                (window?.systemBars?.top ?: 0) + HomeHeaderView.navDefaultHeight +
                    (if (rvMode == HomeHeaderView.Mode.Expanded)
                        headerView.expandedContentHeight.toInt()
                    else
                        headerView.collapsedHeight) +
                    swipeItemsOffset +
                    (if (headerView.centerAccount?.accountType == MAccount.AccountType.VIEW) 0 else HeaderActionsView.HEIGHT.dp) +
                    (if (ThemeManager.uiMode.hasRoundedCorners) 0 else ViewConstants.GAP.dp)
        }
    }

    private fun updateTopReversedCornerViewHeight() {
        topBlurReversedCornerView.updateLayoutParams {
            height = (navigationController?.getSystemBars()?.top ?: 0) +
                HomeHeaderView.navDefaultHeight +
                ViewConstants.BAR_ROUNDS.dp.roundToInt()
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        headerHeightChanged(themeChanged = true)
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        updateSkeletonState()
        rvAdapter.updateTheme()
        rvSkeletonAdapter.updateTheme()
        updateTopReversedCornerViewHeight()
        homeAssetsCell?.updateSegmentItemsTheme()
    }

    override fun updateProtectedView() {
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        headerView.insetsUpdated()
        minHeaderHeight =
            ((navigationController?.getSystemBars()?.top ?: 0) + HomeHeaderView.navDefaultHeight)
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            recyclerView.paddingTop,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            navigationController?.getSystemBars()?.bottom ?: 0
        )
        skeletonRecyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            skeletonRecyclerView.paddingTop,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            skeletonRecyclerView.paddingBottom
        )
        topBlurReversedCornerView.setHorizontalPadding(ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat())
        actionsView?.insetsUpdated()
    }

    private fun onTransactionTap(transaction: MApiTransaction) {
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
                        transaction.fromAmount.toDouble()
                            .toBigInteger(transaction.fromToken!!.decimals),
                        transaction.toAmount.toDouble()
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
                transactionNav.setRoot(TransactionVC(context, transaction))
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
        if (!homeVM.isGeneralDataAvailable && headerView.isShowingSkeletons)
            return
        headerView.updateBalance(
            homeVM.showingAccount?.name ?: "",
            !accountChangedFromOtherScreens
        )
    }

    override fun reloadCard() {
        headerView.updateCardImage()
    }

    override fun transactionsUpdated(isUpdateEvent: Boolean) {
        showingTransactions = homeVM.activityLoaderHelper?.showingTransactions
        updateSkeletonState()
        val shouldReloadAssetsCellHeight = homeAssetsCell?.isDraggingCollectible != true
        if (shouldReloadAssetsCellHeight)
            rvAdapter.reloadData()
        else
            reloadTransactions()
    }

    private fun reloadTransactions() {
        val startInt =
            recyclerViewNumberOfItems(recyclerView, HEADER_SECTION) +
                recyclerViewNumberOfItems(recyclerView, ASSETS_SECTION)
        val count =
            recyclerViewNumberOfItems(recyclerView, TRANSACTION_SECTION) +
                recyclerViewNumberOfItems(recyclerView, EMPTY_VIEW_SECTION) +
                recyclerViewNumberOfItems(recyclerView, LOADING_SECTION)
        if (count > 0)
            rvAdapter.reloadRange(startInt, count)
    }

    override fun loadStakingData() {
        if (!homeVM.isGeneralDataAvailable) return

        if (homeVM.showingAccount?.isViewOnly == false)
            executeWithLowPriority {
                earnToncoinViewModel.loadOrRefreshStakingData()
                earnMycoinViewModel.loadOrRefreshStakingData()
            }
    }

    override fun cacheNotFound() {
        updateSkeletonState()
    }

    override fun loadedAll() {
        rvAdapter.reloadData()
    }

    override fun stakingDataUpdated() {
    }

    private var newTopPadding = 0
    private fun headerModeChanged() {
        rvMode = headerView.mode
        newTopPadding =
            (if (rvMode == HomeHeaderView.Mode.Expanded) headerView.expandedContentHeight - headerView.collapsedHeight else 0f).roundToInt()
        updateHeaderCellHeight()
        updateSkeletonHeaderCellHeight()
        skeletonRecyclerView.post {
            rvSkeletonAdapter.notifyItemChanged(0)
        }
        if (headerView.mode == HomeHeaderView.Mode.Collapsed) {
            recyclerView.setupOverScroll()
            recyclerView.setMaxOverscrollOffset(headerView.diffPx)
        }
    }

    private val skeletonVisible: Boolean
        get() {
            return skeletonAlphaFromLoadValue > 0 && hideSkeletonAnimation?.isRunning != true
        }

    private fun updateSkeletonState() {
        if (skeletonAlphaFromLoadValue > 0 &&
            showingTransactions != null &&
            homeVM.isGeneralDataAvailable &&
            homeVM.assetsShown &&
            ((showingTransactions?.size ?: 0) > 0 ||
                homeVM.activityLoaderHelper?.loadedAll == true)
        ) {
            hideSkeletons()
        } else if (!skeletonVisible && (showingTransactions == null || !homeVM.isGeneralDataAvailable)) {
            showSkeletons()
        }
    }

    private var skeletonsShownOnce = false
    private fun showSkeletons() {
        fun show() {
            if (!skeletonVisible)
                return
            applySkeletonAlpha()
        }
        hideSkeletonAnimation?.cancel()
        skeletonAlphaFromLoadValue = 1f
        if (!skeletonsShownOnce) {
            view.post {
                rvSkeletonAdapter.reloadData()
                view.post {
                    show()
                    skeletonsShownOnce = true
                }
            }
        } else {
            rvSkeletonAdapter.reloadData()
            show()
        }
    }

    private var hideSkeletonAnimation: ValueAnimator? = null
    private fun hideSkeletons() {
        if (skeletonAlphaFromLoadValue == 0f || hideSkeletonAnimation?.isRunning == true)
            return
        hideSkeletonAnimation = ValueAnimator.ofFloat(skeletonAlphaFromLoadValue, 0f).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = DecelerateInterpolator()
            addUpdateListener { animation ->
                skeletonAlphaFromLoadValue = animation.animatedValue as Float
                applySkeletonAlpha()
            }
            start()
        }
    }

    private fun applySkeletonAlpha() {
        val finalAlpha = max(skeletonAlphaFromLoadValue, skeletonAlphaMinValue)
        skeletonRecyclerView.alpha = finalAlpha
        skeletonView.alpha = finalAlpha

        if (finalAlpha > 0 && skeletonRecyclerView.isGone) {
            skeletonRecyclerView.isGone = false
            updateSkeletonViews()
            skeletonView.animate().cancel()
            skeletonView.startAnimating()
        } else if (finalAlpha == 0f && !skeletonRecyclerView.isGone) {
            if (skeletonView.isAnimating)
                skeletonView.stopAnimating()
            else
                skeletonView.visibility = GONE
            skeletonRecyclerView.visibility = GONE
        }
    }

    private fun updateActionsAlpha() {
        actionsView?.fadeOutPercent =
            min(
                swipeFadeOutPercent,
                if (headerView.centerAccount?.isViewOnly == true) 0f else 1 - actionsLayoutFadeOutPercent
            )
    }

    override fun updateActionsView() {
        stickyHeaderView.updateActions()
        actionsView?.updateActions(headerView.centerAccount ?: homeVM.showingAccount)
        updateActionsAlpha()
    }

    override fun reloadTabs(accountChanged: Boolean) {
        homeAssetsCell?.reloadTabs(resetSelection = accountChanged)
    }

    override fun accountNameChanged(accountName: String, animated: Boolean) {
        headerView.updateAccountName(accountName)
        if (stickyHeaderView.updateStatusView.state is UpdateStatusView.State.Updated)
            stickyHeaderView.updateStatusView.setState(
                UpdateStatusView.State.Updated(
                    if (headerView.mode == HomeHeaderView.Mode.Expanded)
                        accountName
                    else
                        ""
                ), animated
            )
    }

    override fun accountConfigChanged() {
        headerView.updateMintIconVisibility()
    }

    override fun accountWillChange() {
        showSkeletons()
        accountNameChanged(headerView.centerAccount?.name ?: "", true)
        updateActionsView()
        if (headerView.changingAccountTo == null)
            swipeFadeOutPercent =
                1f // Account will change from another screen, invalidate swipeFadeOutPercent
    }

    override fun removeScreenFromStack() {
        navigationController?.removeViewController(this)
    }

    override fun popToRoot() {
        navigationController?.popToRoot(false)
    }

    override fun startSorting() {
        homeAssetsCell?.startSorting()
        stickyHeaderView.enterActionMode(onResult = { save ->
            homeAssetsCell?.endSorting(save)
        })
    }

    override fun endSorting() {
        endSorting(true)
    }

    private fun endSorting(save: Boolean) {
        homeAssetsCell?.endSorting(save)
        stickyHeaderView.exitActionMode()
    }

    override fun onBackPressed(): Boolean {
        if (homeAssetsCell?.isInDragMode == true) {
            endSorting(false)
            return false
        }
        return super.onBackPressed()
    }
}
