package org.mytonwallet.app_air.uicomponents.widgets.segmentedController

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.animation.doOnEnd
import androidx.core.graphics.withSave
import androidx.core.view.doOnPreDraw
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.max
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.IChromeOverlapHost
import org.mytonwallet.app_air.uicomponents.base.ISortableView
import org.mytonwallet.app_air.uicomponents.base.WActionBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.extensions.cancelSpringScroll
import org.mytonwallet.app_air.uicomponents.extensions.captureHardwareImage
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setupSpringFling
import org.mytonwallet.app_air.uicomponents.extensions.springToItem
import org.mytonwallet.app_air.uicomponents.helpers.OverlappedChromeFader
import org.mytonwallet.app_air.uicomponents.helpers.frameInWindow
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.clearSegmentedControl.WClearSegmentedControl
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

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
    private var onSelectedIndexChanged: ((Int) -> Unit)? = null,
    // Lets parent know the view items are reordered
    private var onItemsReordered: (() -> Unit)? = null,
    // Lets parent know the view asked to go to reordering mode
    private val onReorderingStarted: (() -> Unit)? = null,
    private val onForceEndReorderingRequested: (() -> Unit)? = null,
    private val forceCenterTabs: Boolean = false,
    private val pilledTabs: Boolean = false,
    private val ownsItems: Boolean = true,
    private val initialPagePrefetchCount: Int? = null,
    private val applyPagerSideInsets: Boolean = true,
    // Keeps the tab bar (and its menu) visible even when there is only one item.
    private val showSingleItemTabs: Boolean = false,
    // Shows the arrow indicator next to the active tab when it has a menu.
    private val showActiveTabArrow: Boolean = true,
    // Stretches pilled tabs across the screen with a tinted active thumb.
    private val pilledTabsFillWidth: Boolean = false,
    private val pilledTabsHeight: Int = PILLED_TABS_HEIGHT,
    private val pilledTabsThumbHeight: Float = WClearSegmentedControl.THUMB_HEIGHT,
    private val shouldSkipIntermediatePages: Boolean = false,
    private var onDirectPageTransitionProgress: (
        (
            from: Int,
            to: Int,
            progress: Float
        ) -> Unit
    )? = null
) : WView(navigationController.context),
    WThemedView,
    WProtectedView,
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    WClearSegmentedControl.Delegate,
    ISortableView,
    IChromeOverlapHost {

    companion object {
        val PAGE_CELL = WCell.Type(1)
        const val PILLED_TABS_HEIGHT = 38
    }

    var items = initialItems

    var currentOffset: Float = 0f
    val clipContent = pilledTabs

    // Blur state for each tab, from 0 to 1, and -1 if it's on the bottom and paused, but with blur screenshot
    private var blurState: HashMap<Int, Float> = hashMapOf()

    private val vpAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(PAGE_CELL))

    private var isAnimatingChangeTab = false
    private var lastFullyVisible: Int = 0
    private var isLastFullyVisiblePartial = false
    private var lastNotifiedSelectedIndex: Int? = null
    private var isUserInteracting = false
    private var lastTargetIndex = 0
    private class DirectPageTransition(
        val from: Int,
        val to: Int,
        val source: WViewController,
        val destination: WViewController,
        val shouldRestoreUserInput: Boolean,
        val accessibility: Int,
        val selectionScroll: WClearSegmentedControl.SelectionScroll?,
        val onCompletion: (() -> Unit)?
    ) {
        var snapshot: PageSnapshot? = null
        var animator: ValueAnimator? = null
    }

    private class PageSnapshot(val bitmap: Bitmap) : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        private val frame = RectF()
        var offset = 0f

        override fun draw(canvas: Canvas) {
            canvas.withSave {
                clipRect(bounds)
                frame.set(
                    bounds.left + offset,
                    bounds.top.toFloat(),
                    bounds.left + offset + bitmap.width,
                    (bounds.top + bitmap.height).toFloat()
                )
                drawBitmap(bitmap, null, frame, paint)
            }
        }

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
        }

        @Suppress("DEPRECATION")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    private var directPageTransition: DirectPageTransition? = null
    val isPageTransitioning: Boolean
        get() = directPageTransition != null
    var targetIndex: Int? = null
        private set(value) {
            field = value
            if (value != null) lastTargetIndex = value
        }
    private fun updatePageOffset(position: Int, positionOffset: Float) {
        currentOffset = position + positionOffset
        if (currentOffset == position.toFloat() && lastFullyVisible != position) {
            (
                items.getOrNull(
                    lastFullyVisible
                )?.viewController as? WSegmentedControllerItemVC
                )?.onPartiallyVisible()
            lastFullyVisible = position
            isLastFullyVisiblePartial = false
            (
                items.getOrNull(
                    lastFullyVisible
                )?.viewController as? WSegmentedControllerItemVC
                )?.onFullyVisible()
            notifySelectedIndexChanged(position)
        } else if (currentOffset != position.toFloat()) {
            if (!isLastFullyVisiblePartial) {
                isLastFullyVisiblePartial = true
                (
                    items.getOrNull(
                        lastFullyVisible
                    )?.viewController as? WSegmentedControllerItemVC
                    )?.onPartiallyVisible()
            }
        } else if (isLastFullyVisiblePartial) {
            isLastFullyVisiblePartial = false
            (
                items.getOrNull(
                    lastFullyVisible
                )?.viewController as? WSegmentedControllerItemVC
                )?.onFullyVisible()
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
                if (isUserInteracting && clearSegmentedControl.isInDragMode) {
                    onForceEndReorderingRequested?.invoke()
                }
                if (directPageTransition == null) updatePageOffset(position, positionOffset)
            }

            override fun onPageScrollStateChanged(state: Int) {
                super.onPageScrollStateChanged(state)
                if (directPageTransition != null) return
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
        val recyclerView = vp.getChildAt(0) as? RecyclerView
        recyclerView?.itemAnimator = null
        initialPagePrefetchCount?.let { count ->
            (recyclerView?.layoutManager as? LinearLayoutManager)?.initialPrefetchItemCount = count
        }
        recyclerView?.addOnItemTouchListener(object : RecyclerView.OnItemTouchListener {
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

    private val clearSegmentedControl =
        WClearSegmentedControl(
            context,
            horizontalPaddingDp = if (pilledTabs) 1f else 11f,
            isTransparent = isTransparent,
            thumbHeightDp = pilledTabsThumbHeight,
            showActiveTabArrow = showActiveTabArrow
        ).apply {
            fillAvailableWidth = pilledTabsFillWidth
        }
    var onTabsLongPress: ((View) -> Boolean)?
        get() = clearSegmentedControl.onLongPress
        set(value) {
            clearSegmentedControl.onLongPress = value
        }
    var shouldCenterSelectedTab: Boolean
        get() = clearSegmentedControl.centersThumb
        set(value) {
            clearSegmentedControl.centersThumb = value
        }
    var onSelectedTabClick: ((View) -> Boolean)?
        get() = clearSegmentedControl.onSelectedItemClick
        set(value) {
            clearSegmentedControl.onSelectedItemClick = value
        }

    private var underTabsView: View? = null
    private var underTabsHeight = 0
    private val blurSourceContainerView: WView by lazy {
        object : WView(context) {
            override fun glassDrawChild(canvas: Canvas, child: View, drawingTime: Long): Boolean {
                if (child !== viewPager || child.width >= width || child.width == 0) {
                    return super.glassDrawChild(canvas, child, drawingTime)
                }
                val scale = width / child.width.toFloat()
                canvas.save()
                canvas.translate(-(child.left + child.translationX) * scale, 0f)
                canvas.scale(scale, 1f)
                val handled = super.glassDrawChild(canvas, child, drawingTime)
                canvas.restore()
                return handled
            }
        }.apply {
            clipChildren = clipContent
            clipToPadding = clipContent
        }
    }
    private val underTabsContainerView: WView by lazy {
        WView(context).apply {
            clipChildren = clipContent
            clipToPadding = clipContent
        }
    }
    private val actionBar: WActionBar by lazy {
        WActionBar(context).apply {
            isInvisible = true
        }
    }
    val actionBarView: WActionBar
        get() = actionBar
    private val closeButton: WImageButton by lazy {
        val v = WImageButton(context)
        v.id = UIComponentsR.id.nav_close
        v.setPadding(8.dp)
        val closeDrawable = context.getDrawableCompat(R.drawable.ic_close)
        v.setImageDrawable(closeDrawable)
        v
    }

    private var backButton: WImageButton? = null
    private var leadingView: View? = null

    private fun segmentedControlTop(): Int {
        val fullScreenOffset =
            if (isFullScreen) navigationController.getSystemBars().top + navTopPadding else 2
        return if (pilledTabs) {
            (navHeight - pilledTabsHeight.dp) / 2 + fullScreenOffset
        } else {
            fullScreenOffset
        }
    }

    val reversedCornerView: ReversedCornerView by lazy {
        ReversedCornerView(
            context,
            ReversedCornerView.Config(
                blurRootView = blurSourceContainerView,
                additionalTabletPadding = false
            )
        )
    }

    private val contentView: WView by lazy {
        val v = WView(context)
        v.clipChildren = clipContent
        v.clipToPadding = clipContent
        val clearSegmentedControlHeight = if (pilledTabs) pilledTabsHeight.dp else navHeight
        v.addView(
            clearSegmentedControl,
            ViewGroup.LayoutParams(
                if (pilledTabsFillWidth) 0 else WRAP_CONTENT,
                clearSegmentedControlHeight
            )
        )
        v.setConstraints {
            constrainedWidth(clearSegmentedControl.id, true)
            toTopPx(
                clearSegmentedControl,
                segmentedControlTop()
            )
            toCenterX(clearSegmentedControl, if (pilledTabsFillWidth) 16f else 0f)
            constrainedWidth(clearSegmentedControl.id, true)
        }
        v
    }

    private val headerFader = OverlappedChromeFader()

    override fun hideChromeOverlapping(windowRect: Rect): Boolean {
        if (!isFullScreen) return false
        val headerViews = listOf(contentView, underTabsContainerView)
        return headerFader.hideIfOverlapping(
            windowRect,
            headerViews.mapNotNull { it.frameInWindow() },
            headerViews + listOfNotNull(reversedCornerView.takeIf { it.parent === this })
        )
    }

    override fun showOverlappedChrome() = headerFader.show()

    private val shouldShowSegmentedControl: Boolean
        get() = items.size > 1 || showSingleItemTabs

    // Header view height; collapses when the tab bar is hidden on embedded controllers.
    private val headerViewHeight: Int
        get() = if (shouldShowSegmentedControl || isFullScreen) baseHeaderHeight() else 0

    // Vertical space reserved above the pager; collapses when the tab bar is hidden.
    val headerHeight: Int
        get() = headerViewHeight + underTabsHeight

    private fun baseHeaderHeight(): Int = navHeight +
        (if (isFullScreen) navigationController.getSystemBars().top + navTopPadding else (-3).dp)

    private val systemBarStartInset: Int
        get() {
            if (navigationController.tabBarController != null) return 0
            val bars = navigationController.getSystemBars()
            return if (LocaleController.isRTL) bars.right else bars.left
        }
    private val systemBarEndInset: Int
        get() {
            val bars = navigationController.getSystemBars()
            return if (LocaleController.isRTL) bars.left else bars.right
        }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w != oldw) {
            finishPageTransition()
            insetsUpdated()
        }
    }

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean =
        (directPageTransition != null && event.y >= headerHeight) ||
            super.onInterceptTouchEvent(event)

    override fun onTouchEvent(event: MotionEvent): Boolean =
        directPageTransition != null || super.onTouchEvent(event)

    override fun onDetachedFromWindow() {
        finishPageTransition(shouldNotifyOffset = false)
        super.onDetachedFromWindow()
    }

    fun insetsUpdated() {
        contentView.layoutParams?.let { layoutParams ->
            val height = headerViewHeight
            if (layoutParams.height != height) {
                layoutParams.height = height
                contentView.layoutParams = layoutParams
            }
        }
        contentView.setConstraints {
            toTopPx(
                clearSegmentedControl,
                segmentedControlTop()
            )
            if (closeButton.parent != null) {
                toTopPx(
                    closeButton,
                    (navHeight - 40.dp) / 2 +
                        (navigationController.getSystemBars().top + navTopPadding)
                )
                toEndPx(closeButton, 8.dp + systemBarEndInset)
                // Reserve the close button's footprint on the end so the centered
                // tab strip can never extend under it. For the centered cases
                // reserve the same on the start to keep the strip visually centered.
                val centeredTabs = items.size < 3 || forceCenterTabs
                toStartPx(
                    clearSegmentedControl,
                    (if (centeredTabs) 56 else 16).dp + systemBarStartInset
                )
                toEndPx(clearSegmentedControl, 56.dp + systemBarEndInset)
            }
            backButton?.let { btn ->
                if (btn.parent != null) {
                    toTopPx(
                        btn,
                        (navHeight - 40.dp) / 2 +
                            (navigationController.getSystemBars().top + navTopPadding)
                    )
                    toStartPx(btn, 8.dp + systemBarStartInset)
                    toStartPx(
                        clearSegmentedControl,
                        (if (items.size < 3 || forceCenterTabs) 0 else 56).dp + systemBarStartInset
                    )
                }
            }
            leadingView?.let { view ->
                toTopPx(
                    view,
                    (navHeight - view.layoutParams.height) / 2 +
                        (navigationController.getSystemBars().top + navTopPadding)
                )
                toStartPx(view, 8.dp + systemBarStartInset)
                val reservedInset = 12.dp + view.layoutParams.width
                toStartPx(clearSegmentedControl, reservedInset + systemBarStartInset)
                if (closeButton.parent != null && (items.size < 3 || forceCenterTabs)) {
                    toEndPx(clearSegmentedControl, reservedInset + systemBarEndInset)
                }
            }
            if (pilledTabsFillWidth) {
                toStartPx(clearSegmentedControl, 16.dp + systemBarStartInset)
                toEndPx(clearSegmentedControl, 16.dp + systemBarEndInset)
            }
        }
        setConstraints {
            toTopPx(underTabsContainerView, baseHeaderHeight())
        }
        blurSourceContainerView.setConstraints {
            val gutter = if (applySideGutters) ViewConstants.HORIZONTAL_PADDINGS.dp else 0
            val startInset = if (applyPagerSideInsets) systemBarStartInset else 0
            val endInset = if (applyPagerSideInsets) systemBarEndInset else 0
            toStartPx(viewPager, gutter + startInset)
            toEndPx(viewPager, gutter + endInset)
        }
        if (isFullScreen && !isTransparent) {
            reversedCornerView.setSideInsets(
                systemBarStartInset.toFloat(),
                systemBarEndInset.toFloat()
            )
        }
        updateUnderTabsLayout()
        items.forEach {
            if (it.viewController.isViewConfigured) it.viewController.insetsUpdated()
        }
    }

    private fun updateUnderTabsLayout() {
        underTabsContainerView.layoutParams?.let { layoutParams ->
            if (layoutParams.height != underTabsHeight) {
                layoutParams.height = underTabsHeight
                underTabsContainerView.layoutParams = layoutParams
            }
        }
        if (!isFullScreen && viewPager.parent === blurSourceContainerView) {
            blurSourceContainerView.setConstraints {
                toTopPx(viewPager, headerHeight)
            }
        }
    }

    private fun notifySelectedIndexChanged(index: Int) {
        if (lastNotifiedSelectedIndex == index) {
            return
        }
        lastNotifiedSelectedIndex = index
        onSelectedIndexChanged?.invoke(index)
    }

    override fun setupViews() {
        super.setupViews()

        clipChildren = clipContent
        clipToPadding = clipContent
        applyItems(selectedItem = defaultSelectedIndex)

        if (!isTransparent) {
            blurSourceContainerView.setBackgroundColor(WColor.Background.color)
        }
        addView(blurSourceContainerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        blurSourceContainerView.addView(viewPager, ViewGroup.LayoutParams(0, 0))
        if (isFullScreen && !isTransparent) {
            addView(reversedCornerView, LayoutParams(MATCH_PARENT, 0))
        }
        addView(contentView, ViewGroup.LayoutParams(MATCH_PARENT, headerViewHeight))
        addView(underTabsContainerView, ViewGroup.LayoutParams(MATCH_PARENT, underTabsHeight))
        setConstraints {
            allEdges(blurSourceContainerView)
            toTop(contentView)
            toTopPx(underTabsContainerView, baseHeaderHeight())
            toCenterX(underTabsContainerView)
            if (isFullScreen && !isTransparent) {
                toTop(reversedCornerView)
                bottomToBottom(
                    reversedCornerView,
                    underTabsContainerView,
                    -ViewConstants.TOOLBAR_RADIUS
                )
            }
        }
        blurSourceContainerView.setConstraints {
            if (isFullScreen) {
                toTop(viewPager)
            } else {
                toTopPx(viewPager, headerHeight)
            }
            val gutter = if (applySideGutters) ViewConstants.HORIZONTAL_PADDINGS.dp else 0
            val startInset = if (applyPagerSideInsets) systemBarStartInset else 0
            val endInset = if (applyPagerSideInsets) systemBarEndInset else 0
            toStartPx(viewPager, gutter + startInset)
            toEndPx(viewPager, gutter + endInset)
            toBottom(viewPager)
        }

        viewPager.setupSpringFling(onScrollingToTarget = { targetIndex ->
            if (targetIndex - this.lastTargetIndex > 1) {
                this.targetIndex = this.lastTargetIndex + 1
            } else if (this.lastTargetIndex - targetIndex > 1) {
                this.targetIndex = this.lastTargetIndex - 1
            } else {
                this.targetIndex = targetIndex
            }
            this.lastTargetIndex
        })
        setActiveIndex(defaultSelectedIndex)
        if (!applySideGutters) reversedCornerView.setHorizontalPadding(0f)

        contentView.setOnClickListener {
            scrollToTop()
        }

        updateTheme()
    }

    override fun updateTheme() {
        closeButton.updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
        backButton?.updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
        if (pilledTabs) {
            clearSegmentedControl.setBackgroundColor(
                if (isTransparent) Color.WHITE.colorWithAlpha(38) else WColor.Background.color,
                (pilledTabsHeight.dp / 2).toFloat(),
                clipContent
            )
        }
        if (isFullScreen) clearSegmentedControl.paintColor = WColor.ThumbBackground.color
        if (pilledTabsFillWidth) {
            clearSegmentedControl.paintColor = WColor.Tint.color.colorWithAlpha(31)
            clearSegmentedControl.primaryTextColorOverride = WColor.Tint.color
        }
        if (isTransparent) {
            updateThemeTransparent()
        } else {
            if (isFullScreen) {
                blurSourceContainerView.setBackgroundColor(WColor.SecondaryBackground.color)
                reversedCornerView.updateTheme()
                reversedCornerView.setBlurOverlayColor(
                    WColor.SecondaryBackground,
                    if (WGlobalStorage.isBlurEnabled()) null else 255
                )
            } else {
                blurSourceContainerView.setBackgroundColor(WColor.Background.color)
                contentView.setBackgroundColor(WColor.Background.color)
            }
        }
        clearSegmentedControl.updateTheme()
        (underTabsView as? WThemedView)?.updateTheme()
    }

    override fun updateProtectedView() {}

    private fun updateThemeTransparent() {
        setBackgroundColor(Color.TRANSPARENT, ViewConstants.BLOCK_RADIUS.dp, true)
        closeButton.updateColors(WColor.White, WColor.BackgroundRipple)
        backButton?.updateColors(WColor.White, WColor.BackgroundRipple)
        clearSegmentedControl.paintColor = Color.WHITE.colorWithAlpha(38)
    }

    private fun applyItems(selectedItem: Int = 0) {
        items.forEach {
            it.viewController.navigationController = navigationController
            it.viewController.isDisappeared = false
            (it.viewController as? WSegmentedControllerItemVC)?.segmentedController = this
        }
        clearSegmentedControl.setItems(
            items.map {
                WClearSegmentedControl.Item(
                    title = it.viewController.title ?: "",
                    onRemove = it.onRemovePressed,
                    onClick = it.onMenuPressed,
                    color = it.color,
                    testViewId = it.testViewId
                )
            },
            selectedItem,
            this
        )
        updateTabBarVisibility()
        syncCloseButtonVisibility()
        clearSegmentedControl.updateItemsTrailingViews()
    }

    private fun updateTabBarVisibility() {
        tabBarPresentationAnimator?.cancel()
        tabBarPresentationAnimator = null
        clearSegmentedControl.isVisible = shouldShowSegmentedControl && !actionBar.isVisible
        clearSegmentedControl.alpha = 1f
        contentView.layoutParams?.let { layoutParams ->
            if (layoutParams.height != headerViewHeight) {
                layoutParams.height = headerViewHeight
                contentView.layoutParams = layoutParams
            }
        }
        applyPagerTopOffset(headerHeight)
    }

    private fun applyPagerTopOffset(offset: Int) {
        if (!isFullScreen && viewPager.parent === blurSourceContainerView) {
            blurSourceContainerView.setConstraints {
                toTopPx(viewPager, offset)
            }
        }
    }

    private var tabBarPresentationAnimator: ValueAnimator? = null

    // Fades the tab bar in/out and animates the header collapse when its visibility changes.
    fun updateTabBarPresentation(animated: Boolean) {
        val shouldShow = shouldShowSegmentedControl && !actionBar.isVisible
        if (!animated ||
            clearSegmentedControl.isVisible == shouldShow ||
            !WGlobalStorage.getAreAnimationsActive()
        ) {
            updateTabBarVisibility()
            return
        }
        tabBarPresentationAnimator?.cancel()
        val startOffset = (if (shouldShow) 0 else baseHeaderHeight()) + underTabsHeight
        if (shouldShow) {
            clearSegmentedControl.alpha = 0f
            clearSegmentedControl.isVisible = true
            clearSegmentedControl.fadeIn(AnimationConstants.QUICK_ANIMATION)
        } else {
            clearSegmentedControl.fadeOut(AnimationConstants.QUICK_ANIMATION)
        }
        tabBarPresentationAnimator = ValueAnimator.ofInt(startOffset, headerHeight).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            addUpdateListener { animator ->
                val offset = animator.animatedValue as Int
                contentView.layoutParams?.let { layoutParams ->
                    layoutParams.height = (offset - underTabsHeight).coerceAtLeast(0)
                    contentView.layoutParams = layoutParams
                }
                applyPagerTopOffset(offset)
            }
            // Finalize with the last height tick; fadeOut's own end action lands
            // a frame later and flashes a blank band over the pager.
            doOnEnd {
                if (!shouldShow) {
                    clearSegmentedControl.animate().cancel()
                    clearSegmentedControl.isVisible = false
                    clearSegmentedControl.alpha = 1f
                }
            }
            start()
        }
    }

    private fun headerViews(): List<View> = buildList {
        add(clearSegmentedControl)
        if (closeButton.parent != null) add(closeButton)
        backButton?.let { add(it) }
        leadingView?.let { add(it) }
    }

    private fun syncCloseButtonVisibility() {
        if (closeButton.parent == null) {
            return
        }
        closeButton.isVisible = !actionBar.isVisible
        closeButton.alpha = clearSegmentedControl.alpha
    }

    fun updateItems(
        items: MutableList<WSegmentedControllerItem>,
        fadeAnimation: Boolean = false,
        keepSelection: Boolean = false,
        onUpdated: (() -> Unit)? = null
    ) {
        finishPageTransition()
        if (closeButton.parent != null) {
            contentView.setConstraints {
                val centeredTabs = items.size < 3 || forceCenterTabs
                toStartPx(
                    clearSegmentedControl,
                    (if (centeredTabs) 56 else 16).dp + systemBarStartInset
                )
                toEndPx(clearSegmentedControl, 56.dp + systemBarEndInset)
            }
        }
        applyLeadingViewConstraints()
        if (fadeAnimation) {
            clearSegmentedControl
            clearSegmentedControl.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
                updateItems(items, false, keepSelection, onUpdated)
                clearSegmentedControl.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
            }
        } else {
            onUpdated?.invoke()
            val currentSelectionIdentifier =
                this.items.getOrNull(viewPager.currentItem)?.identifier
            val removedViewControllers =
                if (ownsItems) {
                    this.items
                        .map { it.viewController }
                        .filter { oldViewController ->
                            items.none { it.viewController === oldViewController }
                        }
                        .distinct()
                } else {
                    emptyList()
                }
            this.items = items
            val newIndex = if (keepSelection && currentSelectionIdentifier != null) {
                items.indexOfFirst { it.identifier == currentSelectionIdentifier }
            } else {
                -1
            }
            applyItems(selectedItem = max(0, newIndex))
            vpAdapter.reloadData()
            removedViewControllers.forEach { it.onDestroy() }
            if (newIndex >= 0) {
                targetIndex = newIndex
                viewPager.setCurrentItem(newIndex, false)
            }
        }
    }

    fun getNextSelectedIndex(current: Int, m: Int): Int = when {
        current < m -> current
        current > m -> current - 1
        m > 0 -> m - 1
        else -> 0
    }

    var removingItem = false
    fun removeItem(index: Int, onCompletion: () -> Unit): WSegmentedControllerItem? {
        finishPageTransition()
        if (removingItem) return null
        removingItem = true
        val removedItem = items.getOrNull(index) ?: return null
        (items[index].viewController as ISortableView).endSorting()
        items.removeAt(index)
        vpAdapter.notifyItemRemoved(index)
        val nextSelectedIndex = getNextSelectedIndex(viewPager.currentItem, index)
        clearSegmentedControl.removeItem(index, nextSelectedIndex, onCompletion = {
            removingItem = false
            currentOffset = nextSelectedIndex.toFloat()
            // In drag mode the bar must stay visible; it collapses when sorting ends.
            if (!isInDragMode) updateTabBarPresentation(animated = true)
            if (nextSelectedIndex != viewPager.currentItem) setActiveIndex(nextSelectedIndex)
            onCompletion()
        })
        return removedItem
    }

    fun setActiveIndex(index: Int, shouldAnimateTabScroll: Boolean = false) {
        finishPageTransition()
        currentOffset = index.toFloat()
        targetIndex = index
        viewPager.setCurrentItem(index, false)
        if (viewPager.width == 0) {
            viewPager.post { viewPager.setCurrentItem(index, false) }
        }
        clearSegmentedControl.updateThumbPosition(
            index,
            targetIndex = index,
            offset = index.toFloat(),
            force = true,
            isAnimatingToPosition = isAnimatingChangeTab,
            animateScroll = shouldAnimateTabScroll,
            shouldAnimateCenter = shouldAnimateTabScroll
        )
        notifySelectedIndexChanged(index)
    }

    fun setUnderTabsView(view: View?) {
        if (underTabsView === view) {
            return
        }

        underTabsView?.let { current ->
            if (current.parent === underTabsContainerView) {
                underTabsContainerView.removeView(current)
            }
        }

        underTabsView = view

        if (view != null) {
            underTabsContainerView.addView(view, ViewGroup.LayoutParams(0, WRAP_CONTENT))
            underTabsContainerView.setConstraints {
                toTop(view)
                toCenterX(view)
            }
            (view as? WThemedView)?.updateTheme()
        }
    }

    fun setUnderTabsHeight(height: Int) {
        if (underTabsHeight == height) {
            return
        }
        underTabsHeight = height
        updateUnderTabsLayout()
    }

    fun addCloseButton(
        onClose: () -> Unit = {
            navigationController.window.dismissLastNav()
        }
    ) {
        if (closeButton.parent != null) return

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
            toEndPx(closeButton, 8.dp + systemBarEndInset)
            toStartPx(clearSegmentedControl, 16.dp + systemBarStartInset)
            toEndPx(
                clearSegmentedControl,
                (if (items.size < 3 || forceCenterTabs) 16 else 56).dp + systemBarEndInset
            )
        }
        clearSegmentedControl.horizontalFadingEdge = true
        syncCloseButtonVisibility()
    }

    fun addBackButton(
        onBack: () -> Unit = {
            navigationController.pop()
        }
    ) {
        val btn = WImageButton(context).apply {
            id = UIComponentsR.id.nav_back
            setPadding(8.dp)
            setImageDrawable(context.getDrawableCompat(R.drawable.ic_nav_back))
            updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
            setOnClickListener { onBack() }
        }
        backButton = btn
        contentView.addView(btn, LayoutParams(40.dp, 40.dp))
        contentView.setConstraints {
            toTopPx(
                btn,
                (navHeight - 40.dp) / 2 +
                    (navigationController.getSystemBars().top + navTopPadding)
            )
            toStartPx(btn, 8.dp + systemBarStartInset)
            toStartPx(
                clearSegmentedControl,
                (if (items.size < 3 || forceCenterTabs) 0 else 56).dp + systemBarStartInset
            )
        }
        clearSegmentedControl.horizontalFadingEdge = true
    }

    fun addLeadingView(view: View, width: Int, height: Int) {
        leadingView = view
        contentView.addView(view, LayoutParams(width, height))
        applyLeadingViewConstraints()
        clearSegmentedControl.horizontalFadingEdge = true
    }

    private fun applyLeadingViewConstraints() {
        val view = leadingView ?: return
        contentView.setConstraints {
            toTopPx(
                view,
                (navHeight - view.layoutParams.height) / 2 +
                    (navigationController.getSystemBars().top + navTopPadding)
            )
            toStartPx(view, 8.dp + systemBarStartInset)
            val reservedInset = 12.dp + view.layoutParams.width
            toStartPx(clearSegmentedControl, reservedInset + systemBarStartInset)
            if (closeButton.parent != null && (items.size < 3 || forceCenterTabs)) {
                toEndPx(clearSegmentedControl, reservedInset + systemBarEndInset)
            }
        }
    }

    fun showActionBar() {
        if (actionBar.isVisible) return

        if (actionBar.parent == null) {
            contentView.addView(actionBar, ViewGroup.LayoutParams(0, navHeight))
            contentView.setConstraints {
                toCenterX(actionBar)
                topToTop(actionBar, clearSegmentedControl)
                bottomToBottom(actionBar, clearSegmentedControl)
            }
        }

        headerViews().forEach {
            it.animate().cancel()
        }
        actionBar.animate().cancel()

        if (!clearSegmentedControl.isVisible) {
            viewPager.isUserInputEnabled = false
            actionBar.isVisible = true
            actionBar.alpha = 1f
            syncCloseButtonVisibility()
            return
        }

        headerViews().fadeOut(
            AnimationConstants.SUPER_QUICK_ANIMATION,
            finishVisibility = View.INVISIBLE
        ) {
            viewPager.isUserInputEnabled = false
            actionBar.isVisible = true
            actionBar.alpha = 0f
            actionBar.fadeIn(AnimationConstants.SUPER_QUICK_ANIMATION)
        }
    }

    fun hideActionBar() {
        if (!actionBar.isVisible) return

        actionBar.animate().cancel()
        headerViews().forEach {
            it.animate().cancel()
        }

        actionBar.fadeOut(AnimationConstants.SUPER_QUICK_ANIMATION) {
            actionBar.isInvisible = true
            viewPager.isUserInputEnabled = !isTabLocked
            headerViews().forEach {
                it.isVisible = it !== clearSegmentedControl || shouldShowSegmentedControl
            }
            val viewsToFadeIn = headerViews().filter { it.isVisible }
            if (viewsToFadeIn.isNotEmpty()) {
                viewsToFadeIn.fadeIn(AnimationConstants.SUPER_QUICK_ANIMATION)
            }
        }
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
        if (index < 0) return
        items[index].onMenuPressed = onMenuPressed
        clearSegmentedControl.updateOnMenuPressed(index = index, onMenuPressed = onMenuPressed)
    }

    fun setBadge(identifier: String, badge: String?) {
        val index = items.indexOfFirst { it.identifier == identifier }
        if (index < 0) return
        val item = items[index]
        (item.viewController as? WSegmentedControllerItemVC)?.badge = badge
        clearSegmentedControl.setBadge(index, badge)
    }

    fun setDragAllowed(enabled: Boolean) {
        clearSegmentedControl.isDragAllowed = enabled
    }

    private var isTabLocked = false

    fun lockTab() {
        finishPageTransition()
        isTabLocked = true
        clearSegmentedControl.isEnabled = false
        viewPager.isUserInputEnabled = false
    }

    fun unlockTab() {
        isTabLocked = false
        clearSegmentedControl.isEnabled = true
        viewPager.isUserInputEnabled = !actionBar.isVisible
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = items.size

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        PAGE_CELL

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        WSegmentedControllerPageCell(context)

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val item = items.getOrNull(indexPath.row) ?: return
        val wasConfigured = item.viewController.isViewConfigured
        (cellHolder.cell as WSegmentedControllerPageCell).configure(
            item.viewController,
            indexPath.row == lastFullyVisible && currentOffset == lastFullyVisible.toFloat()
        )
        if (!wasConfigured) {
            item.viewController.view.post {
                item.viewController.insetsUpdated()
            }
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? =
        items.getOrNull(indexPath.row)?.identifier

    override fun onIndexChanged(to: Int, animated: Boolean) {
        onIndexChanged(to, animated, null)
    }

    fun onIndexChanged(to: Int, animated: Boolean, onCompletion: (() -> Unit)?) {
        if (to !in items.indices || isTabLocked || isInDragMode) return
        finishPageTransition()
        val shouldAnimate = animated && WGlobalStorage.getAreAnimationsActive()
        if (to == viewPager.currentItem) {
            viewPager.cancelSpringScroll()
            setActiveIndex(to, shouldAnimateTabScroll = shouldAnimate && shouldCenterSelectedTab)
            onCompletion?.invoke()
            return
        }
        if (shouldSkipIntermediatePages && shouldAnimate &&
            viewPager.width > 0 && isAttachedToWindow
        ) {
            selectPageDirectly(to, onCompletion)
            return
        }
        isAnimatingChangeTab = shouldAnimate
        targetIndex = to
        if (shouldAnimate) {
            viewPager.springToItem(to, 0f, onCompletion)
        } else {
            viewPager.setCurrentItem(to, false)
            onCompletion?.invoke()
        }
    }

    private fun selectPageDirectly(to: Int, onCompletion: (() -> Unit)?) {
        viewPager.cancelSpringScroll()
        val from = viewPager.currentItem
        val source = items.getOrNull(from)?.viewController ?: return
        val destination = items.getOrNull(to)?.viewController ?: return
        val selectionScroll = clearSegmentedControl.beginSelectionScroll(to)
        jumpToPage(from)
        updatePageOffset(from, 0f)
        val transition = DirectPageTransition(
            from,
            to,
            source,
            destination,
            viewPager.isUserInputEnabled,
            viewPager.importantForAccessibility,
            selectionScroll,
            onCompletion
        )
        directPageTransition = transition
        isAnimatingChangeTab = true
        isUserInteracting = false
        targetIndex = to
        viewPager.isUserInputEnabled = false
        viewPager.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        onDirectPageTransitionProgress?.invoke(from, to, 0f)
        viewPager.doOnPreDraw {
            if (!isCurrentPageTransition(transition)) return@doOnPreDraw
            viewPager.captureHardwareImage { bitmap ->
                if (!isCurrentPageTransition(transition)) {
                    bitmap?.recycle()
                    return@captureHardwareImage
                }
                if (bitmap == null) {
                    jumpToPage(to)
                    finishPageTransition()
                    onCompletion?.invoke()
                    return@captureHardwareImage
                }
                val snapshot = PageSnapshot(bitmap)
                transition.snapshot = snapshot
                blurSourceContainerView.overlay.add(snapshot)
                updateDirectPageTransition(transition, 0f)
                jumpToPage(to)
                currentOffset = to.toFloat()
                viewPager.doOnPreDraw startAnimation@{
                    if (!isCurrentPageTransition(transition)) return@startAnimation
                    transition.animator = ValueAnimator.ofFloat(0f, 1f).apply {
                        duration = AnimationConstants.QUICK_ANIMATION
                        interpolator = WInterpolator.emphasized
                        addUpdateListener {
                            if (directPageTransition === transition) {
                                updateDirectPageTransition(transition, it.animatedValue as Float)
                            }
                        }
                        doOnEnd {
                            if (directPageTransition === transition) {
                                finishPageTransition()
                                transition.onCompletion?.invoke()
                            }
                        }
                        start()
                    }
                }
                viewPager.invalidate()
            }
        }
        viewPager.invalidate()
    }

    private fun isCurrentPageTransition(transition: DirectPageTransition): Boolean =
        directPageTransition === transition && isAttachedToWindow &&
            items.getOrNull(transition.from)?.viewController === transition.source &&
            items.getOrNull(transition.to)?.viewController === transition.destination

    private fun jumpToPage(index: Int) {
        viewPager.setCurrentItem(index, false)
        val recyclerView = viewPager.getChildAt(0) as? RecyclerView ?: return
        (recyclerView.layoutManager as? LinearLayoutManager)?.scrollToPositionWithOffset(index, 0)
    }

    private fun updateDirectPageTransition(transition: DirectPageTransition, progress: Float) {
        transition.selectionScroll?.let {
            clearSegmentedControl.updateSelectionScroll(it, progress)
        }
        val direction = (if (transition.to > transition.from) 1f else -1f) *
            (if (LocaleController.isRTL) -1f else 1f)
        val distance = direction * viewPager.width
        viewPager.translationX = distance * (1f - progress)
        transition.snapshot?.apply {
            setBounds(viewPager.left, viewPager.top, viewPager.right, viewPager.bottom)
            offset = -distance * progress
            invalidateSelf()
        }
        clearSegmentedControl.updateThumbPosition(
            transition.to,
            offset = transition.from + (transition.to - transition.from) * progress,
            targetIndex = transition.to,
            force = false,
            isAnimatingToPosition = true,
            animateScroll = false,
            shouldFollowThumb = transition.selectionScroll == null
        )
        onDirectPageTransitionProgress?.invoke(transition.from, transition.to, progress)
    }

    fun finishPageTransition() {
        finishPageTransition(shouldNotifyOffset = true)
    }

    private fun finishPageTransition(shouldNotifyOffset: Boolean) {
        val transition = directPageTransition ?: return
        directPageTransition = null
        transition.animator?.apply {
            removeAllListeners()
            removeAllUpdateListeners()
            cancel()
        }
        transition.animator = null
        transition.snapshot?.let {
            blurSourceContainerView.overlay.remove(it)
            it.bitmap.recycle()
        }
        transition.snapshot = null
        val shouldCenterSelection = transition.selectionScroll
            ?.let(clearSegmentedControl::finishSelectionScroll) ?: true
        viewPager.translationX = 0f
        viewPager.isUserInputEnabled =
            transition.shouldRestoreUserInput && !isTabLocked && !actionBar.isVisible
        viewPager.importantForAccessibility = transition.accessibility
        isAnimatingChangeTab = false
        val index = viewPager.currentItem
        currentOffset = index.toFloat()
        targetIndex = index
        clearSegmentedControl.updateThumbPosition(
            index,
            offset = currentOffset,
            targetIndex = index,
            force = true,
            isAnimatingToPosition = !shouldCenterSelection,
            animateScroll = false
        )
        if (shouldNotifyOffset && index in items.indices) updatePageOffset(index, 0f)
    }

    override fun onItemMoved(from: Int, to: Int) {
        finishPageTransition()
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

    private fun determineNewSelectedIndex(currentIndex: Int, from: Int, to: Int): Int =
        when (currentIndex) {
            from -> to

            in (minOf(from, to) + 1)..maxOf(from, to) -> {
                if (from < to) currentIndex - 1 else currentIndex + 1
            }

            else -> currentIndex
        }

    fun onDestroy() {
        finishPageTransition(shouldNotifyOffset = false)
        if (ownsItems) items.forEach { it.viewController.onDestroy() }
        items = mutableListOf()
        onOffsetChange = null
        onDirectPageTransitionProgress = null
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
        if (clearSegmentedControl.isInDragMode) return
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
