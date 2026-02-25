package org.mytonwallet.app_air.uicomponents.widgets.segmentedController

import android.annotation.SuppressLint
import android.graphics.Color
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.ISortableView
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setupSpringFling
import org.mytonwallet.app_air.uicomponents.extensions.springToItem
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.clearSegmentedControl.WClearSegmentedControl
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.max

// TODO: Refactor this class to improve performance and readability.
@SuppressLint("ViewConstructor")
class WSegmentedController(
    private val navigationController: WNavigationController,
    initialItems: MutableList<WSegmentedControllerItem>,
    private val defaultSelectedIndex: Int = 0,
    private val isFullScreen: Boolean = true,
    private val isTransparent: Boolean = false,
    private val applySideGutters: Boolean = true,
    private val navTopPadding: Int = 0,
    val navHeight: Int = WNavigationBar.DEFAULT_HEIGHT.dp,
    private var onOffsetChange: ((position: Int, currentOffset: Float) -> Unit)? = null,
    // Lets parent know the view items are reordered
    private var onItemsReordered: (() -> Unit)? = null,
    // Lets parent know the view asked to go to reordering mode
    private val onReorderingStarted: (() -> Unit)? = null,
    private val onForceEndReorderingRequested: (() -> Unit)? = null,
    private val forceCenterTabs: Boolean = false,
) : WView(navigationController.context), WThemedView, WProtectedView,
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    WClearSegmentedControl.Delegate,
    ISortableView {

    companion object {
        val PAGE_CELL = WCell.Type(1)
    }

    var items = initialItems

    var currentOffset: Float = 0f

    // Blur state for each tab, from 0 to 1, and -1 if it's on the bottom and paused, but with blur screenshot
    private var blurState: HashMap<Int, Float> = hashMapOf()

    private val vpAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(PAGE_CELL))

    private var isAnimatingChangeTab = false
    private var lastFullyVisible: Int = 0
    private var isUserInteracting = false
    private var lastTargetIndex = 0
    var targetIndex: Int? = null
        private set(value) {
            field = value
            if (value != null)
                lastTargetIndex = value
        }
    private val viewPager: ViewPager2 by lazy {
        val vp = ViewPager2(context)
        vp.id = generateViewId()
        vp.adapter = vpAdapter
        vp.offscreenPageLimit = ViewPager2.OFFSCREEN_PAGE_LIMIT_DEFAULT
        vp.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageScrolled(
                position: Int,
                positionOffset: Float,
                positionOffsetPixels: Int
            ) {
                super.onPageScrolled(position, positionOffset, positionOffsetPixels)
                if (isUserInteracting && clearSegmentedControl.isInDragMode)
                    onForceEndReorderingRequested?.invoke()
                currentOffset = position + positionOffset
                if (currentOffset == position.toFloat() && lastFullyVisible != position) {
                    (items.getOrNull(lastFullyVisible)?.viewController as? WSegmentedControllerItemVC)?.onPartiallyVisible()
                    lastFullyVisible = position
                    (items.getOrNull(lastFullyVisible)?.viewController as? WSegmentedControllerItemVC)?.onFullyVisible()
                } else {
                    (items.getOrNull(lastFullyVisible)?.viewController as? WSegmentedControllerItemVC)?.onPartiallyVisible()
                }
                onOffsetChange?.invoke(position, currentOffset)
                clearSegmentedControl.updateThumbPosition(
                    position,
                    offset = currentOffset,
                    targetIndex = targetIndex ?: lastTargetIndex,
                    force = false,
                    isAnimatingToPosition = isAnimatingChangeTab
                )
                val blur1 = abs(blurState[position] ?: 0f)
                val blur2 = abs(blurState[position + 1] ?: 0f)
                val currentBlur = blur1 * (1 - (positionOffset)) + blur2 * positionOffset
                if (currentBlur > 0 || positionOffset != 0f) {
                    reversedCornerView.resumeBlurring()
                }
            }

            override fun onPageScrollStateChanged(state: Int) {
                super.onPageScrollStateChanged(state)
                when (state) {
                    ViewPager2.SCROLL_STATE_DRAGGING -> {
                        targetIndex = null
                    }

                    ViewPager2.SCROLL_STATE_IDLE -> {
                        val blurAlpha = blurState[viewPager.currentItem] ?: 0f
                        if (blurAlpha > 0) {
                            reversedCornerView.resumeBlurring()
                        } else {
                            reversedCornerView.pauseBlurring(true)
                        }
                        reversedCornerView.alpha = 1f
                        isAnimatingChangeTab = false
                        clearSegmentedControl.updateThumbPosition(
                            viewPager.currentItem,
                            offset = currentOffset,
                            targetIndex = viewPager.currentItem,
                            force = true,
                            isAnimatingToPosition = false
                        )
                    }

                    else -> {}
                }
            }
        })
        vp.requestDisallowInterceptTouchEvent(true)
        val recyclerView = vp.getChildAt(0) as RecyclerView
        recyclerView.itemAnimator = null
        recyclerView.addOnItemTouchListener(object : RecyclerView.OnItemTouchListener {
            override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
                when (e.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        isUserInteracting = true
                    }

                    MotionEvent.ACTION_UP,
                    MotionEvent.ACTION_CANCEL -> {
                        isUserInteracting = false
                    }
                }
                return false
            }

            override fun onTouchEvent(rv: RecyclerView, e: MotionEvent) {}
            override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {}
        })
        vp
    }

    private val clearSegmentedControl = WClearSegmentedControl(context)
    private val closeButton: WImageButton by lazy {
        val v = WImageButton(context)
        v.setPadding(8.dp)
        val closeDrawable =
            ContextCompat.getDrawable(
                context,
                R.drawable.ic_close
            )
        v.setImageDrawable(closeDrawable)
        v
    }

    val reversedCornerView: ReversedCornerView by lazy {
        ReversedCornerView(
            context,
            ReversedCornerView.Config(
                blurRootView = parent as ViewGroup,
            )
        )
    }

    private val contentView: WView by lazy {
        val v = WView(context)
        v.addView(
            clearSegmentedControl,
            ViewGroup.LayoutParams(0, navHeight)
        )
        v.setConstraints {
            toTopPx(
                clearSegmentedControl,
                (if (isFullScreen) navigationController.getSystemBars().top + navTopPadding else 2)
            )
            toCenterX(clearSegmentedControl)
        }
        v
    }

    override fun setupViews() {
        super.setupViews()

        applyItems()

        val topHeaderHeight =
            navHeight + (if (isFullScreen) navigationController.getSystemBars().top + navTopPadding else (-3).dp)
        addView(viewPager, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        if (isFullScreen && !isTransparent)
            addView(reversedCornerView, LayoutParams(MATCH_PARENT, 0))
        addView(contentView, ViewGroup.LayoutParams(MATCH_PARENT, topHeaderHeight))
        setConstraints {
            toTop(contentView)
            if (isFullScreen) {
                toTop(viewPager)
            } else {
                toTopPx(viewPager, topHeaderHeight)
            }
            toCenterX(
                viewPager,
                if (applySideGutters) ViewConstants.HORIZONTAL_PADDINGS.toFloat() else 0f
            )
            toBottom(viewPager)
            if (isFullScreen && !isTransparent) {
                toTop(reversedCornerView)
                bottomToBottom(reversedCornerView, contentView, -ViewConstants.TOOLBAR_RADIUS)
            }
        }

        viewPager.setupSpringFling(onScrollingToTarget = { targetIndex ->
            if (targetIndex - this.lastTargetIndex > 1)
                this.targetIndex = this.lastTargetIndex + 1
            else if (this.lastTargetIndex - targetIndex > 1)
                this.targetIndex = this.lastTargetIndex - 1
            else
                this.targetIndex = targetIndex
            this.lastTargetIndex
        })
        setActiveIndex(defaultSelectedIndex)
        if (!applySideGutters)
            reversedCornerView.setHorizontalPadding(0f)

        contentView.setOnClickListener {
            scrollToTop()
        }

        updateTheme()
    }

    override fun updateTheme() {
        closeButton.updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
        if (isFullScreen)
            clearSegmentedControl.paintColor = WColor.Background.color
        if (isTransparent)
            updateThemeTransparent()
        else {
            if (isFullScreen)
                reversedCornerView.setBlurOverlayColor(WColor.SecondaryBackground.color)
            else
                contentView.setBackgroundColor(WColor.Background.color)
        }
        clearSegmentedControl.apply {
            updateTheme()
            if (isTransparent) updateThemeTransparent()
        }
    }

    override fun updateProtectedView() {}

    private fun updateThemeTransparent() {
        setBackgroundColor(Color.TRANSPARENT, ViewConstants.BLOCK_RADIUS.dp, true)
        closeButton.updateColors(WColor.White, WColor.BackgroundRipple)
        clearSegmentedControl.paintColor = Color.WHITE.colorWithAlpha(38)
        clearSegmentedControl.primaryTextColor = Color.WHITE
        clearSegmentedControl.secondaryTextColor = Color.WHITE.colorWithAlpha(153)
    }

    private fun applyItems(selectedItem: Int = 0) {
        items.forEach {
            it.viewController.navigationController = navigationController
        }
        clearSegmentedControl.setItems(items.map {
            WClearSegmentedControl.Item(
                it.viewController.title ?: "",
                it.onRemovePressed,
                it.onMenuPressed,
            )
        }, selectedItem, this)
        clearSegmentedControl.isVisible = items.size > 1
        clearSegmentedControl.updateItemsTrailingViews()
    }

    fun updateItems(
        items: MutableList<WSegmentedControllerItem>,
        fadeAnimation: Boolean = false,
        keepSelection: Boolean = false,
        onUpdated: (() -> Unit)? = null
    ) {
        if (closeButton.parent != null)
            contentView.setConstraints {
                toEnd(clearSegmentedControl, if (items.size < 3 || forceCenterTabs) 0f else 56f)
            }
        if (fadeAnimation) {
            clearSegmentedControl
            clearSegmentedControl.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
                updateItems(items, false, keepSelection, onUpdated)
                clearSegmentedControl.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
            }
        } else {
            onUpdated?.invoke()
            val currentSelectionIdentifier = this.items[viewPager.currentItem].identifier
            this.items = items
            val newIndex = if (keepSelection) items.indexOfFirst {
                it.identifier == currentSelectionIdentifier
            } else -1
            applyItems(selectedItem = max(0, newIndex))
            vpAdapter.reloadData()
            if (newIndex >= 0) {
                targetIndex = newIndex
                viewPager.setCurrentItem(newIndex, false)
            }
        }
    }

    fun getNextSelectedIndex(current: Int, m: Int): Int {
        return when {
            current < m -> current
            current > m -> current - 1
            m > 0 -> m - 1
            else -> 0
        }
    }

    var removingItem = false
    fun removeItem(index: Int, onCompletion: () -> Unit): WSegmentedControllerItem? {
        if (removingItem)
            return null
        removingItem = true
        val removedItem = items.getOrNull(index) ?: return null
        (items[index].viewController as ISortableView).endSorting()
        items.removeAt(index)
        vpAdapter.notifyItemRemoved(index)
        val nextSelectedIndex = getNextSelectedIndex(viewPager.currentItem, index)
        clearSegmentedControl.removeItem(index, nextSelectedIndex, onCompletion = {
            removingItem = false
            currentOffset = nextSelectedIndex.toFloat()
            if (nextSelectedIndex != viewPager.currentItem)
                setActiveIndex(nextSelectedIndex)
            onCompletion()
        })
        return removedItem
    }

    fun setActiveIndex(index: Int) {
        currentOffset = index.toFloat()
        targetIndex = index
        viewPager.setCurrentItem(index, false)
        clearSegmentedControl.updateThumbPosition(
            index,
            targetIndex = index,
            offset = index.toFloat(),
            force = true,
            isAnimatingToPosition = isAnimatingChangeTab
        )
    }

    fun addCloseButton(
        onClose: () -> Unit = {
            navigationController.window.dismissLastNav()
        }
    ) {
        contentView.addView(closeButton, LayoutParams(40.dp, 40.dp))
        closeButton.setOnClickListener {
            onClose()
        }
        contentView.setConstraints {
            toTopPx(
                closeButton,
                (navHeight - 40.dp) / 2 +
                    (navigationController.getSystemBars().top + navTopPadding)
            )
            toEnd(closeButton, 8f)
            toEnd(clearSegmentedControl, if (items.size < 3 || forceCenterTabs) 0f else 56f)
        }
        clearSegmentedControl.horizontalFadingEdge = true
    }

    fun scrollToTop() {
        items[viewPager.currentItem].viewController.scrollToTop()
    }

    val currentItem: WViewController?
        get() {
            return items.getOrNull(viewPager.currentItem)?.viewController
        }

    val currentIndex: Int
        get() {
            return viewPager.currentItem
        }

    fun updateBlurViews(recyclerView: RecyclerView) {
        updateBlurViews(recyclerView, recyclerView.computeVerticalScrollOffset())
    }

    fun updateBlurViews(scrollView: ViewGroup, computedOffset: Int) {
        val topOffset =
            if (computedOffset >= 0) computedOffset else computedOffset + scrollView.paddingTop
        val isOnTop = topOffset <= 0
        if (!isOnTop) {
            reversedCornerView.resumeBlurring()
            blurState[viewPager.currentItem] = 1f
        } else {
            reversedCornerView.pauseBlurring(true)
            blurState[viewPager.currentItem] = 0f
        }
    }

    fun updateOnMenuPressed(identifier: String, onMenuPressed: ((v: View) -> Unit)?) {
        val index = items.indexOfFirst { it.identifier == identifier }
        items[index].onMenuPressed = onMenuPressed
        clearSegmentedControl.updateOnMenuPressed(index = index, onMenuPressed = onMenuPressed)
    }

    fun setDragAllowed(enabled: Boolean) {
        clearSegmentedControl.isDragAllowed = enabled
    }

    private var isTabLocked = false

    fun lockTab() {
        isTabLocked = true
        clearSegmentedControl.isEnabled = false
        viewPager.isUserInputEnabled = false
    }

    fun unlockTab() {
        isTabLocked = false
        clearSegmentedControl.isEnabled = true
        viewPager.isUserInputEnabled = true
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 1
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return items.size
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return PAGE_CELL
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return WSegmentedControllerPageCell(context)
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        (cellHolder.cell as WSegmentedControllerPageCell).configure(
            items[indexPath.row].viewController,
            indexPath.row == lastFullyVisible && currentOffset == lastFullyVisible.toFloat()
        )
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        return items[indexPath.row].identifier
    }

    override fun onIndexChanged(to: Int, animated: Boolean) {
        isAnimatingChangeTab = true
        targetIndex = to
        if (animated)
            viewPager.springToItem(to, 0f)
        else
            viewPager.setCurrentItem(to, false)
    }

    override fun onItemMoved(from: Int, to: Int) {
        if (from < 0 || from >= items.size || to < 0 || to >= items.size || from == to) {
            return
        }

        val currentItemIndex = viewPager.currentItem
        val itemsList = items.toMutableList()
        val movedItem = itemsList.removeAt(from)
        itemsList.add(to, movedItem)

        items = itemsList

        val newBlurState = hashMapOf<Int, Float>()
        blurState.forEach { (index, value) ->
            val newIndex = when (index) {
                from -> to
                in (minOf(from, to) + 1)..maxOf(from, to) -> {
                    if (from < to) index - 1 else index + 1
                }

                else -> index
            }
            newBlurState[newIndex] = value
        }
        blurState = newBlurState

        vpAdapter.notifyItemMoved(from, to)
        val newCurrentItem = determineNewSelectedIndex(currentItemIndex, from, to)
        if (newCurrentItem != currentItemIndex) {
            targetIndex = newCurrentItem
            viewPager.setCurrentItem(newCurrentItem, false)
        }

        onItemsReordered?.invoke()
    }

    private fun determineNewSelectedIndex(currentIndex: Int, from: Int, to: Int): Int {
        return when (currentIndex) {
            from -> to
            in (minOf(from, to) + 1)..maxOf(from, to) -> {
                if (from < to) currentIndex - 1 else currentIndex + 1
            }

            else -> currentIndex
        }
    }

    fun onDestroy() {
        items.map { it.viewController.onDestroy() }
        items = mutableListOf()
        onOffsetChange = null
        onItemsReordered = null
        removeAllViews()
    }

    fun scrollToFirst() {
        targetIndex = 0
        viewPager.springToItem(0, 0f)
    }

    // Cached items to allow canceling the edit and revert
    var preeditItems: MutableList<WSegmentedControllerItem>? = null
        private set
    var isInDragMode = false

    override fun enterReorderingMode() {
        onReorderingStarted?.invoke()
    }

    override fun startSorting() {
        if (clearSegmentedControl.isInDragMode)
            return
        isInDragMode = true
        preeditItems = items.toMutableList()
        clearSegmentedControl.setDragMode(value = true, animated = true)
    }

    override fun endSorting() {
        exitDragMode()
        endSortingClearSegmentedControl(true)
    }

    fun exitDragMode() {
        isInDragMode = false
        preeditItems = null
    }

    fun endSortingClearSegmentedControl(animated: Boolean) {
        clearSegmentedControl.setDragMode(value = false, animated = animated)
    }
}
