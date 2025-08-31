package org.mytonwallet.app_air.uicomponents.widgets.segmentedController

import WNavigationController
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
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.increaseDragSensitivity
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.clearSegmentedControl.WClearSegmentedControl
import org.mytonwallet.app_air.uicomponents.widgets.clearSegmentedControl.WClearSegmentedControlItem
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import java.lang.ref.WeakReference
import kotlin.math.abs

@SuppressLint("ViewConstructor")
class WSegmentedController(
    private val navigationController: WNavigationController,
    initialItems: Array<WSegmentedControllerItem>,
    private val defaultSelectedIndex: Int = 0,
    private val isFullScreen: Boolean = true,
    private val isTransparent: Boolean = false,
    private val applySideGutters: Boolean = true,
    val navHeight: Int = WNavigationBar.DEFAULT_HEIGHT.dp,
    private var onOffsetChange: ((position: Int, currentOffset: Float) -> Unit)? = null,
    private var onItemsReordered: (() -> Unit)? = null
) : WView(navigationController.context), WThemedView, WProtectedView,
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    WClearSegmentedControl.Delegate {

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
                currentOffset = position + positionOffset
                if (currentOffset == position.toFloat() && lastFullyVisible != position) {
                    (currentItem as? WSegmentedControllerItemVC)?.onFullyVisible()
                    lastFullyVisible = position
                } else {
                    if (lastFullyVisible != null)
                        (items[lastFullyVisible!!].viewController as? WSegmentedControllerItemVC)?.onPartiallyVisible()
                }
                onOffsetChange?.invoke(position, currentOffset)
                clearSegmentedControl.updateThumbPosition(
                    position,
                    offset = currentOffset,
                    force = false,
                    ensureVisibleThumb = !isAnimatingChangeTab
                )
                val blur1 = abs(blurState[position] ?: 0f)
                val blur2 = abs(blurState[position + 1] ?: 0f)
                val currentBlur = blur1 * (1 - (positionOffset)) + blur2 * positionOffset
                if (currentBlur > 0) {
                    reversedCornerView.resumeBlurring()
                    reversedCornerView.setBlurAlpha(currentBlur)
                }
            }

            override fun onPageScrollStateChanged(state: Int) {
                super.onPageScrollStateChanged(state)
                if (state == ViewPager2.SCROLL_STATE_IDLE) {
                    val blurAlpha = blurState[viewPager.currentItem] ?: 0f
                    if (blurAlpha > 0) {
                        reversedCornerView.resumeBlurring()
                        reversedCornerView.setBlurAlpha(blurAlpha.coerceIn(0f, 1f))
                    } else {
                        reversedCornerView.pauseBlurring(blurAlpha < 0)
                    }
                    reversedCornerView.alpha = 1f
                    isAnimatingChangeTab = false
                    clearSegmentedControl.updateThumbPosition(
                        viewPager.currentItem,
                        offset = currentOffset,
                        force = true,
                        ensureVisibleThumb = true
                    )
                }
            }
        })
        vp.requestDisallowInterceptTouchEvent(true)
        val recyclerView = vp.getChildAt(0) as RecyclerView
        recyclerView.itemAnimator = null
        recyclerView.addOnItemTouchListener(object : RecyclerView.OnItemTouchListener {
            override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
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

    private val reversedCornerView: ReversedCornerView by lazy {
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
            ViewGroup.LayoutParams(MATCH_PARENT, navHeight)
        )
        v.setConstraints {
            toTopPx(
                clearSegmentedControl,
                (if (isFullScreen) navigationController.getSystemBars().top else 6)
            )
            toCenterX(clearSegmentedControl)
        }
        v
    }

    override fun setupViews() {
        super.setupViews()

        applyItems()

        val topHeaderHeight =
            navHeight + (if (isFullScreen) navigationController.getSystemBars().top else 6)
        addView(viewPager, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        if (isFullScreen && !isTransparent)
            addView(reversedCornerView, LayoutParams(MATCH_PARENT, 0))
        addView(contentView, ViewGroup.LayoutParams(MATCH_PARENT, topHeaderHeight))
        setConstraints {
            toTop(contentView)
            if (isFullScreen) {
                toTop(viewPager)
            } else {
                toTopPx(viewPager, topHeaderHeight - 3.dp)
            }
            toCenterX(
                viewPager,
                if (applySideGutters) ViewConstants.HORIZONTAL_PADDINGS.toFloat() else 0f
            )
            toBottom(viewPager)
            if (isFullScreen && !isTransparent) {
                toTop(reversedCornerView)
                bottomToBottom(reversedCornerView, contentView, -ViewConstants.BAR_ROUNDS)
            }
        }

        if (!isFullScreen)
            viewPager.increaseDragSensitivity()
        setActiveIndex(defaultSelectedIndex)

        contentView.setOnClickListener {
            scrollToTop()
        }

        updateTheme()
    }

    override fun updateTheme() {
        closeButton.updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
        if (isFullScreen && ThemeManager.uiMode.hasRoundedCorners)
            clearSegmentedControl.paintColor = WColor.Background.color
        if (isTransparent)
            updateThemeTransparent()
        else {
            if (isFullScreen)
                reversedCornerView.setBlurOverlayColor(if (ThemeManager.uiMode.hasRoundedCorners) WColor.SecondaryBackground else WColor.Background)
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
        setBackgroundColor(Color.TRANSPARENT, ViewConstants.BIG_RADIUS.dp, true)
        closeButton.updateColors(WColor.White, WColor.BackgroundRipple)
        clearSegmentedControl.paintColor = Color.WHITE
        clearSegmentedControl.primaryTextColor = Color.BLACK
        clearSegmentedControl.secondaryTextColor = Color.WHITE
    }

    private fun applyItems() {
        items.forEach {
            it.viewController.navigationController = navigationController
        }
        clearSegmentedControl.setItems(items.map {
            WClearSegmentedControlItem(
                it.viewController.title ?: "",
                it.onClick
            )
        }, 0, this)
        clearSegmentedControl.isVisible = items.size > 1
    }

    fun updateItems(items: Array<WSegmentedControllerItem>) {
        this.items = items
        applyItems()
        vpAdapter.reloadData()
    }

    fun setActiveIndex(index: Int) {
        currentOffset = index.toFloat()
        viewPager.setCurrentItem(index, false)
        clearSegmentedControl.updateThumbPosition(
            index,
            offset = index.toFloat(),
            force = true,
            ensureVisibleThumb = !isAnimatingChangeTab
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
                    (navigationController.getSystemBars().top)
            )
            toEnd(closeButton, 8f)
        }
    }

    fun scrollToTop() {
        items[viewPager.currentItem].viewController.scrollToTop()
    }

    val currentItem: WViewController?
        get() {
            return items.getOrNull(viewPager.currentItem)?.viewController
        }

    fun updateBlurViews(recyclerView: RecyclerView) {
        updateBlurViews(recyclerView, recyclerView.computeVerticalScrollOffset())
    }

    fun updateBlurViews(scrollView: ViewGroup, computedOffset: Int) {
        val topOffset =
            if (computedOffset >= 0) computedOffset else computedOffset + scrollView.paddingTop
        val isOnTop = topOffset <= 0
        if (scrollView.canScrollVertically(1) &&
            !isOnTop
        ) {
            reversedCornerView.resumeBlurring()
            val blurAlpha = (topOffset / 20f.dp).coerceIn(0f, 1f)
            reversedCornerView.setBlurAlpha(blurAlpha)
            blurState[viewPager.currentItem] = blurAlpha
        } else {
            reversedCornerView.pauseBlurring(!isOnTop)
            blurState[viewPager.currentItem] = if (isOnTop) 0f else -1f
        }
    }

    fun updateOnClick(identifier: String, onClick: ((v: View) -> Unit)?) {
        val index = items.indexOfFirst { it.identifier == identifier }
        items[index].onClick = onClick
        clearSegmentedControl.updateOnClick(index = index, onClick = onClick)
    }

    fun setDragEnabled(enabled: Boolean) {
        clearSegmentedControl.setDragEnabled(enabled)
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
            indexPath.row == lastFullyVisible
        )
    }

    override fun onIndexChanged(to: Int, animated: Boolean) {
        isAnimatingChangeTab = true
        viewPager.setCurrentItem(to, animated)
    }

    override fun onItemMoved(from: Int, to: Int) {
        if (from < 0 || from >= items.size || to < 0 || to >= items.size || from == to) {
            return
        }

        val currentItemIndex = viewPager.currentItem
        val itemsList = items.toMutableList()
        val movedItem = itemsList.removeAt(from)
        itemsList.add(to, movedItem)

        items = itemsList.toTypedArray()

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
        items = emptyArray()
        onOffsetChange = null
        onItemsReordered = null
        removeAllViews()
    }

    fun scrollToFirst() {
        viewPager.setCurrentItem(0, true)
    }
}
