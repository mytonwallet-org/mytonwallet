package org.mytonwallet.uihome.home.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import androidx.core.animation.doOnCancel
import androidx.core.animation.doOnEnd
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import me.everything.android.ui.overscroll.IOverScrollState
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WActionBar.TitleAnimationMode
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.executeWithLowPriority
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.commonViews.TabletHeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.EmptyCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderSpaceCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonContainer
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonHeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivityCell
import org.mytonwallet.app_air.uiassets.viewControllers.views.MultisigWalletWarningView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.utils.isSameDayAs
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.helpers.ActivityLoader
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.helpers.IActivityLoader
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.uihome.home.cells.HomeAssetsVCPool
import org.mytonwallet.uihome.home.cells.HomePhoneAssetsCell
import org.mytonwallet.uihome.home.cells.HomeTabletAssetsCell
import org.mytonwallet.uihome.home.cells.HomeTabletAssetsSkeletonCell
import org.mytonwallet.uihome.home.cells.IHomeAssetsCell
import org.mytonwallet.uihome.home.views.header.HomeHeaderView
import java.lang.ref.WeakReference
import java.util.Date

@SuppressLint("ViewConstructor")
class ActivityListView<T>(
    context: Context,
    private val dataSourceRef: WeakReference<T>,
    private val delegateRef: WeakReference<Delegate>
) :
    WFrameLayout(context), WThemedView,
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    IActivityLoader.Delegate where T : WViewController, T : ActivityListView.DataSource {

    val delegate: Delegate?
        get() {
            return delegateRef.get()
        }

    val dataSource: T?
        get() {
            return dataSourceRef.get()
        }

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val ACTIONS_CELL = WCell.Type(2)
        val ASSETS_CELL = WCell.Type(3)
        val TRANSACTION_CELL = WCell.Type(4)
        val EMPTY_VIEW_CELL = WCell.Type(5)
        val BLACK_CELL = WCell.Type(6)
        val TRANSACTION_SMALL_CELL = WCell.Type(7)
        val TRANSACTION_SMALL_FIRST_IN_DAY_CELL = WCell.Type(8)

        val SKELETON_HEADER_CELL = WCell.Type(9)
        val SKELETON_CELL = WCell.Type(10)
        val TABLET_ASSETS_SKELETON_CELL = WCell.Type(11)
        val MULTISIG_WARNING_CELL = WCell.Type(12)

        const val HEADER_SECTION = 0
        const val MULTISIG_WARNING_SECTION = 1
        const val ASSETS_SECTION = 2
        const val TRANSACTION_SECTION = 3
        const val EMPTY_VIEW_SECTION = 4
        const val LOADING_SECTION = 5

        const val LARGE_INT = 10000
    }

    // DATA SOURCE /////////////////////////////////////////////////////////////////////////////////
    interface DataSource {
        fun activityListViewHeaderHeight(): Int
        fun swipeItemsOffset(): Int
        fun activityListReserveActionsCell(): Boolean
        fun activityListActionsCellHeight(): Int = HeaderActionsView.HEIGHT.dp
        fun activityListReserveAssetsCell(): Boolean = true
        fun recyclerViewModeValue(): HomeHeaderView.Mode
        val phoneHeaderView: HomeHeaderView
        val isWideHome: Boolean
    }

    val additionalTabletPadding: Int
        get() {
            return if (dataSourceRef.get()?.isWideHome == true)
                ViewConstants.ADDITIONAL_TABLET_PADDING
            else
                0
        }

    interface Delegate {
        fun updateScroll(dy: Int, velocity: Float? = null, isGoingBack: Boolean = false)
        fun headerModeChanged()
        fun startSorting()
        fun endSorting()
        fun startSelectionMode(selectedCount: Int, shouldShowTransferActions: Boolean)
        fun updateSelectionMode(
            selectedCount: Int,
            animationMode: TitleAnimationMode?,
            shouldShowTransferActions: Boolean
        )

        fun endSelectionMode()
        fun onTransactionTap(accountId: String, transaction: MApiTransaction)
        fun pauseBlurViews()
        fun resumeBottomBlurViews()
        fun onHeaderAction(identifier: HeaderActionsView.Identifier)

        fun onTopItemHorizontalScroll()
    }

    // PUBLIC //////////////////////////////////////////////////////////////////////////////////////
    var expandingProgrammatically = false
    var isInstantSwitchingAccount = false

    fun configure(accountId: String?, shouldLoadNewWallets: Boolean, skipSkeletonOnCache: Boolean) {
        if (showingAccountId == accountId)
            return
        assetsShown = false
        isMainnetAccount =
            accountId != null && MBlockchainNetwork.ofAccountId(accountId).isMainnet
        this.showingAccountId = if (shouldLoadNewWallets) accountId else null

        childrenFadeAnimator?.cancel()
        childrenFadeAnimator = null
        isShowingRecyclerView = false
        setChildrenAlpha(0f)

        activityLoader?.clean()
        activityLoader = null
        val showingAccountId = showingAccountId
        if (showingAccountId != null) {
            isInstantSwitchingAccount =
                (skipSkeletonOnCache || dataSource?.activityListReserveAssetsCell() == false) &&
                    isGeneralDataAvailable &&
                    WGlobalStorage.hasCachedActivities(showingAccountId, null)
            isShowingAccountMultichain = WGlobalStorage.isMultichain(showingAccountId)
            activityLoader =
                ActivityLoader(context, showingAccountId, null, WeakReference(this))
            activityLoader?.askForActivities()
            assetsCell?.configure(showingAccountId)
            updateSkeletonState(animated = false)
        }
        reloadData()
    }

    // Called to update reserved header space when user scrolls on header cells
    fun updateHeaderHeights() {
        updateHeaderCellHeight()
        updateSkeletonHeaderCellHeight()
        updateActionsCell()
    }

    // Scroll to top animated, when user taps on header or double tap on tabs
    fun scrollToTop() {
        if (recyclerView.computeVerticalScrollOffset() > 0) {
            recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
        } else {
            assetsCell?.scrollToFirst()
        }
    }

    private fun scrollAssetsCellToVisible() {
        val cell = assetsCell?.asCell ?: return
        val visibleTop = (dataSource?.navigationController?.getSystemBars()?.top ?: 0) +
            HomeHeaderView.navDefaultHeight
        if (cell.top < visibleTop) {
            recyclerView.smoothScrollBy(0, cell.top - visibleTop)
        }
    }

    fun instantScrollToTop(force: Boolean = false) {
        if (!force && recyclerView.computeVerticalScrollOffset() == 0) {
            return
        }
        (recyclerView.layoutManager as LinearLayoutManager).scrollToPositionWithOffset(0, 0)
        if (isVisible)
            delegate?.updateScroll(0)
    }

    fun onDestroy() {
        activityLoader?.clean()
        activityLoader = null
        recyclerView.setOnOverScrollListener(null)
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.layoutManager = null
        recyclerView.onFlingListener = null
        recyclerView.adapter = null
        recyclerView.removeAllViews()
        skeletonRecyclerView.adapter = null
        skeletonRecyclerView.removeAllViews()
        skeletonView.onDestroy()
        assetsCell?.onDestroy()
        assetsVCPool?.destroy()
        assetsVCPool = null
        tabletActionsView?.onDestroy()
    }

    // On a live phone<->tablet switch the cell types change (segmented vs columns for assets, and
    // phone shared vs tablet per-instance actions), so cached instances are dropped and rebuilt on
    // the next bind.
    fun onWideLayoutChanged() {
        assetsCell?.let {
            if (it.isInDragMode) it.endSorting(false)
            if (it.isInSelectionMode) it.closeSelectionMode()
            (it.asCell.parent as? android.view.ViewGroup)?.removeView(it.asCell)
            it.onDestroy()
        }
        assetsCell = null

        tabletActionsView?.let {
            (it.parent as? android.view.ViewGroup)?.removeView(it)
            it.onDestroy()
        }
        tabletActionsView = null

        // Clear the actions placeholder cell so the correct actions view (phone shared view via
        // HomeVC.moveActionsViewToCell, or a fresh tablet view via mountTabletActionsView) is
        // re-inserted on the next bind. The placeholder cell itself (and its holder) is reused.
        actionsCell.removeAllViews()

        rvAdapter.invalidateCellType(ASSETS_CELL)
        reloadData()
        rvSkeletonAdapter.reloadData()
    }

    private var animationsPaused = false
    fun updateAlpha(newAlpha: Float) {
        alpha = newAlpha
        val newAnimationsPaused = newAlpha < 1
        if (animationsPaused != newAnimationsPaused) {
            animationsPaused = newAnimationsPaused
            if (animationsPaused)
                assetsCell?.setAnimations(paused = true)
            else
                post {
                    if (!animationsPaused)
                        assetsCell?.setAnimations(paused = false)
                }
        }
    }

    // PRIVATE VARIABLES ///////////////////////////////////////////////////////////////////////////
    private var assetsShown = false
    private var isMainnetAccount = false
    private var skeletonAlphaFromLoadValue = 0f
    private var childrenAlpha = 1f
    private var headerReservedActionsCell: Boolean? = null
    var showingAccountId: String? = null
        private set
    private var isShowingAccountMultichain = false

    /**
     * Set alpha on recyclerView children for sections other than header and actions.
     * This allows header and actions to remain visible while transactions fade.
     */
    private fun setChildrenAlpha(alpha: Float) {
        val newHeaderReservedActionsCell = dataSource?.activityListReserveActionsCell()
        if (childrenAlpha == alpha && headerReservedActionsCell == newHeaderReservedActionsCell) return
        headerReservedActionsCell = newHeaderReservedActionsCell
        childrenAlpha = alpha
        applyChildrenAlpha()
    }

    private fun applyChildrenAlpha() {
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return
        var itemCursor = layoutManager.findFirstVisibleItemPosition()
        if (itemCursor == RecyclerView.NO_POSITION) return
        while (true) {
            val child = layoutManager.findViewByPosition(itemCursor++) ?: break
            child.alpha = if (stickyCells.contains(child)) 1f else childrenAlpha
        }
    }

    private var childrenFadeAnimator: ValueAnimator? = null
    private fun fadeInChildren() {
        childrenFadeAnimator?.cancel()
        childrenFadeAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = DecelerateInterpolator()
            addUpdateListener { animation ->
                setChildrenAlpha(animation.animatedValue as Float)
            }
            doOnCancel {
                headerReservedActionsCell = dataSource?.activityListReserveActionsCell()
            }
            doOnEnd {
                headerReservedActionsCell = dataSource?.activityListReserveActionsCell()
            }
            start()
        }
    }

    val isGeneralDataAvailable: Boolean
        get() {
            if (BalanceStore.isAccountNew(showingAccountId))
                return true
            return TokenStore.swapAssetsLoaded &&
                TokenStore.loadedAllTokens &&
                !BalanceStore.getBalances(showingAccountId).isNullOrEmpty() &&
                (
                    !isMainnetAccount ||
                        StakingStore.getStakingState(showingAccountId ?: "") != null ||
                        WGlobalStorage.getAccountTonAddress(showingAccountId ?: "") == null
                    )
        }

    val showingTransactions: List<MApiTransaction>?
        get() {
            return activityLoader?.showingTransactions
        }

    internal var activityLoader: IActivityLoader? = null

    private val skeletonRecyclerView: WRecyclerView by lazy {
        object : WRecyclerView(dataSource!!) {
            @SuppressLint("ClickableViewAccessibility")
            override fun onTouchEvent(event: MotionEvent): Boolean {
                return false
            }
        }.apply {
            adapter = rvSkeletonAdapter
            setLayoutManager(LinearLayoutManager(context))
            setItemAnimator(null)
            alpha = 0f
            isInvisible = true
        }
    }
    private val rvSkeletonAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                HEADER_CELL,
                SKELETON_HEADER_CELL,
                SKELETON_CELL,
                TABLET_ASSETS_SKELETON_CELL
            )
        ).apply {
            setHasStableIds(true)
        }

    val rvLayoutManager = object : LinearLayoutManagerAccurateOffset(context) {
        override fun canScrollVertically(): Boolean {
            return !skeletonView.isVisible && dataSource?.phoneHeaderView?.isAnimating != true
        }
    }.apply {
        isSmoothScrollbarEnabled = true
    }

    private var ignoreScrolls = false

    private var scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            val dataSource = dataSource ?: return
            if (ignoreScrolls || !isVisible) return
            val firstVisibleItem =
                (recyclerView.layoutManager as LinearLayoutManagerAccurateOffset).findFirstVisibleItemPosition()
            val computedOffset =
                if (firstVisibleItem < 2) recyclerView.computeVerticalScrollOffset() else LARGE_INT
            val isHeaderFullyCollapsed =
                (dataSource.phoneHeaderView.mode == HomeHeaderView.Mode.Collapsed &&
                    (dataSource.recyclerViewModeValue() == HomeHeaderView.Mode.Collapsed || computedOffset > dataSource.phoneHeaderView.diffPx + 100.dp))
            if (isHeaderFullyCollapsed && dy > 3 && computedOffset > 100.dp) {
                dataSource.navigationController?.tabBarController?.scrollingDown()
            } else if (dy < -3 || computedOffset < 100.dp) {
                dataSource.navigationController?.tabBarController?.scrollingUp()
            }
            delegate?.updateScroll(computedOffset)
            //endSorting()
        }

        private var prevState = RecyclerView.SCROLL_STATE_IDLE
        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            val dataSource = dataSource ?: return
            if (newState == RecyclerView.SCROLL_STATE_DRAGGING && prevState == RecyclerView.SCROLL_STATE_SETTLING) {
                // Scrolling again, without going to idle => end previous scroll
                scrollEnded()
            }
            if (newState == RecyclerView.SCROLL_STATE_SETTLING || newState == RecyclerView.SCROLL_STATE_IDLE) {
                this@ActivityListView.recyclerView.setBounceBackSkipValue(0)
                dataSource.phoneHeaderView.isExpandAllowed = false
                ignoreScrolls =
                    dataSource.recyclerViewModeValue() == HomeHeaderView.Mode.Expanded &&
                        dataSource.phoneHeaderView.mode == HomeHeaderView.Mode.Collapsed &&
                        recyclerView.computeVerticalScrollOffset() < dataSource.phoneHeaderView.diffPx
                if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                    scrollEnded()
                } else {
                    // Usual fling should be stopped, if the header is collapsed partially.
                    if (dataSource.recyclerViewModeValue() == HomeHeaderView.Mode.Expanded &&
                        dataSource.phoneHeaderView.mode == HomeHeaderView.Mode.Collapsed &&
                        recyclerView.computeVerticalScrollOffset() < dataSource.phoneHeaderView.diffPx
                    ) {
                        recyclerView.stopScroll()
                        scrollEnded()
                    }
                }
            }
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                dataSource.heavyAnimationInProgress()
                if (recyclerView.computeVerticalScrollOffset() == 0) {
                    delegate?.pauseBlurViews()
                }
            } else {
                dataSource.executeWithLowPriority {
                    if (recyclerView.scrollState == RecyclerView.SCROLL_STATE_IDLE)
                        dataSource.heavyAnimationDone()
                }
            }
            prevState = newState
        }
    }

    private var isShowingRecyclerView = false
    val recyclerView: WRecyclerView by lazy {
        WRecyclerView(context).apply {
            clipChildren = false
            clipToPadding = false
            adapter = rvAdapter
            setLayoutManager(rvLayoutManager)
            addOnScrollListener(scrollListener)
            setOnOverScrollListener { isTouchActive, newState, suggestedOffset, velocity ->
                val dataSource = dataSource ?: return@setOnOverScrollListener
                if (showingTransactions == null || !isGeneralDataAvailable)
                    return@setOnOverScrollListener
                var offset = suggestedOffset
                if (
                    (suggestedOffset > 0f && dataSource.phoneHeaderView.mode == HomeHeaderView.Mode.Expanded && dataSource.phoneHeaderView.mode == dataSource.recyclerViewModeValue())
                ) {
                    offset = 0f
                    recyclerView.removeOverScroll()
                }
                if (newState == IOverScrollState.STATE_IDLE) {
                    dataSource.heavyAnimationDone()
                } else {
                    dataSource.heavyAnimationInProgress()
                }
                val isGoingBack = newState == IOverScrollState.STATE_BOUNCE_BACK
                if (isGoingBack && dataSource.recyclerViewModeValue() != dataSource.phoneHeaderView.mode) {
                    val prevOverscroll = recyclerView.getOverScrollOffset()
                    if (dataSource.phoneHeaderView.mode == HomeHeaderView.Mode.Expanded) {
                        recyclerView.getOverScrollOffset()
                        val newOffset =
                            if (!expandingProgrammatically) (dataSource.phoneHeaderView.diffPx - prevOverscroll).toInt() else 0
                        expandingProgrammatically = false
                        ignoreScrolls = true
                        recyclerView.scrollBy(0, newOffset)
                        recyclerView.post {
                            recyclerView.smoothScrollBy(
                                0,
                                -recyclerView.computeVerticalScrollOffset()
                            )
                        }
                    } else {
                        val newOffset =
                            (dataSource.phoneHeaderView.collapsedHeight - dataSource.phoneHeaderView.expandedContentHeight - prevOverscroll).toInt()
                        ignoreScrolls = true
                        recyclerView.scrollBy(0, newOffset)
                        recyclerView.smoothScrollBy(0, -recyclerView.computeVerticalScrollOffset())
                    }
                    delegate?.headerModeChanged()
                    if (offset == 0f) {
                        ignoreScrolls = false
                    }
                    return@setOnOverScrollListener
                }
                if (offset == 0f)
                    ignoreScrolls = false
                delegate?.updateScroll(
                    -offset.toInt() + recyclerView.computeVerticalScrollOffset(),
                    velocity,
                    isGoingBack
                )
                dataSource.phoneHeaderView.isExpandAllowed = isTouchActive
            }
            onFlingListener = object : RecyclerView.OnFlingListener() {
                override fun onFling(velocityX: Int, velocityY: Int): Boolean {
                    return if (dataSource?.phoneHeaderView?.mode == HomeHeaderView.Mode.Expanded)
                        adjustScrollingPosition()
                    else
                        false
                }
            }
            descendantFocusability = FOCUS_BLOCK_DESCENDANTS
            setPadding(0, 0, 0, dataSource?.navigationController?.getSystemBars()?.bottom ?: 0)
            clipToPadding = false
            setItemAnimator(null)
        }
    }
    private val rvAdapter: WRecyclerViewAdapter by lazy {
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(
                HEADER_CELL,
                ACTIONS_CELL,
                MULTISIG_WARNING_CELL,
                ASSETS_CELL,
                TRANSACTION_CELL,
                TRANSACTION_SMALL_CELL,
                TRANSACTION_SMALL_FIRST_IN_DAY_CELL,
                EMPTY_VIEW_CELL,
                BLACK_CELL,
                SKELETON_CELL
            )
        ).apply {
            setHasStableIds(true)
        }
    }

    private val skeletonView = SkeletonView(context)

    private var skeletonEmptyHeaderCell: WCell? = null
    val headerCell = HeaderSpaceCell(context)
    val actionsCell = WCell(context).apply {
        clipChildren = false
        clipToPadding = false
    }

    private val isWideLayout: Boolean
        get() = dataSource?.isWideHome == true

    private var tabletActionsView: TabletHeaderActionsView? = null

    // Ensure the tablet per-instance actions view exists, is mounted inside the actions placeholder
    // cell, and reflects the current account. Called when binding the actions cell on wide layout.
    private fun mountTabletActionsView() {
        val view = tabletActionsView ?: TabletHeaderActionsView(
            context,
            TabletHeaderActionsView.headerTabs(context, true),
            onClick = onClick@{ identifier ->
                if (skeletonVisible)
                    return@onClick
                delegate?.onHeaderAction(HeaderActionsView.Identifier.valueOf(identifier.name))
            }
        ).also { tabletActionsView = it }
        if (view.parent !== actionsCell) {
            (view.parent as? android.view.ViewGroup)?.removeView(view)
            actionsCell.removeAllViews()
            actionsCell.addView(
                view,
                android.view.ViewGroup.LayoutParams(
                    LayoutParams.MATCH_PARENT,
                    LayoutParams.MATCH_PARENT
                )
            )
        }
        view.updateActions(AccountStore.accountById(showingAccountId))
        view.updateTheme()
    }

    fun updateActionsView() {
        tabletActionsView?.updateActions(AccountStore.accountById(showingAccountId))
    }

    val stickyCells = setOf(headerCell, actionsCell)
    var assetsCell: IHomeAssetsCell? = null

    private val showMultisigWarning: Boolean
        get() {
            val account = AccountStore.accountById(showingAccountId) ?: return false
            return account.isMultisig && !account.isViewOnly
        }
    private val multisigWarningCell: WCell by lazy {
        WCell(
            context, ViewGroup.LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.WRAP_CONTENT
            )
        ).apply {
            val banner = MultisigWalletWarningView(context)
            addView(
                banner,
                LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            )
            setConstraints {
                toTop(banner)
                toCenterX(banner)
                toBottom(banner, ViewConstants.GAP.toFloat())
            }
        }
    }

    // Owns the home assets ViewControllers so they survive a phone<->tablet cell swap (see
    // HomeAssetsVCPool). Created on first cell build; destroyed once in onDestroy. Per-ActivityListView
    // (prev/current/next each have their own account, hence their own pool).
    private var assetsVCPool: HomeAssetsVCPool? = null

    // On wide layout the assets are shown as side-by-side columns (HomeTabletAssetsCell); on phone
    // as a paged segmented control (HomePhoneAssetsCell). Both share the IHomeAssetsCell surface.
    private fun createAssetsCell(dataSource: T): IHomeAssetsCell {
        val window = dataSource.window!!
        val navigationController = dataSource.navigationController!!
        val pool = assetsVCPool ?: HomeAssetsVCPool(
            context,
            window,
            navigationController,
            showingAccountId ?: ""
        ).also { assetsVCPool = it }
        val heightChanged = { delegate?.resumeBottomBlurViews(); Unit }
        val onAssetsShown = onAssetsShown@{
            if (showingAccountId == null)
                return@onAssetsShown
            assetsShown = true
            updateSkeletonState(animated = true)
        }
        val onReorderingRequested = { reordering: Boolean ->
            if (reordering) delegate?.startSorting() else delegate?.endSorting()
            Unit
        }
        val onForceEndReorderingRequested = { delegate?.endSorting(); Unit }
        val onSelectionRequested = { selectedCount: Int, shouldShowTransferActions: Boolean ->
            delegate?.startSelectionMode(selectedCount, shouldShowTransferActions)
            Unit
        }
        val onSelectionChanged = { selectedCount: Int,
                                   animationMode: TitleAnimationMode?,
                                   isInSelectionMode: Boolean,
                                   shouldShowTransferActions: Boolean ->
            if (isInSelectionMode) {
                delegate?.updateSelectionMode(
                    selectedCount,
                    animationMode,
                    shouldShowTransferActions
                )
            } else {
                delegate?.endSelectionMode()
            }
            Unit
        }
        val onDetailsOpened = { delegate?.endSelectionMode(); Unit }
        val cell: IHomeAssetsCell = if (isWideLayout) {
            HomeTabletAssetsCell(
                context,
                pool = pool,
                navigationController = navigationController,
                showingAccountId = showingAccountId ?: "",
                heightChanged = heightChanged,
                onAssetsShown = onAssetsShown,
                onReorderingRequested = onReorderingRequested,
                onSelectionRequested = onSelectionRequested,
                onSelectionChanged = onSelectionChanged,
                onDetailsOpened = onDetailsOpened,
                onHorizontalScroll = { delegate?.onTopItemHorizontalScroll() }
            )
        } else {
            HomePhoneAssetsCell(
                context,
                pool = pool,
                window = window,
                navigationController = navigationController,
                showingAccountId = showingAccountId ?: "",
                heightChanged = heightChanged,
                onAssetsShown = onAssetsShown,
                onReorderingRequested = onReorderingRequested,
                onForceEndReorderingRequested = onForceEndReorderingRequested,
                onSelectionRequested = onSelectionRequested,
                onSelectionChanged = onSelectionChanged,
                onDetailsOpened = onDetailsOpened
            )
        }
        cell.onScrollToVisibleRequested = { scrollAssetsCellToVisible() }
        return cell
    }

    init {
        addView(recyclerView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        addView(
            skeletonRecyclerView, LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT
            )
        )
        addView(skeletonView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updateSkeletonViews()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val header = dataSource?.phoneHeaderView ?: return
        header.availableHeight = height
        if (header.mode == HomeHeaderView.Mode.Collapsed && recyclerView.hasOverScroll) {
            recyclerView.setMaxOverscrollOffset(
                if (header.canExpandForHeight) header.diffPx else 0f
            )
        }
    }

    override val isTinted = true
    override fun updateTheme() {
        rvAdapter.updateTheme()
        rvSkeletonAdapter.updateTheme()
    }

    fun insetsUpdated() {
        val startInset = dataSource?.systemBarStartInset ?: 0
        val endInset = dataSource?.systemBarEndInset ?: 0
        recyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + startInset,
            recyclerView.paddingTop,
            ViewConstants.HORIZONTAL_PADDINGS.dp + endInset,
            dataSource?.navigationController?.getSystemBars()?.bottom ?: 0
        )
        skeletonRecyclerView.setPaddingLocalized(
            ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + startInset,
            skeletonRecyclerView.paddingTop,
            ViewConstants.HORIZONTAL_PADDINGS.dp + endInset,
            dataSource?.navigationController?.getSystemBars()?.bottom ?: 0
        )
    }

    private fun updateHeaderCellHeight() {
        val dataSource = dataSource ?: return
        val newHeight = dataSource.activityListViewHeaderHeight() + dataSource.swipeItemsOffset()
        if (newHeight == headerCell.layoutParams.height)
            return
        headerCell.updateLayoutParams {
            height = newHeight
        }
    }

    var showActions: Boolean = false
    fun updateActionsCell(): Boolean {
        val dataSource = dataSource ?: return false
        val shouldShowActions = dataSource.activityListReserveActionsCell()
        if (showActions != shouldShowActions) {
            reloadData()
            return true
        }
        return false
    }

    private fun updateSkeletonHeaderCellHeight() {
        val dataSource = dataSource ?: return
        val newHeight = dataSource.activityListViewHeaderHeight() +
            dataSource.swipeItemsOffset() +
            (if (dataSource.activityListReserveActionsCell()) dataSource.activityListActionsCellHeight() else 0)
        if (newHeight == skeletonEmptyHeaderCell?.layoutParams?.height)
            return
        skeletonEmptyHeaderCell?.layoutParams = skeletonEmptyHeaderCell?.layoutParams?.apply {
            height = newHeight
        }
    }

    private fun updateSkeletonState(animated: Boolean) {
        if (isShowingRecyclerView)
            return // Already shown, no skeleton processes necessary.

        val areActivitiesAvailable =
            !showingTransactions.isNullOrEmpty() || activityLoader?.loadedAll == true
        val assetsReady = assetsShown || dataSource?.activityListReserveAssetsCell() == false
        val shouldShowRecyclerView = isGeneralDataAvailable && areActivitiesAvailable && assetsReady
        val shouldFadeInRecyclerView =
            isInstantSwitchingAccount && shouldShowRecyclerView && !skeletonVisible

        val shouldHideSkeleton =
            skeletonAlphaFromLoadValue > 0 && (isInstantSwitchingAccount || shouldShowRecyclerView)
        val shouldShowSkeleton =
            !isInstantSwitchingAccount && !shouldShowRecyclerView

        when {
            shouldHideSkeleton -> hideSkeletons(animated)
            shouldShowSkeleton -> showSkeletons()
        }

        if (shouldShowRecyclerView) {
            isShowingRecyclerView = true
            reloadData()
            if (animated && shouldFadeInRecyclerView && alpha >= 0.1) {
                fadeInChildren()
            } else {
                setChildrenAlpha(1f)
            }
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

    val skeletonVisible: Boolean
        get() {
            return skeletonAlphaFromLoadValue > 0 && hideSkeletonAnimation?.isRunning != true
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
            post {
                rvSkeletonAdapter.reloadData()
                post {
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
    private fun hideSkeletons(animated: Boolean) {
        if (skeletonAlphaFromLoadValue == 0f || (animated && hideSkeletonAnimation?.isRunning == true))
            return
        if (!isVisible || !animated || alpha < 0.1) {
            hideSkeletonAnimation?.cancel()
            skeletonAlphaFromLoadValue = 0f
            applySkeletonAlpha()
        } else {
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
    }

    fun headerModeChanged() {
        val dataSource = dataSource ?: return
        updateHeaderHeights()
        skeletonRecyclerView.post {
            rvSkeletonAdapter.notifyItemChanged(0)
        }
        if (dataSource.phoneHeaderView.mode == HomeHeaderView.Mode.Collapsed) {
            recyclerView.setupOverScroll()
            recyclerView.setMaxOverscrollOffset(
                if (dataSource.phoneHeaderView.canExpandForHeight)
                    dataSource.phoneHeaderView.diffPx
                else
                    0f
            )
        } else if (isInvisible) {
            recyclerView.removeOverScroll()
        }
    }

    private fun applySkeletonAlpha() {
        val finalAlpha = skeletonAlphaFromLoadValue
        skeletonRecyclerView.alpha = finalAlpha
        skeletonView.alpha = finalAlpha

        if (finalAlpha > 0 && skeletonRecyclerView.isInvisible) {
            skeletonRecyclerView.isInvisible = false
            updateSkeletonViews()
            skeletonView.animate().cancel()
            skeletonView.startAnimating()
        } else if (finalAlpha == 0f && !skeletonRecyclerView.isInvisible) {
            if (skeletonView.isAnimating)
                skeletonView.stopAnimating()
            else
                skeletonView.visibility = GONE
            skeletonRecyclerView.visibility = INVISIBLE
        }
    }

    fun scrollEnded(overrideOffset: Int? = null) {
        val dataSource = dataSource ?: return
        if (dataSource.recyclerViewModeValue() != dataSource.phoneHeaderView.mode) {
            delegate?.headerModeChanged()
            if (rvLayoutManager.findFirstVisibleItemPosition() == 0 && !isWideLayout) {
                // Correct the scroll offset of the recycler view
                val correctionOffset = dataSource.phoneHeaderView.diffPx
                val scrollOffset = overrideOffset ?: recyclerView.computeVerticalScrollOffset()
                if (correctionOffset > scrollOffset) {
                    // Go to over-scroll
                    recyclerView.scrollBy(0, -correctionOffset.toInt())
                    if (scrollOffset != 0) {
                        recyclerView.comeBackFromOverScrollValue((correctionOffset - scrollOffset).toInt())
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
            if (dataSource.phoneHeaderView.mode == HomeHeaderView.Mode.Expanded) {
                recyclerView.removeOverScroll()
            }
        }
    }

    private fun adjustScrollingPosition(): Boolean {
        val dataSource = dataSource ?: return false
        val scrollOffset = recyclerView.computeVerticalScrollOffset()
        when (dataSource.recyclerViewModeValue()) {
            HomeHeaderView.Mode.Expanded -> {
                if (scrollOffset > 0 &&
                    dataSource.phoneHeaderView.mode == HomeHeaderView.Mode.Expanded
                ) {
                    recyclerView.smoothScrollBy(0, -scrollOffset)
                    return true
                }
            }

            HomeHeaderView.Mode.Collapsed -> {
                if (scrollOffset in 0..92.dp) {
                    val canGoDown = recyclerView.canScrollVertically(1)
                    if (!canGoDown)
                        return true
                    val adjustment =
                        if (scrollOffset < 46.dp) -scrollOffset else 92.dp - scrollOffset
                    if (adjustment != 0) {
                        recyclerView.smoothScrollBy(0, adjustment)
                        return true
                    }
                }
            }
        }
        return false
    }

    private var oldTransactions: Set<String>? = null
    private var oldTransactionsFirstDt: Date? = null
    private var isApplyingUpdate = false
    fun transactionsUpdated(isUpdateEvent: Boolean) {
        if (showingAccountId == null)
            return
        updateSkeletonState(animated = true)
        val shouldReloadActionsCellHeight = tabletActionsView?.isScrolling != true
        val shouldReloadAssetsCellHeight = assetsCell?.isDraggingCollectible != true
        val shouldShowActions = dataSource?.activityListReserveActionsCell()
        isApplyingUpdate = isUpdateEvent && oldTransactions != null
        if ((shouldReloadAssetsCellHeight && shouldReloadActionsCellHeight) ||
            showActions != shouldShowActions
        )
            reloadData()
        else
            reloadTransactions()
        post {
            isApplyingUpdate = false
            activityLoader?.showingTransactions?.let { showingTransactions ->
                oldTransactions =
                    showingTransactions.map { it.getStableId() }.toSet()
                oldTransactionsFirstDt = showingTransactions.firstOrNull()?.dt
            } ?: run {
                oldTransactions = null
                oldTransactionsFirstDt = null
            }
        }
    }

    internal fun reloadData() {
        if (recyclerView.isComputingLayout) {
            recyclerView.post { reloadData() }
            return
        }
        showActions = dataSource?.activityListReserveActionsCell() == true
        rvAdapter.reloadData()
    }

    private fun reloadTransactions() {
        val startInt =
            recyclerViewNumberOfItems(recyclerView, HEADER_SECTION) +
                recyclerViewNumberOfItems(recyclerView, MULTISIG_WARNING_SECTION) +
                recyclerViewNumberOfItems(recyclerView, ASSETS_SECTION)
        val count =
            recyclerViewNumberOfItems(recyclerView, TRANSACTION_SECTION) +
                recyclerViewNumberOfItems(recyclerView, EMPTY_VIEW_SECTION) +
                recyclerViewNumberOfItems(recyclerView, LOADING_SECTION)
        if (count > 0)
            rvAdapter.reloadRange(startInt, count)
    }

    // RECYCLER VIEW ///////////////////////////////////////////////////////////////////////////////
    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return when (rv) {
            recyclerView -> {
                if (isGeneralDataAvailable) 6 else 1
            }

            skeletonRecyclerView -> {
                2
            }

            else -> {
                0
            }
        }
    }

    override fun recyclerViewNumberOfItems(
        rv: RecyclerView,
        section: Int
    ): Int {
        when (rv) {
            recyclerView -> {
                return when (section) {
                    HEADER_SECTION -> {
                        if (showActions) 2 else 1
                    }

                    MULTISIG_WARNING_SECTION -> if (showMultisigWarning) 1 else 0

                    ASSETS_SECTION -> if (dataSource?.activityListReserveAssetsCell() == false) 0 else 2

                    TRANSACTION_SECTION -> if ((showingTransactions?.size ?: 0) > 0)
                        showingTransactions!!.size
                    else
                        0

                    EMPTY_VIEW_SECTION -> {
                        if (
                            showingTransactions?.isEmpty() == true
                        ) 1 else 0
                    }

                    LOADING_SECTION -> {
                        1
                    }

                    else -> throw Error()
                }
            }

            skeletonRecyclerView -> {
                return if (section == 0) 1 else 100
            }

            else -> {
                return 0
            }
        }
    }

    override fun recyclerViewCellType(
        rv: RecyclerView,
        indexPath: IndexPath
    ): WCell.Type {
        when (rv) {
            recyclerView -> {
                return when (indexPath.section) {
                    HEADER_SECTION -> {
                        if (indexPath.row == 0)
                            HEADER_CELL
                        else
                            ACTIONS_CELL
                    }

                    MULTISIG_WARNING_SECTION -> {
                        MULTISIG_WARNING_CELL
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
                        val tx = showingTransactions?.getOrNull(indexPath.row)
                        tx?.let { transaction ->
                            if (transaction.isNft ||
                                (transaction as? MApiTransaction.Transaction)?.hasComment == true
                            ) TRANSACTION_CELL else if (indexPath.row == 0 || !transaction.dt.isSameDayAs(
                                    showingTransactions!![indexPath.row - 1].dt
                                )
                            ) TRANSACTION_SMALL_FIRST_IN_DAY_CELL else TRANSACTION_SMALL_CELL
                        } ?: BLACK_CELL
                    }
                }
            }

            skeletonRecyclerView -> {
                return when (indexPath.section) {
                    HEADER_SECTION -> {
                        HEADER_CELL
                    }

                    else -> {
                        if (isWideLayout) {
                            when (indexPath.row) {
                                0 -> TABLET_ASSETS_SKELETON_CELL
                                1 -> SKELETON_HEADER_CELL
                                else -> SKELETON_CELL
                            }
                        } else {
                            if (indexPath.row == 0) SKELETON_HEADER_CELL else SKELETON_CELL
                        }
                    }
                }
            }

            else -> {
                throw Error()
            }
        }
    }

    override fun recyclerViewCellView(
        rv: RecyclerView,
        cellType: WCell.Type
    ): WCell {
        val dataSource = dataSource ?: throw Error()
        when (rv) {
            recyclerView -> {
                return when (cellType) {
                    HEADER_CELL -> {
                        headerCell
                    }

                    BLACK_CELL -> {
                        WCell(context)
                    }

                    ACTIONS_CELL -> {
                        actionsCell
                    }

                    MULTISIG_WARNING_CELL -> {
                        multisigWarningCell
                    }

                    ASSETS_CELL -> {
                        if (assetsCell == null)
                            assetsCell = createAssetsCell(dataSource)
                        assetsCell!!.asCell
                    }

                    TRANSACTION_CELL -> {
                        val cell = ActivityCell(
                            recyclerView,
                            withoutTagAndComment = false,
                            isFirstInDay = null
                        )
                        cell.allowNftMenu = true
                        cell.onTap = { transaction ->
                            delegate?.onTransactionTap(showingAccountId!!, transaction)
                        }
                        cell
                    }

                    TRANSACTION_SMALL_CELL -> {
                        val cell = ActivityCell(
                            recyclerView,
                            withoutTagAndComment = true,
                            isFirstInDay = false
                        )
                        cell.allowNftMenu = true
                        cell.onTap = { transaction ->
                            delegate?.onTransactionTap(showingAccountId!!, transaction)
                        }
                        cell
                    }

                    TRANSACTION_SMALL_FIRST_IN_DAY_CELL -> {
                        val cell = ActivityCell(
                            recyclerView,
                            withoutTagAndComment = true,
                            isFirstInDay = true
                        )
                        cell.allowNftMenu = true
                        cell.onTap = { transaction ->
                            delegate?.onTransactionTap(showingAccountId!!, transaction)
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

            skeletonRecyclerView -> {
                return when (cellType) {
                    HEADER_CELL -> {
                        skeletonEmptyHeaderCell = WCell(context)
                        skeletonEmptyHeaderCell!!
                    }

                    SKELETON_HEADER_CELL -> {
                        SkeletonHeaderCell(context)
                    }

                    TABLET_ASSETS_SKELETON_CELL -> {
                        HomeTabletAssetsSkeletonCell(context)
                    }

                    else -> {
                        SkeletonCell(context)
                    }
                }
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
        when (rv) {
            recyclerView -> {
                if (indexPath.section == TRANSACTION_SECTION &&
                    indexPath.row >= (showingTransactions?.size ?: 0) - 20
                ) {
                    activityLoader?.useBudgetTransactions()
                }

                when (indexPath.section) {
                    HEADER_SECTION -> {
                        when (indexPath.row) {
                            0 -> {
                                updateHeaderCellHeight()
                            }

                            1 -> {
                                cellHolder.cell.updateLayoutParams {
                                    height = dataSource?.activityListActionsCellHeight()
                                        ?: HeaderActionsView.HEIGHT.dp
                                }
                                if (isWideLayout)
                                    mountTabletActionsView()
                            }
                        }
                        (cellHolder.cell as? WThemedView)?.updateTheme()
                        return
                    }

                    MULTISIG_WARNING_SECTION -> {
                        (cellHolder.cell.getChildAt(0) as? WThemedView)?.updateTheme()
                    }

                    ASSETS_SECTION -> {
                        if (indexPath.row == 0) {
                            cellHolder.cell.visibility =
                                if (showingTransactions == null) INVISIBLE else VISIBLE
                            assetsCell?.configure(showingAccountId)
                        } else {
                            val layoutParams = cellHolder.cell.layoutParams
                            layoutParams.height = ViewConstants.GAP.dp
                            cellHolder.cell.layoutParams = layoutParams
                        }
                    }

                    TRANSACTION_SECTION -> {
                        if (indexPath.row < showingTransactions!!.size) {
                            val transactionCell = cellHolder.cell as ActivityCell
                            val transaction = showingTransactions!![indexPath.row]
                            val isFirstInDay = indexPath.row == 0 || !transaction.dt.isSameDayAs(
                                showingTransactions!![indexPath.row - 1].dt
                            )
                            transactionCell.configure(
                                transaction = transaction,
                                accountId = showingAccountId!!,
                                isMultichain = isShowingAccountMultichain,
                                positioning = ActivityCell.Positioning(
                                    isFirst = indexPath.row == 0,
                                    isFirstInDay = isFirstInDay,
                                    isLastInDay = (indexPath.row == showingTransactions!!.size - 1) || !transaction.dt.isSameDayAs(
                                        showingTransactions!![indexPath.row + 1].dt
                                    ),
                                    isLast = indexPath.row == showingTransactions!!.size - 1 && activityLoader?.loadedAll != false,
                                    isAdded = isApplyingUpdate &&
                                        oldTransactions?.contains(
                                            transaction.getStableId()
                                        ) == false,
                                    isAddedAsNewDay = isFirstInDay && (oldTransactionsFirstDt == null || !transaction.dt.isSameDayAs(
                                        oldTransactionsFirstDt!!
                                    ))
                                )
                            )
                        } else {
                            val layoutParams = cellHolder.cell.layoutParams
                            layoutParams.height =
                                if (activityLoader?.loadedAll != false) ViewConstants.GAP.dp else 0
                            cellHolder.cell.layoutParams = layoutParams
                        }
                    }

                    EMPTY_VIEW_SECTION -> {
                        (cellHolder.cell as EmptyCell).let { cell ->
                            cell.updateTheme()
                            cell.layoutParams = cell.layoutParams.apply {
                                height = (dataSource?.view?.parent as View).height - (
                                    (dataSource?.navigationController?.getSystemBars()?.top
                                        ?: 0) +
                                        (dataSource?.navigationController?.getSystemBars()?.bottom
                                            ?: 0) +
                                        75.dp + // TabBar
                                        HomeHeaderView.navDefaultHeight +
                                        ViewConstants.GAP.dp +
                                        (assetsCell?.asCell?.height ?: 0)
                                    )
                            }
                        }
                    }

                    LOADING_SECTION -> {
                        (cellHolder.cell as SkeletonCell).apply {
                            configure(indexPath.row, false, isLast = true)
                            updateTheme()
                            visibility =
                                if (activityLoader?.showingTransactions == null ||
                                    activityLoader?.loadedAll == true
                                ) INVISIBLE else VISIBLE
                        }
                    }
                }

                // Apply alpha to children outside header section
                cellHolder.cell.alpha = childrenAlpha
            }

            skeletonRecyclerView -> {
                if (indexPath.section == 0) {
                    updateSkeletonHeaderCellHeight()
                    return
                }
                when (cellHolder.cell) {
                    is SkeletonHeaderCell -> {
                        (cellHolder.cell as SkeletonHeaderCell).updateTheme()
                    }

                    is HomeTabletAssetsSkeletonCell -> {
                        (cellHolder.cell as HomeTabletAssetsSkeletonCell).updateTheme()
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

            else -> {}
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        when (rv) {
            recyclerView -> {
                return when (indexPath.section) {
                    HEADER_SECTION -> {
                        "header"
                    }

                    TRANSACTION_SECTION -> {
                        if (indexPath.row < (showingTransactions?.size ?: 0)) {
                            showingTransactions!![indexPath.row].getStableId()
                        } else
                            null
                    }

                    else ->
                        null
                }
            }

            else -> {
                return "${indexPath.section}_${indexPath.row}"
            }
        }
    }

    override fun activityLoaderDataLoaded(isUpdateEvent: Boolean) {
        transactionsUpdated(isUpdateEvent)
    }

    override fun activityLoaderCacheNotFound() {
        updateSkeletonState(animated = true)
    }

    override fun activityLoaderLoadedAll() {
        reloadData()
    }

}
