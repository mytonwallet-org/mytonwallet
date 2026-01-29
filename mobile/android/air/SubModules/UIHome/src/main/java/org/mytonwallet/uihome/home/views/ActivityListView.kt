package org.mytonwallet.uihome.home.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.view.MotionEvent
import android.view.View
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
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.executeWithLowPriority
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
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
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.utils.isSameDayAs
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.helpers.ActivityLoader
import org.mytonwallet.app_air.walletcore.helpers.IActivityLoader
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.uihome.home.cells.HomeAssetsCell
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

        const val HEADER_SECTION = 0
        const val ASSETS_SECTION = 1
        const val TRANSACTION_SECTION = 2
        const val EMPTY_VIEW_SECTION = 3
        const val LOADING_SECTION = 4

        const val LARGE_INT = 10000
    }

    // DATA SOURCE /////////////////////////////////////////////////////////////////////////////////
    interface DataSource {
        fun activityListViewHeaderHeight(): Int
        fun swipeItemsOffset(): Int
        fun activityListReserveActionsCell(): Boolean
        fun recyclerViewModeValue(): HomeHeaderView.Mode
        val headerView: HomeHeaderView
    }

    interface Delegate {
        fun updateScroll(dy: Int, velocity: Float? = null, isGoingBack: Boolean = false)
        fun headerModeChanged()
        fun startSorting()
        fun endSorting()
        fun onTransactionTap(accountId: String, transaction: MApiTransaction)
        fun pauseBlurViews()
        fun resumeBottomBlurViews()
    }

    // PUBLIC //////////////////////////////////////////////////////////////////////////////////////
    var expandingProgrammatically = false
    var isInstantSwitchingAccount = false

    fun configure(accountId: String?, shouldLoadNewWallets: Boolean, skipSkeletonOnCache: Boolean) {
        if (showingAccountId == accountId)
            return
        assetsShown = false
        isMainnetAccount =
            accountId != null && MBlockchainNetwork.ofAccountId(accountId) == MBlockchainNetwork.MAINNET
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
                skipSkeletonOnCache &&
                    isGeneralDataAvailable &&
                    WGlobalStorage.hasCachedActivities(showingAccountId, null)
            isShowingAccountMultichain = WGlobalStorage.isMultichain(showingAccountId)
            activityLoader =
                ActivityLoader(context, showingAccountId, null, WeakReference(this))
            activityLoader?.askForActivities()
            homeAssetsCell?.configure(showingAccountId)
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
            homeAssetsCell?.scrollToFirst()
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
        homeAssetsCell?.onDestroy()
    }

    private var animationsPaused = false
    fun updateAlpha(newAlpha: Float) {
        alpha = newAlpha
        val newAnimationsPaused = newAlpha < 1
        if (animationsPaused != newAnimationsPaused) {
            animationsPaused = newAnimationsPaused
            if (animationsPaused)
                homeAssetsCell?.setAnimations(paused = true)
            else
                post {
                    if (!animationsPaused)
                        homeAssetsCell?.setAnimations(paused = false)
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
            return TokenStore.swapAssets != null &&
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
                SKELETON_CELL
            )
        ).apply {
            setHasStableIds(true)
        }

    val rvLayoutManager = object : LinearLayoutManagerAccurateOffset(context) {
        override fun canScrollVertically(): Boolean {
            return !skeletonView.isVisible && dataSource?.headerView?.isAnimating != true
        }
    }.apply {
        isSmoothScrollbarEnabled = true
    }

    private var ignoreScrolls = false
    private var scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            val dataSource = dataSource ?: return
            if (ignoreScrolls || !isVisible)
                return
            val firstVisibleItem =
                (recyclerView.layoutManager as LinearLayoutManagerAccurateOffset).findFirstVisibleItemPosition()
            val computedOffset =
                if (firstVisibleItem < 2) recyclerView.computeVerticalScrollOffset() else LARGE_INT
            val isHeaderFullyCollapsed =
                (dataSource.headerView.mode == HomeHeaderView.Mode.Collapsed &&
                    (dataSource.recyclerViewModeValue() == HomeHeaderView.Mode.Collapsed || computedOffset > dataSource.headerView.diffPx + 100.dp))
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
                dataSource.headerView.isExpandAllowed = false
                ignoreScrolls =
                    dataSource.recyclerViewModeValue() == HomeHeaderView.Mode.Expanded &&
                        dataSource.headerView.mode == HomeHeaderView.Mode.Collapsed &&
                        recyclerView.computeVerticalScrollOffset() < dataSource.headerView.diffPx
                if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                    scrollEnded()
                } else {
                    // Usual fling should be stopped, if the header is collapsed partially.
                    if (dataSource.recyclerViewModeValue() == HomeHeaderView.Mode.Expanded &&
                        dataSource.headerView.mode == HomeHeaderView.Mode.Collapsed &&
                        recyclerView.computeVerticalScrollOffset() < dataSource.headerView.diffPx
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
                    (suggestedOffset > 0f && dataSource.headerView.mode == HomeHeaderView.Mode.Expanded && dataSource.headerView.mode == dataSource.recyclerViewModeValue())
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
                if (isGoingBack && dataSource.recyclerViewModeValue() != dataSource.headerView.mode) {
                    val prevOverscroll = recyclerView.getOverScrollOffset()
                    if (dataSource.headerView.mode == HomeHeaderView.Mode.Expanded) {
                        recyclerView.getOverScrollOffset()
                        val newOffset =
                            if (!expandingProgrammatically) (dataSource.headerView.diffPx - prevOverscroll).toInt() else 0
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
                            (dataSource.headerView.collapsedHeight - dataSource.headerView.expandedContentHeight - prevOverscroll).toInt()
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
                dataSource.headerView.isExpandAllowed = isTouchActive
            }
            onFlingListener = object : RecyclerView.OnFlingListener() {
                override fun onFling(velocityX: Int, velocityY: Int): Boolean {
                    return if (dataSource?.headerView?.mode == HomeHeaderView.Mode.Expanded)
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
    val actionsCell = WCell(context)
    val stickyCells = setOf(headerCell, actionsCell)
    var homeAssetsCell: HomeAssetsCell? = null

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

    override val isTinted = true
    override fun updateTheme() {
        rvAdapter.updateTheme()
        rvSkeletonAdapter.updateTheme()
    }

    fun insetsUpdated() {
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            recyclerView.paddingTop,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            dataSource?.navigationController?.getSystemBars()?.bottom ?: 0
        )
        skeletonRecyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            skeletonRecyclerView.paddingTop,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            skeletonRecyclerView.paddingBottom
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
            (if (dataSource.activityListReserveActionsCell()) HeaderActionsView.HEIGHT.dp else 0)
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
        val shouldShowRecyclerView = isGeneralDataAvailable && areActivitiesAvailable && assetsShown
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
        if (dataSource.headerView.mode == HomeHeaderView.Mode.Collapsed) {
            recyclerView.setupOverScroll()
            recyclerView.setMaxOverscrollOffset(dataSource.headerView.diffPx)
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
        if (dataSource.recyclerViewModeValue() != dataSource.headerView.mode) {
            delegate?.headerModeChanged()
            if (rvLayoutManager.findFirstVisibleItemPosition() == 0) {
                // Correct the scroll offset of the recycler view
                val correctionOffset = dataSource.headerView.diffPx
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
            if (dataSource.headerView.mode == HomeHeaderView.Mode.Expanded) {
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
                    dataSource.headerView.mode == HomeHeaderView.Mode.Expanded
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
        val shouldReloadAssetsCellHeight = homeAssetsCell?.isDraggingCollectible != true
        val shouldShowActions = dataSource?.activityListReserveActionsCell()
        isApplyingUpdate = isUpdateEvent && oldTransactions != null
        if (shouldReloadAssetsCellHeight || showActions != shouldShowActions)
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

    private fun reloadData() {
        showActions = dataSource?.activityListReserveActionsCell() == true
        rvAdapter.reloadData()
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

    // RECYCLER VIEW ///////////////////////////////////////////////////////////////////////////////
    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return when (rv) {
            recyclerView -> {
                if (isGeneralDataAvailable) 5 else 1
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

                    ASSETS_SECTION -> 2

                    TRANSACTION_SECTION -> if ((showingTransactions?.size ?: 0) > 0)
                        showingTransactions!!.size
                    else
                        0

                    EMPTY_VIEW_SECTION -> {
                        return if (
                            showingTransactions?.isEmpty() == true
                        ) 1 else 0
                    }

                    LOADING_SECTION -> {
                        return 1
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
                        return tx?.let { transaction ->
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
                        return if (indexPath.row == 0)
                            SKELETON_HEADER_CELL
                        else
                            SKELETON_CELL
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

                    ASSETS_CELL -> {
                        if (homeAssetsCell == null)
                            homeAssetsCell = HomeAssetsCell(
                                context,
                                window = dataSource.window!!,
                                navigationController = dataSource.navigationController!!,
                                showingAccountId = showingAccountId ?: "",
                                heightChanged = {
                                    delegate?.resumeBottomBlurViews()
                                },
                                onAssetsShown = {
                                    if (showingAccountId == null)
                                        return@HomeAssetsCell
                                    assetsShown = true
                                    updateSkeletonState(animated = true)
                                },
                                onReorderingRequested = {
                                    delegate?.startSorting()
                                },
                                onForceEndReorderingRequested = {
                                    delegate?.endSorting()
                                }
                            )
                        return homeAssetsCell!!
                    }

                    TRANSACTION_CELL -> {
                        val cell = ActivityCell(
                            recyclerView,
                            withoutTagAndComment = false,
                            isFirstInDay = null
                        )
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
                                actionsCell.updateLayoutParams {
                                    height = HeaderActionsView.Companion.HEIGHT.dp
                                }
                            }
                        }
                        (cellHolder.cell as? WThemedView)?.updateTheme()
                        return
                    }

                    ASSETS_SECTION -> {
                        if (indexPath.row == 0) {
                            val homeAssetsCell = cellHolder.cell as HomeAssetsCell
                            homeAssetsCell.visibility =
                                if (showingTransactions == null) INVISIBLE else VISIBLE
                            homeAssetsCell.configure(showingAccountId)
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
                            return showingTransactions!![indexPath.row].getStableId()
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
