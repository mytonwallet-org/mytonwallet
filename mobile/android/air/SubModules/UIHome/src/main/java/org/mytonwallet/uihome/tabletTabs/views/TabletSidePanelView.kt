package org.mytonwallet.uihome.tabletTabs.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.LinearGradient
import android.graphics.Path
import android.graphics.Shader
import android.graphics.drawable.PaintDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.RectShape
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import me.everything.android.ui.overscroll.IOverScrollState
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HighlightOverlayView
import org.mytonwallet.app_air.uicomponents.commonViews.PanelAccountItemView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderSpaceCell
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.AccountDialogHelpers
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.frameAsRectF
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.uihome.home.WalletNameMenuHelper
import org.mytonwallet.uihome.home.views.UpdateStatusView
import org.mytonwallet.uihome.home.views.header.HomeHeaderView
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TabletSidePanelView(
    private val viewController: WViewController,
    private val tabDefs: List<TabDef>,
    private val onTabSelected: (id: Int) -> Unit,
    private val onTabReselected: (id: Int) -> Unit,
    private val onAccountSelected: (account: MAccount) -> Unit,
    private val onWalletSettings: () -> Unit,
    private val onAddAccount: () -> Unit,
    private val onHeaderSwipe: (progress: Float, verticalOffset: Int, actionsFadeInPercent: Float) -> Unit,
) : WFrameLayout(viewController.context), WThemedView,
    WRecyclerViewAdapter.WRecyclerViewDataSource {
    data class TabDef(
        val id: Int,
        val iconRes: Int,
        val filledIconRes: Int,
        val labelKey: String,
    )

    companion object {
        private val HEADER_CELL = WCell.Type(1)
        private val TAB_CELL = WCell.Type(2)
        private val ACCOUNT_CELL = WCell.Type(3)
        private val ADD_ACCOUNT_CELL = WCell.Type(4)
        private val SPACER_CELL = WCell.Type(5)
        private const val TAB_ROW_HEIGHT = 50

        private const val ADD_ICON_SIZE = 33
        private const val ADD_ICON_START = 17
        private const val ADD_LABEL_START = 69
    }

    private val window get() = viewController.window

    private var accounts: List<MAccount> = emptyList()
    private var selectedTabId: Int = tabDefs.first().id
    private var ignoreScrolls = false

    private var rvMode = HomeHeaderView.DEFAULT_MODE
    private val tabRows = HashMap<Int, TabRowCell>()
    private val headerCell = HeaderSpaceCell(context)

    private val updateStatusView = UpdateStatusView(context).apply {
        onTap = { onWalletSettings() }
        onLongTap = {
            headerView.centerAccount?.let { account ->
                WalletNameMenuHelper.present(
                    viewController = viewController,
                    anchor = this,
                    account = account,
                    onManageWallets = onWalletSettings,
                )
            }
        }
    }
    val headerView: HomeHeaderView = HomeHeaderView(
        viewController.window!!,
        overrideAccountIds = null,
        updateStatusView = updateStatusView,
        onModeChange = { animated -> onHeaderModeChange(animated) },
        onExpandPressed = { expandHeader() },
        onHeaderPressed = { scrollToTop() },
        onHorizontalScrollListener = { progress, verticalOffset, actionsFadeInPercent ->
            onHeaderSwipe(progress, verticalOffset, actionsFadeInPercent)
        },
        wideHomeHeaderView = true,
        topInsetOverride = (-2).dp,
    )

    private val recyclerView = WRecyclerView(viewController)
    private val rvAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(HEADER_CELL, TAB_CELL, ACCOUNT_CELL, ADD_ACCOUNT_CELL, SPACER_CELL)
    ).apply {
        setHasStableIds(true)
    }

    private val topBlurReversedCornerView = ReversedCornerView(
        context,
        ReversedCornerView.Config(
            blurRootView = recyclerView,
            additionalTabletPadding = false,
            overrideBackgroundColor = WColor.Background
        )
    ).apply {
        isGone = true
        setRadius(0f)
        setHorizontalPadding(0f)
    }

    private val bottomBlurReversedCornerView = ReversedCornerViewUpsideDown(
        context,
        blurRootView = recyclerView,
        forceBlurView = false,
        additionalTabletPadding = false
    ).apply {
        setHorizontalPadding(0f)
    }

    private val underCardFadeView = View(context).apply {
        isGone = true
    }
    private val underCardFadeBand = 10.dp

    val isHeightLocked: Boolean
        get() = headerView.isHeightLocked

    private fun bottomBlurHeight(): Int =
        ViewConstants.TOOLBAR_RADIUS.dp.roundToInt() + bottomInset()

    private fun bottomInset(): Int =
        (window?.systemBars?.bottom ?: 0) + bottomBlurReversedCornerView.extraTopHeight

    val contentBottomInset: Int
        get() = bottomInset()

    private fun headerCellHeight(): Int {
        return headerView.collapsedMinHeight +
            if (isHeightLocked || rvMode == HomeHeaderView.Mode.Expanded)
                headerView.expandedContentHeight.toInt()
            else
                headerView.collapsedHeight
    }

    private fun spacerHeight(): Int {
        val diffPx = headerView.diffPx.toInt()
        val viewport = recyclerView.height
        if (viewport <= 0) return diffPx.coerceAtLeast(1)
        val headerCellContent = headerView.collapsedMinHeight +
            if (isHeightLocked) headerView.expandedContentHeight.toInt() else headerView.collapsedHeight
        val tabsHeight = (tabDefs.size * TAB_ROW_HEIGHT).dp - 4.dp
        val accountsHeight =
            accounts.size * PanelAccountItemView.HEIGHT_DP.dp + (if (accounts.isNotEmpty()) 12.dp else 0)
        val addAccountHeight = PanelAccountItemView.HEIGHT_DP.dp
        val collapsedContent = headerCellContent + tabsHeight + accountsHeight + addAccountHeight
        return (viewport - collapsedContent).coerceAtLeast(bottomInset() + 1) +
            if (isHeightLocked) 0 else headerView.collapseExtraScrollPx
    }

    init {
        recyclerView.clipChildren = false
        recyclerView.clipToPadding = false
        recyclerView.layoutManager = LinearLayoutManagerAccurateOffset(context)
        recyclerView.itemAnimator = null
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
        )
        recyclerView.adapter = rvAdapter
        if (rvMode == HomeHeaderView.Mode.Collapsed)
            recyclerView.setupOverScroll()

        recyclerView.addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
                if (ignoreScrolls) return
                val firstVisible =
                    (rv.layoutManager as LinearLayoutManager).findFirstVisibleItemPosition()
                val computedOffset =
                    if (firstVisible < 1) rv.computeVerticalScrollOffset() else Int.MAX_VALUE / 2
                updateHeaderScroll(computedOffset)
                updateBottomBlur()
            }

            private var prevState = RecyclerView.SCROLL_STATE_IDLE
            override fun onScrollStateChanged(rv: RecyclerView, newState: Int) {
                if (newState == RecyclerView.SCROLL_STATE_DRAGGING &&
                    prevState == RecyclerView.SCROLL_STATE_SETTLING
                ) {
                    scrollEnded()
                }
                if (newState == RecyclerView.SCROLL_STATE_SETTLING ||
                    newState == RecyclerView.SCROLL_STATE_IDLE
                ) {
                    recyclerView.setBounceBackSkipValue(0)
                    headerView.isExpandAllowed = false
                    ignoreScrolls =
                        rvMode == HomeHeaderView.Mode.Expanded &&
                            headerView.mode == HomeHeaderView.Mode.Collapsed &&
                            rv.computeVerticalScrollOffset() < headerView.diffPx
                    if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                        scrollEnded()
                    } else if (
                        rvMode == HomeHeaderView.Mode.Expanded &&
                        headerView.mode == HomeHeaderView.Mode.Collapsed &&
                        rv.computeVerticalScrollOffset() < headerView.diffPx
                    ) {
                        rv.stopScroll()
                        scrollEnded()
                    }
                }
                prevState = newState
            }
        })

        recyclerView.setOnOverScrollListener { isTouchActive, newState, suggestedOffset, velocity ->
            if (isHeightLocked) {
                updateUnderCardFade()
                return@setOnOverScrollListener
            }
            var offset = suggestedOffset
            if (suggestedOffset > 0f &&
                headerView.mode == HomeHeaderView.Mode.Expanded &&
                headerView.mode == rvMode
            ) {
                offset = 0f
                recyclerView.removeOverScroll()
            }
            val isGoingBack = newState == IOverScrollState.STATE_BOUNCE_BACK
            if (isGoingBack && rvMode != headerView.mode) {
                val prevOverscroll = recyclerView.getOverScrollOffset()
                if (headerView.mode == HomeHeaderView.Mode.Expanded) {
                    val newOffset =
                        if (!expandingProgrammatically) (headerView.diffPx - prevOverscroll).toInt() else 0
                    expandingProgrammatically = false
                    ignoreScrolls = true
                    recyclerView.scrollBy(0, newOffset)
                    recyclerView.post {
                        recyclerView.smoothScrollBy(0, -recyclerView.computeVerticalScrollOffset())
                    }
                } else {
                    ignoreScrolls = true
                    recyclerView.scrollBy(
                        0,
                        (headerView.collapsedHeight - headerView.expandedContentHeight - prevOverscroll).toInt()
                    )
                    recyclerView.smoothScrollBy(0, -recyclerView.computeVerticalScrollOffset())
                }
                headerModeChanged()
                if (offset == 0f) ignoreScrolls = false
                return@setOnOverScrollListener
            }
            if (offset == 0f) ignoreScrolls = false
            headerView.isExpandAllowed = isTouchActive
            updateHeaderScroll(
                -offset.toInt() + recyclerView.computeVerticalScrollOffset(),
                velocity,
                isGoingBack
            )
        }

        recyclerView.onFlingListener = object : RecyclerView.OnFlingListener() {
            override fun onFling(velocityX: Int, velocityY: Int): Boolean {
                return if (headerView.mode == HomeHeaderView.Mode.Expanded)
                    adjustScrollingPosition()
                else
                    false
            }
        }

        addView(
            recyclerView, ViewGroup.LayoutParams(
                MATCH_PARENT,
                MATCH_PARENT
            )
        )
        addView(
            topBlurReversedCornerView,
            LayoutParams(
                MATCH_PARENT,
                WNavigationBar.DEFAULT_HEIGHT_TINY.dp,
                Gravity.TOP
            )
        )
        addView(
            bottomBlurReversedCornerView,
            LayoutParams(
                MATCH_PARENT,
                bottomBlurHeight(),
                Gravity.BOTTOM
            )
        )
        addView(
            underCardFadeView,
            LayoutParams(MATCH_PARENT, 0, Gravity.TOP)
        )
        updateStatusView.id = generateViewId()
        addView(
            updateStatusView,
            LayoutParams(
                LayoutParams.WRAP_CONTENT,
                WNavigationBar.DEFAULT_HEIGHT.dp,
                Gravity.TOP or Gravity.CENTER_HORIZONTAL
            ).apply {
                topMargin = (-5).dp
            }
        )
        moveHeaderViewToParent()
        updateTheme()
    }

    private fun lockedCardBottom(): Int =
        headerView.collapsedMinHeight + headerView.expandedContentHeight.toInt()

    private fun updateUnderCardFade() {
        if (!isHeightLocked) {
            underCardFadeView.isGone = true
            return
        }
        val coverHeight = lockedCardBottom()
        (underCardFadeView.layoutParams as? LayoutParams)?.let { lp ->
            if (lp.topMargin != 0 || lp.height != coverHeight) {
                lp.topMargin = 0
                lp.height = coverHeight
                underCardFadeView.layoutParams = lp
                applyUnderCardFadeGradient(coverHeight)
            }
        }
        val show = recyclerView.computeVerticalScrollOffset() > 0
        underCardFadeView.isGone = !show
    }

    private fun applyUnderCardFadeGradient(coverHeight: Int = underCardFadeView.height) {
        if (coverHeight <= 0) return
        val solidStop = ((coverHeight - underCardFadeBand).toFloat() / coverHeight).coerceIn(0f, 1f)
        val solid = WColor.Background.color
        val transparent = solid and 0x00FFFFFF
        underCardFadeView.background = PaintDrawable().apply {
            shape = RectShape()
            shaderFactory = object : ShapeDrawable.ShaderFactory() {
                override fun resize(width: Int, height: Int): Shader {
                    return LinearGradient(
                        0f, 0f, 0f, height.toFloat(),
                        intArrayOf(solid, solid, transparent),
                        floatArrayOf(0f, solidStop, 1f),
                        Shader.TileMode.CLAMP
                    )
                }
            }
        }
    }

    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.action == MotionEvent.ACTION_DOWN && !isHeightLocked) {
            if (headerView.mode == HomeHeaderView.Mode.Expanded) moveHeaderViewToCell()
        }
        return super.dispatchTouchEvent(ev)
    }

    // Public API //////////////////////////////////////////////////////////////////////////////////
    var gutterPadding: Int = ViewConstants.HORIZONTAL_PADDINGS.dp
        set(value) {
            if (field == value) return
            field = value
            recyclerView.setPadding(value, 0, value, 0)
            if (headerView.parent == headerCell) {
                headerCell.setConstraints {
                    toStartPx(headerView, -value)
                    toEndPx(headerView, -value)
                }
            }
        }

    fun setAccounts(accounts: List<MAccount>) {
        this.accounts = accounts
        rvAdapter.reloadData()
        recyclerView.doOnPreDraw { updateBottomBlur() }
    }

    fun setSelectedTab(id: Int) {
        selectedTabId = id
        tabRows.forEach { (rowId, row) -> row.setSelectedState(rowId == id) }
    }

    fun refreshAccountSelection() {
        for (i in 0 until recyclerView.childCount) {
            val cell = recyclerView.getChildAt(i) as? PanelAccountItemView ?: continue
            cell.refreshSelection()
        }
    }

    private var wasHeightLocked = false

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        headerView.availableHeight = height
        val lockChanged = isHeightLocked != wasHeightLocked
        if (isHeightLocked) {
            rvMode = HomeHeaderView.Mode.Expanded
            moveHeaderViewToParent()
            headerView.y = 0f
        } else if (wasHeightLocked) {
            reconcileAfterUnlock()
        }
        wasHeightLocked = isHeightLocked
        if (lockChanged)
            applyStatusAppearance(animated = false)
        applyMaxOverscroll()
        applyBottomInset()
        updateHeaderCellHeight()
        updateSpacerHeight()
        updateUnderCardFade()
    }

    private fun reconcileAfterUnlock() {
        val scrolled = recyclerView.computeVerticalScrollOffset() > 0
        underCardFadeView.isGone = true
        headerView.unlockPin(collapse = scrolled)
        if (scrolled) {
            showTopBlur()
            moveHeaderViewToParent()
            headerView.y = 0f
            headerModeChanged()
        } else {
            scrollToTop()
        }
    }

    private fun updateSpacerHeight() {
        val spacerPosition = 1 + tabDefs.size + accounts.size + 1
        recyclerView.post { rvAdapter.notifyItemChanged(spacerPosition) }
    }

    fun onLaidOut() {
        recyclerView.doOnPreDraw {
            moveHeaderViewToCell()
            updateBottomBlur()
        }
        headerView.doOnPreDraw { applyMaxOverscroll(); updateHeaderCellHeight(); updateSpacerHeight() }
        headerView.onLayoutRecalculated = {
            applyMaxOverscroll()
            updateHeaderCellHeight()
            updateSpacerHeight()
        }
        headerCell.doOnPreDraw { headerView.layoutCardView() }
    }

    private fun applyMaxOverscroll() {
        if (isHeightLocked || !headerView.canExpandForHeight)
            recyclerView.setMaxOverscrollOffset(0f)
        else if (headerView.diffPx > 0f)
            recyclerView.setMaxOverscrollOffset(headerView.diffPx)
    }

    val pausedBlurViews: Boolean
        get() = !topBlurReversedCornerView.isPlaying

    fun showTopBlur() {
        if (topBlurReversedCornerView.isPlaying && !topBlurReversedCornerView.isGone) return
        topBlurReversedCornerView.isGone = false
        topBlurReversedCornerView.resumeBlurring()
    }

    fun hideTopBlur() {
        if (!topBlurReversedCornerView.isPlaying) return
        topBlurReversedCornerView.pauseBlurring(false)
        topBlurReversedCornerView.isGone = true
    }

    private fun updateBottomBlur() {
        if (recyclerView.canScrollVertically(1)) {
            if (bottomBlurReversedCornerView.isPlaying && !bottomBlurReversedCornerView.isGone) return
            bottomBlurReversedCornerView.resumeBlurring()
        } else {
            if (!bottomBlurReversedCornerView.isPlaying) return
            bottomBlurReversedCornerView.pauseBlurring()
        }
    }

    fun updateInsets() {
        applyBottomInset()
    }

    private var appliedBottomInset = -1

    private fun applyBottomInset() {
        val blurHeight = bottomBlurHeight()
        if (bottomBlurReversedCornerView.layoutParams?.height != blurHeight)
            bottomBlurReversedCornerView.updateLayoutParams { height = blurHeight }
        val bottomInset = bottomInset()
        if (appliedBottomInset == bottomInset)
            return
        appliedBottomInset = bottomInset
        updateSpacerHeight()
    }

    fun onDestroy() {
        headerView.onDestroy()
        recyclerView.onDestroy()
        topBlurReversedCornerView.pauseBlurring(keepBlurAsImage = false)
        bottomBlurReversedCornerView.pauseBlurring()
    }

    // Header expand/collapse mechanics (same model as HomeVC) //////////////////////////////////////
    private fun moveHeaderViewToCell() {
        if (isHeightLocked) return
        if (headerView.parent != headerCell &&
            recyclerView.computeVerticalScrollOffset() == 0 &&
            headerView.mode == HomeHeaderView.Mode.Expanded
        ) {
            (headerView.parent as? ViewGroup)?.removeView(headerView)
            if (headerView.id == NO_ID)
                headerView.id = generateViewId()
            headerCell.addView(
                headerView,
                ConstraintLayout.LayoutParams(0, LayoutParams.WRAP_CONTENT)
            )
            headerCell.setConstraints {
                toStartPx(headerView, -gutterPadding)
                toEndPx(headerView, -gutterPadding)
            }
        }
    }

    private fun moveHeaderViewToParent() {
        if (headerView.parent != this) {
            (headerView.parent as? ViewGroup)?.removeView(headerView)
            addView(
                headerView,
                LayoutParams(MATCH_PARENT, headerCell.height.coerceAtLeast(0))
            )
            updateStatusView.bringToFront()
        }
    }

    private fun updateHeaderCellHeight() {
        val target = headerCellHeight()
        if (headerCell.layoutParams != null && headerCell.layoutParams.height != target) {
            headerCell.updateLayoutParams { height = target }
        }
    }

    private fun headerModeChanged() {
        rvMode = headerView.mode
        updateHeaderCellHeight()
        if (headerView.mode == HomeHeaderView.Mode.Collapsed) {
            recyclerView.setupOverScroll()
            applyMaxOverscroll()
        }
    }

    private fun onHeaderModeChange(animated: Boolean) {
        applyMaxOverscroll()
        // Match HomeVC: on animated mode-change (mid-drag threshold cross), tell the OverScrollDecor
        // to skip the upcoming bounce-back by diffPx so the cell doesn't need to grow during the
        // bounce. Only update the cell height directly on non-animated changes.
        if (animated) {
            recyclerView.setBounceBackSkipValue(
                if (rvMode == headerView.mode) 0 else headerView.diffPx.toInt()
            )
        } else {
            headerModeChanged()
        }
        applyStatusAppearance(animated)
    }

    private var statusState: UpdateStatusView.State? = null

    /** Drive the header + status label from a status update (wallet name / sync state). */
    fun applyHeaderStatus(state: UpdateStatusView.State, animated: Boolean) {
        statusState = state
        headerView.update(state, animated)
        applyStatusAppearance(animated)
    }

    // Mirrors StickyHeaderView.update exactly.
    private fun applyStatusAppearance(animated: Boolean) {
        val state = statusState ?: return
        val isShowing =
            state is UpdateStatusView.State.Updated && headerView.mode == HomeHeaderView.Mode.Collapsed
        updateStatusView.setAppearance(isShowing = !isShowing, animated = animated)
        updateStatusView.setState(state, animated)
        updateStatusView.isClickable = !isShowing
        updateStatusView.isEnabled = !isShowing
    }

    fun scrollToTop() {
        recyclerView.smoothScrollToPosition(0)
    }

    private var expandingProgrammatically = false

    // Expand the card from a tap (same as HomeVC.expand): drive the recycler into overscroll so the
    // header's scrollY goes negative and it renders fully expanded.
    private fun expandHeader() {
        if (headerView.mode == HomeHeaderView.Mode.Expanded) return
        if (!headerView.canExpandForHeight) return
        expandingProgrammatically = true
        recyclerView.scrollToOverScroll(
            (headerView.expandedContentHeight - headerView.collapsedHeight).toInt()
        )
        recyclerView.removeOverScroll()
    }

    private fun updateHeaderScroll(dy: Int, velocity: Float? = null, isGoingBack: Boolean = false) {
        if (isHeightLocked) {
            hideTopBlur()
            if (headerView.parent == headerCell)
                moveHeaderViewToParent()
            headerView.y = 0f
            headerView.updateScroll(0)
            updateUnderCardFade()
            return
        }
        if (dy > 1) {
            if (headerView.mode == HomeHeaderView.Mode.Collapsed) {
                showTopBlur()
                moveHeaderViewToParent()
            }
        } else if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE ||
            recyclerView.getOverScrollOffset() > 0
        ) {
            hideTopBlur()
        }
        val scrollY =
            dy - (if (rvMode == HomeHeaderView.Mode.Expanded) headerView.diffPx else 0f).roundToInt()
        val acceptNegativeScrollY =
            dy < 0 ||
                headerView.mode == HomeHeaderView.Mode.Expanded ||
                recyclerView.scrollState == RecyclerView.SCROLL_STATE_DRAGGING
        if (!acceptNegativeScrollY && scrollY < 0) {
            scrollEnded()
            recyclerView.stopScroll()
            recyclerView.scrollToPosition(0)
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
    }

    private fun scrollEnded() {
        if (isHeightLocked) {
            updateUnderCardFade()
            return
        }
        val lm = recyclerView.layoutManager as LinearLayoutManager
        if (rvMode != headerView.mode) {
            headerModeChanged()
            if (lm.findFirstVisibleItemPosition() == 0) {
                val correctionOffset = headerView.diffPx
                val scrollOffset = recyclerView.computeVerticalScrollOffset()
                if (correctionOffset > scrollOffset) {
                    recyclerView.scrollBy(0, -correctionOffset.toInt())
                    if (scrollOffset != 0) {
                        recyclerView.comeBackFromOverScrollValue(
                            (correctionOffset - scrollOffset).toInt()
                        )
                    }
                } else {
                    recyclerView.scrollBy(0, -correctionOffset.toInt())
                    adjustScrollingPosition()
                }
            }
        } else {
            adjustScrollingPosition()
            if (headerView.mode == HomeHeaderView.Mode.Expanded)
                recyclerView.removeOverScroll()
        }
        if (headerView.mode == HomeHeaderView.Mode.Expanded)
            moveHeaderViewToCell()
    }

    private fun adjustScrollingPosition(): Boolean {
        if (isHeightLocked) return false
        val scrollOffset = recyclerView.computeVerticalScrollOffset()
        when (rvMode) {
            HomeHeaderView.Mode.Expanded -> {
                if (scrollOffset > 0 && headerView.mode == HomeHeaderView.Mode.Expanded) {
                    recyclerView.smoothScrollBy(0, -scrollOffset)
                    return true
                }
            }

            HomeHeaderView.Mode.Collapsed -> {
                if (scrollOffset in 0..92.dp) {
                    if (!recyclerView.canScrollVertically(1)) return true
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

    override val isTinted = true
    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f,
            clipToBounds = true
        )
        recyclerView.setBackgroundColor(WColor.Background.color)
        tabRows.values.forEach { it.updateTheme() }
        topBlurReversedCornerView.updateTheme()
        bottomBlurReversedCornerView.updateTheme()
        applyUnderCardFadeGradient()
        applyBottomInset()
    }

    // Data source /////////////////////////////////////////////////////////////////////////////////
    override fun recyclerViewNumberOfSections(rv: RecyclerView) = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int =
        1 + tabDefs.size + accounts.size + 2

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        when {
            indexPath.row == 0 -> HEADER_CELL
            indexPath.row <= tabDefs.size -> TAB_CELL
            indexPath.row < 1 + tabDefs.size + accounts.size -> ACCOUNT_CELL
            indexPath.row == 1 + tabDefs.size + accounts.size -> ADD_ACCOUNT_CELL
            else -> SPACER_CELL
        }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? =
        when {
            indexPath.row == 0 -> "header"
            indexPath.row <= tabDefs.size -> "tab:${tabDefs[indexPath.row - 1].id}"
            indexPath.row < 1 + tabDefs.size + accounts.size ->
                accounts[indexPath.row - 1 - tabDefs.size].accountId

            indexPath.row == 1 + tabDefs.size + accounts.size -> "addAccount"
            else -> "spacer"
        }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            HEADER_CELL -> headerCell
            TAB_CELL -> TabRowCell(context)
            ACCOUNT_CELL -> PanelAccountItemView(context)
            ADD_ACCOUNT_CELL -> AddAccountCell(context)
            SPACER_CELL -> WCell(
                context,
                ViewGroup.LayoutParams(MATCH_PARENT, 0)
            )

            else -> throw Error()
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (val cell = cellHolder.cell) {
            headerCell -> updateHeaderCellHeight()

            is TabRowCell -> {
                val def = tabDefs[indexPath.row - 1]
                cell.bind(def)
                cell.setSelectedState(def.id == selectedTabId)
                cell.setOnClickListener {
                    if (def.id == selectedTabId) onTabReselected(def.id)
                    else onTabSelected(def.id)
                }
                (cell.layoutParams as? MarginLayoutParams)?.let { lp ->
                    val target = if (indexPath.row == 1) (-4).dp else 0
                    if (lp.topMargin != target) {
                        lp.topMargin = target
                        cell.layoutParams = lp
                    }
                }
                tabRows[def.id] = cell
            }

            is PanelAccountItemView -> {
                val index = indexPath.row - 1 - tabDefs.size
                val account = accounts[index]
                cell.configure(
                    account = account,
                    isFirst = index == 0,
                    onSelect = { onAccountSelected(account) },
                    onLongPress = { presentAccountMenu(cell, account) }
                )
            }

            is AddAccountCell -> {
                cell.setOnClickListener { onAddAccount() }
            }

            else -> {
                cell.updateLayoutParams { height = spacerHeight() }
            }
        }
    }

    private var highlightOverlayView: HighlightOverlayView? = null

    private fun presentAccountMenu(cell: PanelAccountItemView, account: MAccount) {
        recyclerView.cancelActiveGesture()
        val rect = cell.frameAsRectF(4f).apply {
            top += cell.paddingTop
        }
        val cornerRadius = 24f.dp
        highlightOverlayView =
            HighlightOverlayView(
                context,
                rect,
                cornerRadius,
                topBlurReversedCornerView.takeIf { it.isVisible },
                bottomBlurReversedCornerView.takeIf { it.isVisible }
            ).apply {
                alpha = 0f
                fadeIn()
            }
        window?.windowView?.addView(
            highlightOverlayView,
            FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        WMenuPopup.present(
            cell,
            listOf(
                WMenuPopup.Item(
                    config = WMenuPopup.Item.Config.Item(
                        icon = WMenuPopup.Item.Config.Icon(
                            org.mytonwallet.uihome.R.drawable.ic_pen,
                            tintColor = WColor.SecondaryText
                        ),
                        title = LocaleController.getString("Rename")
                    ),
                    hasSeparator = false,
                    onTap = {
                        AccountDialogHelpers.presentRename(viewController, account)
                    }),
                WMenuPopup.Item(
                    config = WMenuPopup.Item.Config.Item(
                        icon = WMenuPopup.Item.Config.Icon(
                            org.mytonwallet.app_air.icons.R.drawable.ic_remove,
                            tintColor = WColor.Red
                        ),
                        title = LocaleController.getString("Remove"),
                        titleColor = WColor.Red.color
                    ),
                    hasSeparator = false,
                    onTap = {
                        window?.let {
                            AccountDialogHelpers.presentSignOut(it, account)
                        }
                    })
            ),
            xOffset = 72.dp,
            yOffset = (-20).dp,
            positioning = WMenuPopup.Positioning.BELOW,
            centerHorizontally = true,
            windowBackgroundStyle = WMenuPopup.BackgroundStyle.Cutout(Path().apply {
                addRoundRect(rect, cornerRadius, cornerRadius, Path.Direction.CW)
            }),
            backdropStyle = WMenuPopup.BackdropStyle.Transparent,
            usePillShadow = true,
            onWillDismiss = {
                highlightOverlayView?.let { overlayView ->
                    overlayView.fadeOut {
                        window?.windowView?.removeView(overlayView)
                    }
                }
            }
        )
    }

    // Cells ///////////////////////////////////////////////////////////////////////////////////////
    @SuppressLint("ViewConstructor")
    private inner class TabRowCell(context: Context) :
        WCell(context, LayoutParams(MATCH_PARENT, TAB_ROW_HEIGHT.dp)), WThemedView {
        private var def: TabDef? = null
        private val icon = ImageView(context).apply {
            id = generateViewId()
            scaleType = ImageView.ScaleType.CENTER
        }
        private val label = WLabel(context).apply {
            id = generateViewId()
            setStyle(16f, WFont.Medium)
        }
        private val rippleDrawable = WRippleDrawable.create(16f.dp).apply {
            rippleColor = WColor.BackgroundRipple.color
        }
        private var isSelectedState = false

        init {
            background = rippleDrawable
            addView(icon, LayoutParams(28.dp, 28.dp))
            addView(label, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
            setConstraints {
                toStartPx(icon, 10.dp)
                toCenterY(icon)
                toStartPx(label, 50.dp)
                toCenterY(label)
            }
        }

        fun bind(def: TabDef) {
            this.def = def
            label.text = LocaleController.getString(def.labelKey)
            updateTheme()
        }

        fun setSelectedState(selected: Boolean) {
            isSelectedState = selected
            updateTheme()
        }

        override fun updateTheme() {
            val def = def ?: return
            val tint = if (isSelectedState) WColor.Tint.color else WColor.PrimaryText.color
            icon.setImageResource(if (isSelectedState) def.filledIconRes else def.iconRes)
            icon.setColorFilter(tint)
            label.setTextColor(tint)
            rippleDrawable.rippleColor = WColor.BackgroundRipple.color
        }
    }

    @SuppressLint("ViewConstructor")
    private inner class AddAccountCell(context: Context) :
        WCell(context, LayoutParams(MATCH_PARENT, PanelAccountItemView.HEIGHT_DP.dp)),
        WThemedView {
        private val icon = ImageView(context).apply {
            id = generateViewId()
            scaleType = ImageView.ScaleType.FIT_CENTER
            setImageResource(org.mytonwallet.app_air.uisettings.R.drawable.ic_add)
        }
        private val label = WLabel(context).apply {
            id = generateViewId()
            setStyle(16f, WFont.Regular)
            text = LocaleController.getString("Add Wallet")
        }
        private val rippleDrawable = WRippleDrawable.create(16f.dp).apply {
            rippleColor = WColor.BackgroundRipple.color
        }

        init {
            background = rippleDrawable
            addView(icon, LayoutParams(ADD_ICON_SIZE.dp, ADD_ICON_SIZE.dp))
            addView(label, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT))
            setConstraints {
                toStartPx(icon, ADD_ICON_START.dp)
                toCenterY(icon)
                toStartPx(label, ADD_LABEL_START.dp)
                toCenterY(label)
            }
            updateTheme()
        }

        override fun updateTheme() {
            icon.setColorFilter(WColor.Tint.color)
            label.setTextColor(WColor.Tint.color)
            rippleDrawable.rippleColor = WColor.BackgroundRipple.color
        }
    }
}
