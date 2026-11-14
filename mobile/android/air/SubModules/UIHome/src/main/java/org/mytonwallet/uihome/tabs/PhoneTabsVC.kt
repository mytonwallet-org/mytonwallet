package org.mytonwallet.uihome.tabs

import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.InsetDrawable
import android.net.Uri
import android.os.SystemClock
import android.view.Choreographer
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewTreeObserver
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.animation.doOnEnd
import androidx.core.net.toUri
import androidx.core.view.OneShotPreDrawListener
import androidx.core.view.children
import androidx.core.view.doOnLayout
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import kotlin.math.abs
import kotlin.math.roundToInt
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.FloatAnimator
import org.mytonwallet.app_air.icons.R as IconsR
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentListBarHost
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadListVC
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WNavigationController.PresentationConfig
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.commonViews.AccountItemView
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.UpdateStatusView
import org.mytonwallet.app_air.uicomponents.commonViews.toast.ToastHost
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.drawable.StickyBottomGradientDrawable
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.cancelSpring
import org.mytonwallet.app_air.uicomponents.extensions.cancelSpringScroll
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.extensions.setupSpringFling
import org.mytonwallet.app_air.uicomponents.extensions.springToItem
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.HomeStatusController
import org.mytonwallet.app_air.uicomponents.helpers.HomeToolbarActions
import org.mytonwallet.app_air.uicomponents.helpers.HomeToolbarBackgrounds
import org.mytonwallet.app_air.uicomponents.helpers.HomeToolbarLayout
import org.mytonwallet.app_air.uicomponents.helpers.OverlappedChromeFader
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.RevealUpdates
import org.mytonwallet.app_air.uicomponents.helpers.ToastHelper
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.frameInWindow
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.IPopup
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.clearSegmentedControl.WClearSegmentedControl
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopupView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.uifutures.viewControllers.futures.FuturesVC
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketVC
import org.mytonwallet.app_air.uisettings.viewControllers.settings.SettingsVC
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.PerpsAvailability
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MToolbarItem
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.EnvironmentStore
import org.mytonwallet.uihome.home.HomeVC
import org.mytonwallet.uihome.home.actions.HomeActionsSheetVC
import org.mytonwallet.uihome.tabs.views.HomeSearchField

class PhoneTabsVC(context: Context) :
    BaseTabsVC(context),
    WThemedView,
    WProtectedView,
    WalletCore.EventObserver {
    @Suppress("PropertyName")
    override val TAG = "Tabs"

    companion object {
        const val SEARCH_HEIGHT = 48
        const val SEARCH_TOP_MARGIN = 4
        const val SEARCH_BOTTOM_MARGIN = 10
        private const val SEARCH_KEYBOARD_GAP = 12
        private const val ACTIONS_ICON_SIZE = 18
        private const val TOOLBAR_AVATAR_ICON_SIZE = 40
        private const val TOOLBAR_SCAN_ICON_SIZE = 24
        private const val TOOLBAR_ACTION_ICON_SIZE = 24
        private const val TOOLBAR_SHAKE_ANGLE = 4f
        private const val AVATAR_SWAP_SCALE = 0.7f

        private const val ACTIONS_SHEET_INSET = 8

        private const val TOAST_HOST_BOTTOM_MARGIN = 12

        private const val BOTTOM_EXTRA_GAP = 7

        internal const val SEARCH_OVERLAY_ANIMATION = AnimationConstants.VERY_VERY_QUICK_ANIMATION
        internal const val TOP_TABS_HEIGHT = 44
        internal const val TOP_TABS_ROOT_INSET = WNavigationBar.DEFAULT_HEIGHT + 2
        private const val TOP_TABS_THUMB_HEIGHT = 36f
        private const val TOP_TABS_INSET = 4f
        private const val TOP_TAB_HORIZONTAL_PADDING = 20
        internal const val TOP_TABS_TOP_MARGIN = 8
        private const val TOP_TABS_START_MARGIN = 16
        private const val TOP_TABS_END_MARGIN = 70
        private const val TOP_AVATAR_SIZE = 44
        private const val TOP_AVATAR_ICON_SIZE = 36
        private const val TOP_AVATAR_RING_STROKE = 2f
        private const val TOP_AVATAR_RING_CYCLE_MS = 750L
        private const val TOP_AVATAR_END_MARGIN = 16

        // The tab bar is shorter than the avatar, so nudge it down to align their centers.
        internal const val TOP_TABS_CENTERING_OFFSET = (TOP_AVATAR_SIZE - TOP_TABS_HEIGHT) / 2

        // Distance from the tab bar's top margin to its bottom edge, offset included.
        internal const val TOP_TABS_BOTTOM_EDGE = TOP_TABS_CENTERING_OFFSET + TOP_TABS_HEIGHT

        private val UPDATE_BUTTON_AVAILABLE_TABS = setOf(
            AppTabsManager.ID_HOME,
            AppTabsManager.ID_SETTINGS
        )

        private const val GRADIENT_ALPHA = 229
        private const val AGENT_CHROME_SCALE = 0.9f

        // The search field's magnifier: 22 dp, 14 dp in from its leading edge
        // The design's "Android / Search" glyph in its 26 dp box, centred in the circle
        private const val CIRCLE_ICON_SIZE = 26
        private const val CIRCLE_ICON_START = 11

        // The field's own 22 dp magnifier, which the circle's grows out of
        private const val FIELD_ICON_SCALE = 22f / CIRCLE_ICON_SIZE
        private const val AGENT_CHROME_SHOW_MS = 300L
        private const val AGENT_CHROME_HIDE_MS = 300L
    }

    override val isSwipeBackAllowed = false
    override var ignoreSideGuttering = false

    override var currentTabId: Int
        get() = selectedTabId
        set(value) {
            if (value in PHONE_PUSHED_TAB_IDS) {
                pendingSelectedTab = AppTabsManager.ID_HOME
                pendingTabToPresentOverMain = value
            } else {
                pendingSelectedTab = value
            }
        }
    private var pendingSelectedTab: Int? = null
    private var pendingTabToPresentOverMain: Int? = null

    override fun exportSearchText(): String = searchView.currentText()

    override fun restoreSearchText(text: String) {
        searchView.restoreText(text)
    }

    override fun detachMountedStacks() {
        finishDirectTabTransition()
        toolbarEditor.cancel()
        dismissTabMenu()
        // The Agent list's search closes with this container, which the tablet layout does not take over
        finishAgentSearch()
        releaseAgentBar()
        // The stacks live inside the pager's pages rather than directly in contentView;
        // exportStacks() removes each nav from its own parent.
        contentView.removeAllViews()
    }

    // The Agent list goes on without this toolbar, as when the tablet layout takes the stacks over
    private fun releaseAgentBar() {
        isAgentBarReleased = true
        if (agentBarMorphDelegate.isInitialized()) agentBarMorph.stop()
        findAgentList()?.takeIf { it.barHost === agentBarHost }?.barHost = null
    }

    private var isAgentBarReleased = false

    private val contentView = object : WView(context) {
        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            if (directTabTransition != null) return true
            if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                springTabScroll?.let { topTabsControl.finishSelectionScroll(it.selectionScroll) }
                springTabScroll = null
            }
            return super.dispatchTouchEvent(event)
        }

        override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
            if (oldWidth > 0 && (width != oldWidth || height != oldHeight)) {
                finishDirectTabTransition()
            }
            super.onSizeChanged(width, height, oldWidth, oldHeight)
        }

        override fun onDetachedFromWindow() {
            finishDirectTabTransition()
            super.onDetachedFromWindow()
        }
    }

    private class DirectTabTransition(
        val from: Int,
        val to: Int,
        val tabIds: List<Int>,
        val source: TabPageView,
        val destination: TabPageView,
        val accountId: String?,
        val accessibility: Int,
        val selectionScroll: WClearSegmentedControl.SelectionScroll?
    ) {
        var layoutListener: OneShotPreDrawListener? = null
        var animator: ValueAnimator? = null
    }

    private var directTabTransition: DirectTabTransition? = null

    private class SpringTabScroll(
        val fromOffset: Float,
        val to: Int,
        val selectionScroll: WClearSegmentedControl.SelectionScroll
    ) {
        var isFinishing = false
    }

    private var springTabScroll: SpringTabScroll? = null
    private var tabPageOffset = 0f

    private inner class TabPageHolder(val page: TabPageView) : RecyclerView.ViewHolder(page)

    private inner class TabPagerAdapter : RecyclerView.Adapter<TabPageHolder>() {
        init {
            setHasStableIds(true)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
            TabPageHolder(TabPageView(context, tabPager))

        override fun onBindViewHolder(holder: TabPageHolder, position: Int) {
            val id = topTabIds[position]
            if (id == selectedTabId) revealedTabIds.add(id)
            if (id in revealedTabIds) {
                holder.page.bind(getNavigationStack(id))
            } else {
                holder.page.unbind()
            }
        }

        override fun onViewRecycled(holder: TabPageHolder) {
            holder.page.unbind()
        }

        override fun getItemCount(): Int = topTabIds.size

        override fun getItemId(position: Int): Long = topTabIds[position].toLong()
    }

    private var updateFloatingButton: WLabel? = null
    private var updateFloatingButtonBackground: WRippleDrawable? = null
    private var stickyBackgroundColor = WColor.SecondaryBackground.color

    override val minimizedBlurRootView: ViewGroup?
        get() = contentView
    val bottomBarHeight: Int
        get() {
            return (window?.systemBars?.bottom ?: 0) + (-2).dp
        }

    override val minimizedBrowserBottomInset: Int
        get() = bottomBarHeight + bottomOverlayExtraGap

    override fun rootTopInsetForTab(id: Int): Int {
        if (id == AppTabsManager.ID_SETTINGS) return 0
        return TOP_TABS_ROOT_INSET.dp
    }

    private var selectedTabId = AppTabsManager.ID_HOME
    private var selectingTabId: Int? = null

    private fun selectTab(itemId: Int, isInstant: Boolean = false) {
        finishDirectTabTransition()
        if (selectedTabId == itemId) {
            val index = topTabIds.indexOf(itemId)
            if (index >= 0) {
                topTabsControl.updateThumbPosition(
                    index = index,
                    offset = index.toFloat(),
                    targetIndex = index,
                    force = true,
                    isAnimatingToPosition = false,
                    shouldAnimateCenter = true
                )
            }
            navForOrNull(itemId)?.apply {
                if (viewControllers.size == 1) scrollToTop() else popToRoot()
            }
            return
        }

        selectingTabId = itemId
        committedTabId = itemId
        isAgentTopChromeShown = null
        finishAgentSearch()
        updateTopChromeVisibility(itemId)
        checkForUpdate(itemId)
        val isAgent = itemId == AppTabsManager.ID_AGENT
        ignoreSideGuttering = isAgent
        val wasAgent = selectedTabId == AppTabsManager.ID_AGENT
        if (wasAgent != isAgent) updateStickyBottomGradient()
        bottomReversedCornerView?.setHorizontalPadding(
            if (ignoreSideGuttering) 0f else ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat()
        )

        val newNav = getNavigationStack(itemId)
        updateToastAvailability(itemId)
        val oldNav = activeNavigationController

        if (searchView.hasFocus()) searchView.clearFocus()

        switchTab(itemId, oldNav, newNav, isInstant)
        selectingTabId = null
        selectedTabId = itemId
        updateAgentChrome()
        updateAgentBar()
    }

    private var topTabIds = emptyList<Int>()

    // Every page stays mounted once its tab has shown, so paging over it doesn't mount and lay out its screen
    // mid-slide; a tab not shown yet gets its screen when paging first reaches it
    private val revealedTabIds = HashSet<Int>()

    private fun revealPage(index: Int) {
        val id = topTabIds.getOrNull(index) ?: return
        if (!revealedTabIds.add(id)) return
        val pages = tabPager.getChildAt(0) as? RecyclerView ?: return
        val holder = pages.findViewHolderForAdapterPosition(index) as? TabPageHolder ?: return
        holder.page.bind(getNavigationStack(id))
    }

    // The pages not shown yet mount while the app idles once the selected one has appeared, so a tab's first visit
    // finds its screen laid out
    private var pagePreloader: TabPagePreloader? = null
    private var hasSelectedPageAppeared = false

    private fun createPagePreloader() = TabPagePreloader(
        view,
        isActive = { hasSelectedPageAppeared && !isDisappeared && window?.isPaused == false },
        isIdle = {
            tabPager.scrollState == ViewPager2.SCROLL_STATE_IDLE && !tabPager.isFakeDragging &&
                springingTabId == null && directTabTransition == null &&
                pendingTabAppearance == null &&
                (tabPager.getChildAt(0) as? ViewGroup)?.children
                    ?.none { (it as? TabPageView)?.isTouched == true } != false
        },
        nextPage = { topTabIds.indexOfFirst { it !in revealedTabIds }.takeIf { it >= 0 } },
        mount = ::revealPage,
        unmountInactive = ::unmountInactivePages
    )

    // Under memory pressure only the pages on screen stay mounted; the others mount again as paging reaches them
    private fun unmountInactivePages() {
        val pages = tabPager.getChildAt(0) as? RecyclerView ?: return
        val keptIds = setOfNotNull(
            selectedTabId,
            selectingTabId,
            directTabTransition?.let { it.tabIds[it.from] },
            topTabIds.getOrNull(tabPager.currentItem)
        )
        topTabIds.forEachIndexed { index, id ->
            if (id in keptIds || !revealedTabIds.remove(id)) return@forEachIndexed
            (pages.findViewHolderForAdapterPosition(index) as? TabPageHolder)?.page?.unbind()
        }
    }

    private val tabPagerAdapter = TabPagerAdapter()
    private var pendingTabAppearance: WNavigationController? = null
    private val tabPager by lazy {
        ViewPager2(context).apply {
            id = View.generateViewId()
            adapter = tabPagerAdapter
            registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
                override fun onPageScrolled(
                    position: Int,
                    positionOffset: Float,
                    positionOffsetPixels: Int
                ) {
                    tabPageOffset = position + positionOffset
                    if (directTabTransition != null || springTabScroll?.isFinishing == true) return
                    revealPage(position)
                    if (positionOffset > 0f) revealPage(position + 1)
                    // The Agent list's bar is hosted as soon as its page can show
                    val list = findAgentList()
                    if (list != null && list.barHost == null) updateAgentBar(isInstant = true)
                    springTabScroll?.let { scroll ->
                        val distance = scroll.to - scroll.fromOffset
                        val progress = if (distance == 0f) {
                            1f
                        } else {
                            (tabPageOffset - scroll.fromOffset) / distance
                        }
                        topTabsControl.updateSelectionScroll(scroll.selectionScroll, progress)
                    }
                    topTabsControl.updateThumbPosition(
                        index = position,
                        offset = position + positionOffset,
                        targetIndex = currentItem,
                        force = false,
                        isAnimatingToPosition = springTabScroll != null
                    )
                    keepAgentBarOnToolbar()
                }

                override fun onPageSelected(position: Int) {
                    if (directTabTransition != null || springTabScroll?.isFinishing == true) return
                    commitPage(position)
                }

                override fun onPageScrollStateChanged(state: Int) {
                    if (directTabTransition != null || springTabScroll?.isFinishing == true) return
                    // The finger or the pager took over from a tapped tab's slide
                    springingTabId = null
                    if (state == ViewPager2.SCROLL_STATE_DRAGGING) {
                        cancelSpring()
                        springTabScroll?.let {
                            topTabsControl.finishSelectionScroll(it.selectionScroll)
                        }
                        springTabScroll = null
                    }
                    if (state != ViewPager2.SCROLL_STATE_IDLE) return
                    finishSpringTabScroll()
                    val index = currentItem
                    // Page frames center the strip; idle must not override a touch that canceled that motion
                    topTabsControl.updateThumbPosition(
                        index = index,
                        offset = index.toFloat(),
                        targetIndex = index,
                        force = true,
                        isAnimatingToPosition = true
                    )
                    commitPage(index)
                    val tabId = topTabIds.getOrNull(index)
                    if (selectingTabId == null &&
                        tabId != null &&
                        selectedTabId != tabId
                    ) {
                        selectTab(tabId)
                    }
                    completePendingTabAppearance()
                }
            })
            (getChildAt(0) as? RecyclerView)?.apply {
                itemAnimator = null
                // The Agent page draws over its neighbours, so its bar stays on the toolbar as the page slides
                clipChildren = false
                setChildDrawingOrderCallback { childCount, i ->
                    orderAgentPageLast(this, childCount, i)
                }
            }
            setupSpringFling { target ->
                target.coerceIn(currentItem - 1, currentItem + 1).also(::commitPage)
            }
        }
    }

    private fun switchTab(
        itemId: Int,
        oldNav: WNavigationController?,
        newNav: WNavigationController,
        isInstant: Boolean
    ) {
        val index = topTabIds.indexOf(itemId)
        if (index < 0) return
        if (oldNav !== newNav) {
            // A switch started before the previous one settled would otherwise drop the earlier
            // nav's viewDidAppear, leaving its viewWillAppear unmatched.
            completePendingTabAppearance()
            oldNav?.viewWillDisappear()
            newNav.viewWillAppear()
            pendingTabAppearance = newNav
        }
        val previousIndex = tabPager.currentItem
        revealPage(previousIndex)
        revealPage(index)
        val animated = !isInstant && WGlobalStorage.getAreAnimationsActive()
        if (animated && previousIndex != index && tabPager.width > 0) {
            if (abs(previousIndex - index) > 1) {
                if (!startDirectTabTransition(previousIndex, index)) {
                    tabPager.cancelSpringScroll()
                    jumpToPage(index)
                    completePendingTabAppearance()
                }
                return
            }
            val scroll = topTabsControl.beginSelectionScroll(index)?.let {
                SpringTabScroll(tabPageOffset, index, it)
            }
            springTabScroll = scroll
            springingTabId = itemId
            tabPager.springToItem(index) {
                if (scroll != null && springTabScroll === scroll) finishSpringTabScroll()
                if (springingTabId == itemId) springingTabId = null
                completePendingTabAppearance()
            }
        } else {
            jumpToPage(index)
            completePendingTabAppearance()
        }
    }

    // A pager out of the window reports no scroll, so the tab bar moves with the page here
    private fun jumpToPage(index: Int) {
        tabPager.setCurrentItem(index, false)
        tabPageOffset = index.toFloat()
        topTabsControl.updateThumbPosition(
            index = index,
            offset = index.toFloat(),
            targetIndex = index,
            force = true,
            isAnimatingToPosition = false,
            animateScroll = false
        )
    }

    private fun finishSpringTabScroll(shouldCancelPage: Boolean = false) {
        val scroll = springTabScroll ?: return
        if (shouldCancelPage) {
            scroll.isFinishing = true
            tabPager.cancelSpringScroll()
            tabPager.setCurrentItem(scroll.to, false)
            tabPageOffset = scroll.to.toFloat()
            springingTabId = null
        }
        springTabScroll = null
        val shouldCenterSelection = topTabsControl.finishSelectionScroll(scroll.selectionScroll)
        val index = tabPager.currentItem
        topTabsControl.updateThumbPosition(
            index = index,
            offset = index.toFloat(),
            targetIndex = index,
            force = true,
            isAnimatingToPosition = !shouldCenterSelection,
            animateScroll = false
        )
        keepAgentBarOnToolbar()
        if (shouldCancelPage) completePendingTabAppearance()
    }

    private fun startDirectTabTransition(from: Int, to: Int): Boolean {
        if (!tabPager.isAttachedToWindow || isDisappeared) return false
        val pages = tabPager.getChildAt(0) as? RecyclerView ?: return false
        val source = (pages.findViewHolderForAdapterPosition(from) as? TabPageHolder)?.page
            ?: return false
        val destination = (pages.findViewHolderForAdapterPosition(to) as? TabPageHolder)?.page
            ?: return false
        val transition = DirectTabTransition(
            from,
            to,
            topTabIds,
            source,
            destination,
            AccountStore.activeAccountId,
            contentView.importantForAccessibility,
            topTabsControl.beginSelectionScroll(to)
        )
        directTabTransition = transition
        val now = SystemClock.uptimeMillis()
        val cancel = MotionEvent.obtain(now, now, MotionEvent.ACTION_CANCEL, 0f, 0f, 0)
        tabPager.dispatchTouchEvent(cancel)
        cancel.recycle()
        tabPager.cancelSpringScroll()
        springingTabId = null
        tabPager.isUserInputEnabled = false
        contentView.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        tabPager.setCurrentItem(to, false)
        (pages.layoutManager as? LinearLayoutManager)?.scrollToPositionWithOffset(to, 0)
        transition.layoutListener = tabPager.doOnPreDraw {
            transition.layoutListener = null
            if (!isCurrentDirectTabTransition(transition)) {
                if (directTabTransition === transition) finishDirectTabTransition()
                return@doOnPreDraw
            }
            updateDirectTabTransition(transition, 0f)
            transition.animator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = AnimationConstants.QUICK_ANIMATION
                interpolator = WInterpolator.emphasized
                addUpdateListener {
                    if (directTabTransition === transition) {
                        updateDirectTabTransition(transition, it.animatedValue as Float)
                    }
                }
                doOnEnd {
                    if (directTabTransition === transition) finishDirectTabTransition()
                }
                start()
            }
        }
        tabPager.invalidate()
        return true
    }

    private fun isCurrentDirectTabTransition(transition: DirectTabTransition): Boolean =
        directTabTransition === transition && topTabIds === transition.tabIds &&
            AccountStore.activeAccountId == transition.accountId && !isDisappeared &&
            transition.source.isAttachedToWindow && transition.destination.isAttachedToWindow

    private fun updateDirectTabTransition(transition: DirectTabTransition, progress: Float) {
        transition.selectionScroll?.let { topTabsControl.updateSelectionScroll(it, progress) }
        val direction = (if (transition.to > transition.from) 1f else -1f) *
            (if (LocaleController.isRTL) -1f else 1f)
        val distance = direction * tabPager.width
        transition.source.translationX = -transition.source.left - distance * progress
        transition.destination.translationX =
            -transition.destination.left + distance * (1f - progress)
        topTabsControl.updateThumbPosition(
            index = transition.to,
            offset = transition.from + (transition.to - transition.from) * progress,
            targetIndex = transition.to,
            force = false,
            isAnimatingToPosition = true,
            animateScroll = false,
            shouldFollowThumb = transition.selectionScroll == null
        )
        keepAgentBarOnToolbar()
    }

    private fun finishDirectTabTransition() {
        finishSpringTabScroll(shouldCancelPage = true)
        val transition = directTabTransition ?: return
        directTabTransition = null
        transition.layoutListener?.removeListener()
        transition.layoutListener = null
        transition.animator?.apply {
            removeAllListeners()
            removeAllUpdateListeners()
            cancel()
        }
        transition.animator = null
        val shouldCenterSelection = transition.selectionScroll
            ?.let(topTabsControl::finishSelectionScroll) ?: true
        transition.source.translationX = 0f
        transition.destination.translationX = 0f
        contentView.importantForAccessibility = transition.accessibility
        val index = tabPager.currentItem
        topTabsControl.updateThumbPosition(
            index = index,
            offset = index.toFloat(),
            targetIndex = index,
            force = true,
            isAnimatingToPosition = !shouldCenterSelection,
            animateScroll = false
        )
        commitPage(index)
        keepAgentBarOnToolbar()
        updateAgentChrome()
        updateAgentBar()
        completePendingTabAppearance()
    }

    private fun completePendingTabAppearance() {
        pendingTabAppearance?.let { nav ->
            if (!nav.isDisappeared) {
                nav.viewDidAppear()
            }
        }
        pendingTabAppearance = null
        pagePreloader?.schedule()
    }

    private val topTabsDelegate = object : WClearSegmentedControl.Delegate {
        override fun onIndexChanged(to: Int, animated: Boolean) {
            topTabIds.getOrNull(to)?.let { selectTab(it) }
        }

        override fun onItemMoved(from: Int, to: Int) {}

        override fun enterReorderingMode() {}
    }
    private val topTabsControl by lazy {
        WClearSegmentedControl(
            context,
            horizontalPaddingDp = TOP_TABS_INSET,
            thumbHeightDp = TOP_TABS_THUMB_HEIGHT,
            // Tabs keep the design's padding and scroll when they don't fit, rather than narrowing
            itemHorizontalPaddingDp = TOP_TAB_HORIZONTAL_PADDING,
            minItemHorizontalPaddingDp = TOP_TAB_HORIZONTAL_PADDING,
            itemSpacingDp = 0
        ).apply {
            centersThumb = true
            paintColor = WColor.Tint.color.colorWithAlpha(31)
            primaryTextColorOverride = WColor.Tint.color
            fillAvailableWidth = true
            onSelectedItemClick = ::presentTabMenu
            onLongPress = ::presentTabMenu
        }
    }
    private var topTabsGlass: WGlassView? = null
    private var tabMenuPopup: INavigationPopup? = null

    // The tab menu reorders the tabs while it stays open
    private var isApplyingTabMenuOrder = false

    private val topAvatarRipple by lazy {
        WRippleDrawable.create(TOP_AVATAR_SIZE.dp / 2f)
    }
    private val topAvatarIconView by lazy {
        AccountIconView(
            context,
            AccountIconView.Usage.ViewItem(14f.dp)
        )
    }
    private val alternateTopAvatarIconView by lazy {
        AccountIconView(
            context,
            AccountIconView.Usage.ViewItem(14f.dp)
        ).apply {
            alpha = 0f
            isInvisible = true
        }
    }
    private var visibleTopAvatarIconView: AccountIconView? = null
    private val topAvatarRingDrawable by lazy {
        RoundProgressDrawable(
            TOP_AVATAR_SIZE.toFloat(),
            TOP_AVATAR_RING_STROKE,
            TOP_AVATAR_RING_CYCLE_MS
        )
    }
    private val topAvatarRingView by lazy {
        View(context).apply {
            id = View.generateViewId()
            background = InsetDrawable(
                topAvatarRingDrawable,
                (TOP_AVATAR_RING_STROKE / 2f).dp.roundToInt()
            )
            alpha = 0f
            isInvisible = true
        }
    }
    private var topAvatarStatus: UpdateStatusView.State? = null
    private val topAvatarStatusListener = HomeStatusController.Listener { state, animated ->
        RevealUpdates.runOrHold(topAvatarRingView, topAvatarRingView) {
            applyTopAvatarStatus(state, animated)
        }
    }
    private val topAvatarView: WFrameLayout by lazy {
        WFrameLayout(context).apply {
            id = UIComponentsR.id.tab_settings_button
            setBackgroundColor(Color.TRANSPARENT, TOP_AVATAR_SIZE.dp / 2f, clipToBounds = true)
            foreground = topAvatarRipple
            addView(topAvatarRingView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            contentDescription = LocaleController.getString("Settings")
            val iconLayoutParams = FrameLayout.LayoutParams(
                TOP_AVATAR_ICON_SIZE.dp,
                TOP_AVATAR_ICON_SIZE.dp,
                Gravity.CENTER
            )
            addView(topAvatarIconView, iconLayoutParams)
            addView(alternateTopAvatarIconView, FrameLayout.LayoutParams(iconLayoutParams))
            setOnClickListener { switchToSettings(null) }
            setOnTouchListener(::recordProfileDown)
            // Moving the finger turns the switcher into a drag
            setOnLongClickListener { button ->
                val isTouch = button.isPressed
                val isPresented = presentWalletSwitcherPopup(button)
                val isDragging = isTouch && isPhoneSearchShown && canStartToolbarDrag() &&
                    toolbarEditor.startTopDrag(
                        getScreenFrame(button),
                        onLift = ::dismissWalletSwitcher,
                        downX = profileDownX,
                        downY = profileDownY
                    )
                isDragging || isPresented
            }
        }
    }
    private var topAvatarGlass: WGlassView? = null
    private var isTopChromeHidden = false

    private fun reloadTopTabs(selectedItemId: Int = selectedTabId) {
        finishDirectTabTransition()
        if (!isApplyingTabMenuOrder) dismissTabMenu()
        val tabs = AppTabsManager.orderedTabs.filter {
            it.intId !in PHONE_PUSHED_TAB_IDS
        }
        topTabIds = tabs.map { it.intId }
        tabPager.offscreenPageLimit = (topTabIds.size - 1).coerceAtLeast(1)
        val requestedIndex = topTabIds.indexOf(selectedItemId)
        val selectedIndex = requestedIndex.coerceAtLeast(0)
        if (requestedIndex < 0) {
            // The requested tab has no page (e.g. Settings, which is pushed instead), so
            // keep the selected id in sync with the page the pager actually shows.
            topTabIds.getOrNull(selectedIndex)?.let {
                if (selectedTabId != it) selectTab(it)
            }
        }
        topTabsControl.setItems(
            tabs.map {
                WClearSegmentedControl.Item(
                    title = LocaleController.getString(it.labelKey),
                    onRemove = null,
                    onClick = null,
                    testViewId = it.testViewId
                )
            },
            selectedIndex,
            topTabsDelegate
        )
        tabPagerAdapter.notifyDataSetChanged()
        if (topTabIds.isNotEmpty()) {
            tabPager.setCurrentItem(selectedIndex, false)
        }
        updateTopChromeVisibility(selectedItemId)
    }

    // Whether the Agent list's tabs showed, when they come and go as chats cover the list
    private var isAgentTopChromeShown: Boolean? = null

    // Whether a screen pushed over the Agent list covers its tabs, and whether they wait for it to finish coming
    private var isAgentChromeCovered = false
    private var isAgentChromeAwaitingCover = false

    private val agentCoverGroup = AgentListCoverGroup()

    private val agentCoverView by lazy {
        AgentListCoverView(context, agentCoverGroup) {
            navForOrNull(AppTabsManager.ID_AGENT)?.takeIf {
                selectedTabId == AppTabsManager.ID_AGENT && topTabsControl.isVisible
            }
        }.apply { onFrame = ::followAgentCover }
    }

    // The screens pushed over the Agent list come over the toolbar's circle there, and dim it, as they do the list's
    // own bar beside it
    private val agentBarCoverView by lazy {
        AgentListCoverView(context, agentCoverGroup) {
            navForOrNull(AppTabsManager.ID_AGENT)?.takeIf {
                selectedTabId == AppTabsManager.ID_AGENT && agentBarMorphDelegate.isInitialized() &&
                    agentBarMorph.shouldKeepToolbar
            }
        }
    }

    private fun updateTopChromeVisibility(selectedItemId: Int) {
        val isAgent = selectedItemId == AppTabsManager.ID_AGENT
        // The tabs come back as a chat starts to leave the list, not once it has gone
        val depth = if (isAgent && findAgentList()?.isBarCovered == false) {
            1
        } else {
            navForOrNull(selectedItemId)?.viewControllers?.size ?: 1
        }
        // A question written in the list gives the header to a new chat
        val isComposing = isAgent && findAgentList()?.isComposing == true
        val shouldShowTabs = !isTopChromeHidden && !isComposing &&
            shouldShowPhoneTopTabs(selectedItemId, depth)
        if (!shouldShowTabs) dismissTabMenu()
        val shouldShowAvatar = shouldShowTopAvatar(shouldShowTabs)
        val shouldFade = isAgent && !isTopChromeHidden && isAgentTopChromeShown != null &&
            isAgentTopChromeShown != shouldShowTabs && WGlobalStorage.getAreAnimationsActive()
        isAgentTopChromeShown = if (isAgent) shouldShowTabs else null
        val isCovered = isAgent && depth > 1
        val isCoverChange = isCovered != isAgentChromeCovered
        isAgentChromeCovered = isCovered
        if (shouldFade && isCoverChange) {
            coverAgentTopChrome(shouldShowTabs, shouldShowAvatar)
            return
        }
        if (shouldFade) {
            fadeAgentTopChrome(topTabsControl, shouldShowTabs)
            fadeAgentTopChrome(topAvatarView, shouldShowAvatar)
            return
        }
        if (isAgent && isAgentTopChromeFadingIn == shouldShowTabs) return
        // The tabs under a screen still coming over the list stay until it has come
        if (isAgentChromeAwaitingCover && isCovered && !shouldShowTabs) return
        cancelAgentTopChromeFade()
        isAgentChromeAwaitingCover = false
        topTabsControl.isVisible = shouldShowTabs
        topAvatarView.isVisible = shouldShowAvatar
        if (!isTopChromeHidden) {
            topTabsControl.alpha = 1f
            topAvatarView.alpha = 1f
        }
    }

    private fun shouldShowTopAvatar(shouldShowTabs: Boolean): Boolean = shouldShowTabs &&
        AccountStore.permanentActiveAccount != null &&
        !toolbarConfiguration.isShown(MToolbarItem.ACCOUNTS)

    private var isAgentTopChromeFadingIn: Boolean? = null

    // The tabs lie on the list's layer: a screen pushed over it comes over them, drawn there by the cover view, and
    // they go once it has come; one going away leaves them shown under it from its start
    private fun coverAgentTopChrome(shouldShowTabs: Boolean, shouldShowAvatar: Boolean) {
        cancelAgentTopChromeFade()
        isAgentChromeAwaitingCover = !shouldShowTabs
        if (!shouldShowTabs) return
        topTabsControl.alpha = 1f
        topTabsControl.isVisible = true
        topAvatarView.alpha = 1f
        topAvatarView.isVisible = shouldShowAvatar
    }

    // Once the screen pushed over the list has come, the list leaves the stack and the tabs go with it
    private fun followAgentCover() {
        if (!isAgentChromeAwaitingCover) return
        val navigation = navForOrNull(AppTabsManager.ID_AGENT)
        val listView = navigation?.viewControllers?.firstOrNull()?.view
        if (listView != null && listView.parent === navigation) return
        isAgentChromeAwaitingCover = false
        if (isAgentTopChromeShown != false) return
        topTabsControl.isVisible = false
        topAvatarView.isVisible = false
        // The halos synced before this ran, so they go in the same frame only when hidden here
        topTabsGlass?.isVisible = false
        topAvatarGlass?.isVisible = false
    }

    private fun cancelAgentTopChromeFade() {
        if (isAgentTopChromeFadingIn == null) return
        isAgentTopChromeFadingIn = null
        listOf(topTabsControl, topAvatarView).forEach {
            it.animate().cancel()
            it.scaleX = 1f
            it.scaleY = 1f
        }
    }

    // The tabs and the avatar give way to a chat's header and come back with the list
    private fun fadeAgentTopChrome(view: View, shouldShow: Boolean) {
        view.animate().cancel()
        isAgentTopChromeFadingIn = shouldShow
        if (shouldShow) {
            if (!view.isVisible) {
                view.alpha = 0f
                view.scaleX = AGENT_CHROME_SCALE
                view.scaleY = AGENT_CHROME_SCALE
            }
            view.isVisible = true
        }
        view.animate()
            .alpha(if (shouldShow) 1f else 0f)
            .scaleX(if (shouldShow) 1f else AGENT_CHROME_SCALE)
            .scaleY(if (shouldShow) 1f else AGENT_CHROME_SCALE)
            .setDuration(if (shouldShow) AGENT_CHROME_SHOW_MS else AGENT_CHROME_HIDE_MS)
            // Going, they cross-fade with the new chat's header, which comes in on this curve
            .setInterpolator(
                if (shouldShow) {
                    WInterpolator.emphasizedDecelerate
                } else {
                    AccelerateDecelerateInterpolator()
                }
            )
            .withEndAction {
                isAgentTopChromeFadingIn = null
                if (!shouldShow) view.isVisible = false
                view.scaleX = 1f
                view.scaleY = 1f
                if (!shouldShow) view.alpha = 1f
            }
            .start()
    }

    private fun hideTopChromeView(view: View?) {
        view ?: return
        view.animate().cancel()
        view.fadeOut(AnimationConstants.QUICK_ANIMATION / 2) {
            if (isTopChromeHidden) view.isInvisible = true
        }
    }

    private fun showTopChromeView(view: View?, shouldShow: Boolean) {
        view ?: return
        view.animate().cancel()
        if (!shouldShow) {
            view.alpha = 1f
            view.isInvisible = true
            return
        }
        view.isVisible = true
        view.fadeIn(AnimationConstants.QUICK_ANIMATION / 2)
    }

    private fun applyTopAvatarStatus(state: UpdateStatusView.State, animated: Boolean) {
        topAvatarStatus = state
        applyAvatarRingStatus(topAvatarRingView, state, animated)
        applyAvatarRingStatus(toolbarAccountsRingView, state, animated)
    }

    private fun applyAvatarRingStatus(
        ringView: View,
        state: UpdateStatusView.State,
        animated: Boolean
    ) {
        val shouldShow = state !is UpdateStatusView.State.Updated
        ringView.animate().cancel()
        if (!animated) {
            ringView.alpha = if (shouldShow) 1f else 0f
            ringView.isInvisible = !shouldShow
            return
        }
        if (shouldShow) {
            ringView.isVisible = true
            ringView.fadeIn(AnimationConstants.QUICK_ANIMATION)
        } else {
            ringView.fadeOut(AnimationConstants.QUICK_ANIMATION) {
                if (topAvatarStatus is UpdateStatusView.State.Updated) {
                    ringView.isInvisible = true
                }
            }
        }
    }

    private fun updateTopAvatar() {
        updateToolbarAvatar()
        updateTopChromeVisibility(selectedTabId)
    }

    private fun updateTopChromeLayout() {
        if (topTabsControl.parent == null) return
        val systemBars = window?.systemBars
        val startSystemInset = if (LocaleController.isRTL) {
            systemBars?.right ?: 0
        } else {
            systemBars?.left ?: 0
        }
        val endSystemInset = if (LocaleController.isRTL) {
            systemBars?.left ?: 0
        } else {
            systemBars?.right ?: 0
        }
        val top = (systemBars?.top ?: 0) + TOP_TABS_TOP_MARGIN.dp
        if (agentCoverView.parent != null) {
            agentCoverView.updateLayoutParams {
                height = top + TOP_AVATAR_SIZE.dp + WGlassView.GLASS_PADDING_DP.dp
            }
        }
        val hasAvatar = !toolbarConfiguration.isShown(MToolbarItem.ACCOUNTS)
        val isAvatarAtStart = toolbarConfiguration.isAccountsAtStart
        view.setConstraints {
            toTopPx(topAvatarView, top)
            clear(topAvatarView.id, ConstraintSet.START)
            clear(topAvatarView.id, ConstraintSet.END)
            if (isAvatarAtStart) {
                toStartPx(topAvatarView, startSystemInset + TOP_AVATAR_END_MARGIN.dp)
            } else {
                toEndPx(topAvatarView, endSystemInset + TOP_AVATAR_END_MARGIN.dp)
            }
            toTopPx(topTabsControl, top + TOP_TABS_CENTERING_OFFSET.dp)
            toStartPx(
                topTabsControl,
                startSystemInset +
                    if (hasAvatar &&
                        isAvatarAtStart
                    ) {
                        TOP_TABS_END_MARGIN.dp
                    } else {
                        TOP_TABS_START_MARGIN.dp
                    }
            )
            toEndPx(
                topTabsControl,
                endSystemInset +
                    if (hasAvatar &&
                        !isAvatarAtStart
                    ) {
                        TOP_TABS_END_MARGIN.dp
                    } else {
                        TOP_TABS_START_MARGIN.dp
                    }
            )
        }
    }

    private val toastHostView by lazy {
        ToastHost(context).apply {
            attachBlurRoot(contentView)
        }
    }

    private val topChromeBlurViews
        get() = listOfNotNull(searchGlass, topTabsGlass, topAvatarGlass) +
            toolbarBackgroundGlasses
    private var searchGlass: WGlassView? = null
    private val searchView by lazy {
        HomeSearchField(
            context,
            onSearch = { query, focused -> updateSearch(query, focused) },
            onSubmit = { field -> submitExploreSearch(field) },
            onFocusProgressChanged = { updateActionsButtonMorph() }
        ).apply {
            alpha = 0f
            visibility = View.INVISIBLE
            translationY = -SEARCH_BOTTOM_MARGIN.dp.toFloat()
        }
    }
    private val searchEditText: WSearchEditText
        get() = searchView.editText

    // Round "+" button beside the search field; opens the actions sheet,
    // or morphs into an "X" that closes the search while it has focus.
    private val toolbarButtonItems = MToolbarItem.entries - MToolbarItem.SEARCH
    private val toolbarBackgroundsSync = HomeToolbarBackgrounds(context, ::getToolbarView)
    private val toolbarBackgroundGlasses = mutableListOf<WGlassView>()
    private val toolbarBackgroundsListener = ViewTreeObserver.OnPreDrawListener {
        val isToggled = toolbarBackgroundsSync.sync(
            toolbarOrder,
            toolbarConfiguration.isSharedBackground
        )
        // The glass root already updated this frame
        if (isToggled) toolbarBackgroundGlasses.firstOrNull()?.syncRootNow()
        true
    }
    private val actionsButtonIcon by lazy {
        AppCompatImageView(context).apply {
            setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_plus_thick)
            setColorFilter(WColor.SecondaryText.color)
        }
    }
    private val actionsButtonRipple by lazy {
        WRippleDrawable.create(SEARCH_HEIGHT.dp / 2f).apply {
            rippleColor = WColor.BackgroundRipple.color
        }
    }
    private val actionsButton by lazy {
        WFrameLayout(context).apply {
            id = UIComponentsR.id.home_more_actions_button
            alpha = 0f
            visibility = View.INVISIBLE
            isClickable = true
            contentDescription = LocaleController.getString("More actions")
            setBackgroundColor(Color.TRANSPARENT, SEARCH_HEIGHT.dp / 2f, clipToBounds = true)
            addView(
                actionsButtonIcon,
                FrameLayout.LayoutParams(ACTIONS_ICON_SIZE.dp, ACTIONS_ICON_SIZE.dp, Gravity.CENTER)
            )
            foreground = actionsButtonRipple
            setOnClickListener {
                if (searchEditText.hasFocus()) {
                    searchEditText.setText("")
                    clearSearchFocus()
                } else {
                    presentActionsSheet()
                }
            }
            setOnLongClickListener { startToolbarItemDrag(MToolbarItem.ACTIONS) }
        }
    }

    private val toolbarAccountsRipple by lazy {
        WRippleDrawable.create(SEARCH_HEIGHT.dp / 2f)
    }

    // Two, to crossfade
    private val toolbarAccountsIconViews by lazy {
        List(2) { AccountIconView(context, AccountIconView.Usage.ViewItem(14f.dp)) }
    }
    private var toolbarAccountsIconIndex = 0
    private val toolbarAccountsIconView: AccountIconView
        get() = toolbarAccountsIconViews[toolbarAccountsIconIndex]
    private val toolbarAccountsRingDrawable by lazy {
        RoundProgressDrawable(
            SEARCH_HEIGHT.toFloat(),
            TOP_AVATAR_RING_STROKE,
            TOP_AVATAR_RING_CYCLE_MS
        )
    }
    private val toolbarAccountsRingView by lazy {
        View(context).apply {
            id = View.generateViewId()
            background = InsetDrawable(
                toolbarAccountsRingDrawable,
                (TOP_AVATAR_RING_STROKE / 2f).dp.roundToInt()
            )
            alpha = 0f
            isInvisible = true
        }
    }
    private val toolbarAccountsButton by lazy {
        WFrameLayout(context).apply {
            id = UIComponentsR.id.home_toolbar_accounts_button
            visibility = View.GONE
            setBackgroundColor(Color.TRANSPARENT, SEARCH_HEIGHT.dp / 2f, clipToBounds = true)
            foreground = toolbarAccountsRipple
            contentDescription = LocaleController.getString("Settings")
            addView(toolbarAccountsRingView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            toolbarAccountsIconViews.forEachIndexed { index, icon ->
                icon.alpha = if (index == toolbarAccountsIconIndex) 1f else 0f
                addView(
                    icon,
                    FrameLayout.LayoutParams(
                        TOOLBAR_AVATAR_ICON_SIZE.dp,
                        TOOLBAR_AVATAR_ICON_SIZE.dp,
                        Gravity.CENTER
                    )
                )
            }
            setOnClickListener { switchToSettings(null) }
            setOnTouchListener(::recordProfileDown)
            // Moving the finger turns the switcher into a drag
            setOnLongClickListener { button ->
                val isTouch = button.isPressed
                val isPresented = presentWalletSwitcherPopup(button, WMenuPopup.Positioning.ABOVE)
                val isDragging = isTouch && canStartToolbarDrag() &&
                    toolbarEditor.startToolbarDrag(
                        MToolbarItem.ACCOUNTS,
                        getScreenFrame(button),
                        onLift = ::dismissWalletSwitcher,
                        downX = profileDownX,
                        downY = profileDownY
                    )
                isDragging || isPresented
            }
        }
    }

    private val toolbarScanIcon by lazy {
        AppCompatImageView(context).apply {
            setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_qr_code_scan_18_24)
            setColorFilter(WColor.SecondaryText.color)
        }
    }
    private val toolbarScanRipple by lazy {
        WRippleDrawable.create(SEARCH_HEIGHT.dp / 2f)
    }
    private val toolbarScanButton by lazy {
        WFrameLayout(context).apply {
            id = UIComponentsR.id.home_toolbar_scan_button
            visibility = View.GONE
            isClickable = true
            contentDescription = LocaleController.getString("Scan QR")
            setBackgroundColor(Color.TRANSPARENT, SEARCH_HEIGHT.dp / 2f, clipToBounds = true)
            addView(
                toolbarScanIcon,
                FrameLayout.LayoutParams(
                    TOOLBAR_SCAN_ICON_SIZE.dp,
                    TOOLBAR_SCAN_ICON_SIZE.dp,
                    Gravity.CENTER
                )
            )
            foreground = toolbarScanRipple
            setOnClickListener { performToolbarAction(MToolbarItem.SCAN) }
            setOnLongClickListener { startToolbarItemDrag(MToolbarItem.SCAN) }
        }
    }

    private val toolbarActionIcons = mutableListOf<AppCompatImageView>()
    private val toolbarActionItemButtons by lazy {
        MToolbarItem.ACTION_ITEMS.filter { it != MToolbarItem.SCAN }
            .associateWith(::createToolbarActionButton)
    }

    private fun createToolbarActionButton(item: MToolbarItem): View {
        val icon = AppCompatImageView(context).apply {
            setImageResource(getToolbarIconRes(item))
            setColorFilter(WColor.SecondaryText.color)
        }
        toolbarActionIcons += icon
        return WFrameLayout(context).apply {
            id = View.generateViewId()
            visibility = View.GONE
            isClickable = true
            contentDescription = HomeToolbarActions.getTitle(item)
            setBackgroundColor(Color.TRANSPARENT, SEARCH_HEIGHT.dp / 2f, clipToBounds = true)
            addView(
                icon,
                FrameLayout.LayoutParams(
                    getToolbarIconSize(item).dp,
                    getToolbarIconSize(item).dp,
                    Gravity.CENTER
                )
            )
            foreground = WRippleDrawable.create(SEARCH_HEIGHT.dp / 2f)
            setOnClickListener { performToolbarAction(item) }
            setOnLongClickListener { startToolbarItemDrag(item) }
        }
    }

    private fun getToolbarIconRes(item: MToolbarItem): Int = when (item) {
        MToolbarItem.ACTIONS -> org.mytonwallet.app_air.icons.R.drawable.ic_plus_thick
        else -> HomeToolbarActions.getToolbarIconRes(item)
    }

    private fun getToolbarIconSize(item: MToolbarItem): Int = when (item) {
        MToolbarItem.SCAN -> TOOLBAR_SCAN_ICON_SIZE
        MToolbarItem.ACTIONS -> ACTIONS_ICON_SIZE
        MToolbarItem.ACCOUNTS -> TOOLBAR_AVATAR_ICON_SIZE
        else -> TOOLBAR_ACTION_ICON_SIZE
    }

    private fun performToolbarAction(item: MToolbarItem) {
        if (!HomeToolbarActions.isAvailable(item, toolbarAccount)) return
        val homeVC = navForOrNull(AppTabsManager.ID_HOME)
            ?.viewControllers?.firstOrNull() as? HomeVC ?: return
        clearSearchFocus()
        homeVC.onHeaderAction(HomeToolbarActions.getIdentifier(item))
    }

    private val toolbarHideableItems = MToolbarItem.entries.filter { it.isHideable }
    private val toolbarActionButtons by lazy { toolbarHideableItems.map(::getToolbarView) }

    private var toolbarConfiguration = WGlobalStorage.getToolbarConfiguration()
    private val toolbarStarts = FloatArray(MToolbarItem.entries.size)
    private var toolbarFocus = 0f
    private val toolbarVisibility: (MToolbarItem) -> Float = { item ->
        when {
            item == editedToolbarItem -> toolbarEditGap

            item.isHideable ->
                getToolbarButtonVisibility(getToolbarView(item)) * toolbarFades[item.ordinal]

            else -> 1f
        }
    }

    private fun getToolbarButtonVisibility(button: View): Float =
        if (button.visibility == View.GONE) 0f else 1 - toolbarFocus

    private val toolbarFades = FloatArray(MToolbarItem.entries.size) { 1f }
    private var toolbarFadeAnimator: ValueAnimator? = null

    private val toolbarAccount: MAccount?
        get() = WalletCore.nextAccountId?.takeIf { it != AccountStore.activeAccountId }
            ?.let(AccountStore::accountById) ?: AccountStore.activeAccount

    private var toolbarAvatarAccountId: String? = null

    private var toolbarAvatarAnimator: ValueAnimator? = null
    private var toolbarAccountChangeFrames = 0

    // Starts after the switch's blocking frame, which would swallow the transition
    private val toolbarAccountChangeFrame = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (--toolbarAccountChangeFrames > 0) {
                Choreographer.getInstance().postFrameCallback(this)
                return
            }
            updateToolbarAvatar()
            updateToolbarAvailability()
        }
    }

    private fun scheduleToolbarAccountChange() {
        if (toolbarAccountChangeFrames == 0) {
            Choreographer.getInstance().postFrameCallback(toolbarAccountChangeFrame)
        }
        toolbarAccountChangeFrames = 2
    }

    // The toolbar and top avatars crossfade alike, both following the wallet being switched to
    private fun updateToolbarAvatar() {
        val account = WalletCore.nextAccountId
            ?.takeIf { WalletCore.nextAccountIsPushedTemporary != true }
            ?.let(AccountStore::accountById) ?: AccountStore.permanentActiveAccount ?: return
        val isNew = toolbarAvatarAccountId != null && toolbarAvatarAccountId != account.accountId
        toolbarAvatarAccountId = account.accountId
        val topOutgoing = visibleTopAvatarIconView ?: topAvatarIconView.also {
            visibleTopAvatarIconView = it
        }
        if (!isNew) {
            toolbarAccountsIconView.config(account)
            topOutgoing.config(account)
            return
        }
        toolbarAvatarAnimator?.cancel()
        val outgoing = toolbarAccountsIconView
        toolbarAccountsIconIndex = 1 - toolbarAccountsIconIndex
        val incoming = toolbarAccountsIconView
        val topIncoming = if (topOutgoing === topAvatarIconView) {
            alternateTopAvatarIconView
        } else {
            topAvatarIconView
        }
        visibleTopAvatarIconView = topIncoming
        incoming.config(account)
        topIncoming.config(account)
        topIncoming.isVisible = true
        val pairs = listOf(outgoing to incoming, topOutgoing to topIncoming)
        val from = pairs.map { (old, new) -> old.alpha to new.alpha }
        fun apply(fraction: Float) {
            pairs.forEachIndexed { index, (old, new) ->
                old.alpha = from[index].first * (1 - fraction)
                new.alpha = from[index].second + (1 - from[index].second) * fraction
                val outScale = 1 - (1 - AVATAR_SWAP_SCALE) * fraction
                val inScale = AVATAR_SWAP_SCALE + (1 - AVATAR_SWAP_SCALE) * fraction
                old.scaleX = outScale
                old.scaleY = outScale
                new.scaleX = inScale
                new.scaleY = inScale
            }
        }
        val isShown = toolbarAccountsButton.isShown || topAvatarView.isShown
        if (!isShown || !WGlobalStorage.getAreAnimationsActive()) {
            apply(1f)
            return
        }
        toolbarAvatarAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener { apply(it.animatedValue as Float) }
            start()
        }
    }

    private val toolbarFadingOut = mutableSetOf<MToolbarItem>()

    private fun isToolbarItemShown(item: MToolbarItem): Boolean =
        toolbarConfiguration.isShown(item) &&
            (!item.isAction || HomeToolbarActions.isAvailable(item, toolbarAccount))

    private fun updateToolbarAvailability() {
        val wasShown = toolbarHideableItems.filter {
            getToolbarView(it).isVisible && it !in toolbarFadingOut
        }
        if (!searchView.isShown || !WGlobalStorage.getAreAnimationsActive()) {
            finishToolbarFade()
            return
        }
        val isShown = toolbarHideableItems.filter(::isToolbarItemShown)
        val hidden = wasShown - isShown.toSet()
        val shown = isShown - wasShown.toSet()
        if (hidden.isEmpty() && shown.isEmpty()) return
        toolbarFadingOut += hidden
        toolbarFadingOut -= shown.toSet()
        shown.forEach { if (!getToolbarView(it).isVisible) toolbarFades[it.ordinal] = 0f }
        showSearchChrome()
        toolbarFadeAnimator?.run {
            removeAllListeners()
            cancel()
        }
        val from = toolbarFades.copyOf()
        toolbarFadeAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener {
                val fraction = it.animatedValue as Float
                for (item in toolbarHideableItems) {
                    val target = if (item in toolbarFadingOut) 0f else 1f
                    toolbarFades[item.ordinal] =
                        from[item.ordinal] + (target - from[item.ordinal]) * fraction
                }
                agentBarMorph.apply()
            }
            doOnEnd { finishToolbarFade() }
            start()
        }
    }

    private fun finishToolbarFade() {
        toolbarFadeAnimator?.run {
            removeAllListeners()
            cancel()
        }
        toolbarFadeAnimator = null
        toolbarFadingOut.clear()
        toolbarFades.fill(1f)
        showSearchChrome()
    }

    private fun getToolbarView(item: MToolbarItem): View = when (item) {
        MToolbarItem.SEARCH -> searchView
        MToolbarItem.ACCOUNTS -> toolbarAccountsButton
        MToolbarItem.SCAN -> toolbarScanButton
        MToolbarItem.ACTIONS -> actionsButton
        else -> toolbarActionItemButtons.getValue(item)
    }

    private fun layoutToolbar(collapse: Float, focus: Float) {
        val width = view.width - 2 * HomeToolbarLayout.margin
        if (width <= 0) return
        toolbarFocus = focus
        var fieldWidth = HomeToolbarLayout.layout(
            toolbarOrder,
            width,
            toolbarConfiguration.isSharedBackground,
            toolbarVisibility,
            toolbarStarts
        )
        val reflow = toolbarReflowProgress
        if (reflow < 1f) {
            for (index in toolbarStarts.indices) {
                toolbarStarts[index] = toolbarReflowStarts[index] +
                    (toolbarStarts[index] - toolbarReflowStarts[index]) * reflow
            }
            fieldWidth = toolbarReflowFieldWidth + (fieldWidth - toolbarReflowFieldWidth) * reflow
        }
        toolbarFieldWidth = fieldWidth
        val direction = if (LocaleController.isRTL) -1 else 1
        for (item in MToolbarItem.entries) {
            if (item == MToolbarItem.SEARCH) continue
            getToolbarView(item).translationX = direction * toolbarStarts[item.ordinal]
        }
        // Collapses into the Agent circle at the leading edge
        val circle = SEARCH_HEIGHT.dp
        val searchWidth = (fieldWidth + (circle - fieldWidth) * collapse).roundToInt()
            .coerceAtLeast(circle)
        if (searchView.layoutParams.width != searchWidth) {
            searchView.updateLayoutParams { this.width = searchWidth }
        }
        searchView.translationX =
            direction * toolbarStarts[MToolbarItem.SEARCH.ordinal] * (1 - collapse)
    }

    private val toolbarOrder: List<MToolbarItem>
        get() = toolbarEditOrder ?: toolbarConfiguration.order

    private fun onToolbarSettingsChanged() {
        // A drop saves settings too; its settle continues
        if (toolbarEditor.isDragging) toolbarEditor.cancel()
        toolbarConfiguration = WGlobalStorage.getToolbarConfiguration()
        updateTopChromeLayout()
        updateTopChromeVisibility(selectedTabId)
        showSearchChrome()
    }

    private var editedToolbarItem: MToolbarItem? = null
    private val editedToolbarView: View?
        get() = editedToolbarItem?.let(::getToolbarView)

    private var landingToolbarItem: MToolbarItem? = null
    private val landingToolbarView: View?
        get() = landingToolbarItem?.let(::getToolbarView)
    private var toolbarLandingAnimator: ValueAnimator? = null
    private var toolbarEditOrder: List<MToolbarItem>? = null
    private var toolbarEditGap = 0f
    private var toolbarFieldWidth = 0f
    private val toolbarReflowStarts = FloatArray(MToolbarItem.entries.size)
    private var toolbarReflowFieldWidth = 0f
    private var toolbarReflowProgress = 1f
    private var toolbarReflowAnimator: ValueAnimator? = null
    private val toolbarShakeAnimators = mutableListOf<ValueAnimator>()
    private val toolbarCandidateStarts = FloatArray(MToolbarItem.entries.size)

    private val toolbarEditor by lazy { HomeToolbarEditor(context, toolbarEditorHost) }

    private var profileDownX = 0f
    private var profileDownY = 0f

    private fun recordProfileDown(view: View, event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            profileDownX = event.rawX
            profileDownY = event.rawY
        }
        return false
    }

    private fun dismissWalletSwitcher() {
        walletSwitcherPopup?.dismiss()
        walletSwitcherPopup = null
    }

    private fun canStartToolbarDrag(): Boolean =
        !searchEditText.hasFocus() && !agentBarMorph.isEngaged && !isTopChromeHidden

    // Not for an accessibility long click
    private fun startToolbarItemDrag(item: MToolbarItem): Boolean {
        val button = getToolbarView(item)
        if (!button.isPressed || !canStartToolbarDrag()) return false
        return toolbarEditor.startToolbarDrag(item, getScreenFrame(button))
    }

    private fun getScreenFrame(view: View): RectF {
        val location = IntArray(2)
        view.getLocationOnScreen(location)
        return RectF(
            location[0].toFloat(),
            location[1].toFloat(),
            location[0] + view.width.toFloat(),
            location[1] + view.height.toFloat()
        )
    }

    private fun layoutToolbarCandidate(order: List<MToolbarItem>, item: MToolbarItem) {
        HomeToolbarLayout.layout(
            order,
            view.width - 2 * HomeToolbarLayout.margin,
            toolbarConfiguration.isSharedBackground,
            { if (it == item) 1f else toolbarVisibility(it) },
            toolbarCandidateStarts
        )
    }

    private fun getToolbarScreenX(start: Float, width: Float): Float {
        val frame = getScreenFrame(view)
        return if (LocaleController.isRTL) {
            frame.right - HomeToolbarLayout.margin - start - width
        } else {
            frame.left + HomeToolbarLayout.margin + start
        }
    }

    private fun getToolbarStart(screenX: Float, width: Float): Float {
        val frame = getScreenFrame(view)
        return if (LocaleController.isRTL) {
            frame.right - HomeToolbarLayout.margin - width - screenX
        } else {
            screenX - frame.left - HomeToolbarLayout.margin
        }
    }

    private fun landToolbarItem(item: MToolbarItem, drop: HomeToolbarEditor.Drop) {
        toolbarLandingAnimator?.cancel()
        val button = getToolbarView(item)
        val size = SEARCH_HEIGHT.dp.toFloat()
        toolbarReflowStarts[item.ordinal] = getToolbarStart(drop.x - size / 2, size)
        val offset = drop.y - getScreenFrame(searchView).centerY()
        fun apply(fraction: Float) {
            val scale = drop.scale + (1 - drop.scale) * fraction
            button.scaleX = scale
            button.scaleY = scale
            button.translationY = searchView.translationY + offset * (1 - fraction)
        }
        if (!WGlobalStorage.getAreAnimationsActive()) return
        landingToolbarItem = item
        apply(0f)
        toolbarLandingAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener { apply(it.animatedValue as Float) }
            doOnEnd {
                apply(1f)
                if (landingToolbarItem == item) landingToolbarItem = null
                agentBarMorph.apply()
            }
            start()
        }
    }

    private fun findToolbarOrder(
        item: MToolbarItem,
        order: List<MToolbarItem>,
        screenX: Float
    ): List<MToolbarItem> {
        val others = order - item
        val button = SEARCH_HEIGHT.dp.toFloat()
        var bestOrder = order
        var bestDistance = Float.MAX_VALUE
        for (index in 0..others.size) {
            val candidate = others.toMutableList().apply { add(index, item) }
            layoutToolbarCandidate(candidate, item)
            val center =
                getToolbarScreenX(toolbarCandidateStarts[item.ordinal], button) + button / 2
            val distance = abs(center - screenX)
            if (distance < bestDistance || (distance == bestDistance && candidate == order)) {
                bestDistance = distance
                bestOrder = candidate
            }
        }
        return bestOrder
    }

    private fun snapshotToolbarReflow() {
        toolbarReflowAnimator?.cancel()
        toolbarReflowAnimator = null
        toolbarStarts.copyInto(toolbarReflowStarts)
        toolbarReflowFieldWidth = toolbarFieldWidth
        toolbarReflowProgress = 0f
    }

    private fun startToolbarReflow() {
        if (!WGlobalStorage.getAreAnimationsActive()) {
            toolbarReflowProgress = 1f
            agentBarMorph.apply()
            return
        }
        toolbarReflowAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener {
                toolbarReflowProgress = it.animatedValue as Float
                agentBarMorph.apply()
            }
            start()
        }
    }

    // Rotating the buttons themselves blanks the glass every frame
    private fun startToolbarShake() {
        stopToolbarShake()
        if (!WGlobalStorage.getAreAnimationsActive()) return
        var phase = 0
        for (item in MToolbarItem.entries) {
            val button = getToolbarView(item) as? ViewGroup ?: continue
            if (item == editedToolbarItem || !button.isVisible) continue
            val angle = TOOLBAR_SHAKE_ANGLE * SEARCH_HEIGHT.dp / button.width.coerceAtLeast(1)
            toolbarShakeAnimators += ValueAnimator.ofFloat(
                0f,
                -angle / 2,
                angle / 2,
                -angle / 2,
                angle / 2,
                0f
            ).apply {
                duration = AnimationConstants.SLOW_ANIMATION
                repeatCount = ValueAnimator.INFINITE
                interpolator = LinearInterpolator()
                addUpdateListener { animator ->
                    val rotation = animator.animatedValue as Float
                    button.children.forEach { it.rotation = rotation }
                }
                start()
                currentPlayTime = duration * phase++ / 3
            }
        }
    }

    private fun stopToolbarShake() {
        toolbarShakeAnimators.forEach { it.cancel() }
        toolbarShakeAnimators.clear()
        for (item in MToolbarItem.entries) {
            (getToolbarView(item) as? ViewGroup)?.children?.forEach { it.rotation = 0f }
        }
    }

    private val toolbarEditorHost = object : HomeToolbarEditor.Host {
        override val window: WWindow?
            get() = this@PhoneTabsVC.window

        override fun getToolbarFrame(): RectF? {
            if (!searchView.isShown) return null
            val frame = getScreenFrame(searchView)
            val row = getScreenFrame(view)
            frame.left = row.left + HomeToolbarLayout.margin
            frame.right = row.right - HomeToolbarLayout.margin
            return frame
        }

        override fun beginToolbarEdit(item: MToolbarItem) {
            clearSearchFocus()
            snapshotToolbarReflow()
            editedToolbarItem = item
            toolbarEditOrder = toolbarConfiguration.order
            toolbarEditGap = if (getToolbarView(item).isVisible) 1f else 0f
            showSearchChrome()
            startToolbarReflow()
            startToolbarShake()
        }

        override fun moveToolbarEdit(screenX: Float?): Boolean {
            val item = editedToolbarItem ?: return false
            val order = toolbarEditOrder ?: return false
            val newOrder = screenX?.let { findToolbarOrder(item, order, it) } ?: order
            val gap = if (screenX == null) 0f else 1f
            if (newOrder == order && gap == toolbarEditGap) return false
            snapshotToolbarReflow()
            toolbarEditOrder = newOrder
            toolbarEditGap = gap
            startToolbarReflow()
            return true
        }

        override fun canToolbarHold(item: MToolbarItem): Boolean =
            HomeToolbarLayout.canHold(toolbarConfiguration, item, view.width)

        override fun endToolbarEdit(
            result: HomeToolbarEditor.Result,
            drop: HomeToolbarEditor.Drop?,
            isAtStart: Boolean
        ) {
            val item = editedToolbarItem ?: return
            val order = toolbarEditOrder ?: toolbarConfiguration.order
            stopToolbarShake()
            val configuration = WGlobalStorage.getToolbarConfiguration()
            val newConfiguration = when (result) {
                HomeToolbarEditor.Result.ADD ->
                    configuration.copy(order = order).withShown(item, true)

                HomeToolbarEditor.Result.REMOVE -> configuration.withShown(item, false)

                HomeToolbarEditor.Result.CANCEL -> configuration

                HomeToolbarEditor.Result.TOP ->
                    configuration.withShown(item, false).copy(isAccountsAtStart = isAtStart)
            }
            snapshotToolbarReflow()
            editedToolbarItem = null
            toolbarEditOrder = null
            if (drop != null && newConfiguration.isShown(item)) landToolbarItem(item, drop)
            if (newConfiguration != configuration) {
                WGlobalStorage.setToolbarConfiguration(newConfiguration)
                toolbarConfiguration = newConfiguration
                WalletCore.notifyEvent(WalletEvent.ToolbarSettingsChanged)
            }
            showSearchChrome()
            startToolbarReflow()
        }

        override fun createToolbarIcon(item: MToolbarItem, scale: Float): View =
            if (item == MToolbarItem.ACCOUNTS) {
                AccountIconView(context, AccountIconView.Usage.ViewItem(14f.dp * scale)).apply {
                    AccountStore.activeAccount?.let { config(it) }
                }
            } else {
                AppCompatImageView(context).apply {
                    setImageResource(getToolbarIconRes(item))
                    setColorFilter(WColor.SecondaryText.color)
                }
            }

        override fun getToolbarIconSize(item: MToolbarItem): Int =
            this@PhoneTabsVC.getToolbarIconSize(item)

        override fun getToolbarButton(item: MToolbarItem): View = getToolbarView(item)

        override fun getTopAvatarFrame(isAtStart: Boolean): RectF? {
            if (!topTabsControl.isShown) return null
            val tabs = getScreenFrame(topTabsControl)
            val row = getScreenFrame(view)
            val systemBars = window?.systemBars
            val leftInset = systemBars?.left ?: 0
            val rightInset = systemBars?.right ?: 0
            val size = TOP_AVATAR_SIZE.dp.toFloat()
            val margin = TOP_AVATAR_END_MARGIN.dp
            val isLeft = isAtStart != LocaleController.isRTL
            val left = if (isLeft) {
                row.left + leftInset + margin
            } else {
                row.right - rightInset - margin - size
            }
            val top = tabs.centerY() - size / 2
            return RectF(left, top, left + size, top + size)
        }

        override fun isTopAvatarAtStart(): Boolean = toolbarConfiguration.isAccountsAtStart

        override fun setTopAvatarHeld(isHeld: Boolean) {
            val scale = if (isHeld) 0f else 1f
            topAvatarView.scaleX = scale
            topAvatarView.scaleY = scale
        }
    }

    private fun updateActionsButtonMorph() {
        val fraction = searchView.focusProgress
        actionsButton.contentDescription = LocaleController.getString(
            if (searchEditText.hasFocus()) "Close" else "More actions"
        )
        actionsButtonIcon.rotation = 45f * fraction
        actionsButtonIcon.setColorFilter(WColor.SecondaryText.color)
        agentBarMorph.apply()
    }

    private fun presentActionsSheet() {
        val window = window ?: return
        val homeVC = navForOrNull(AppTabsManager.ID_HOME)
            ?.viewControllers?.firstOrNull() as? HomeVC ?: return
        clearSearchFocus()
        val nav = WNavigationController(
            window,
            PresentationConfig(
                style = WNavigationController.PresentationStyle.BottomSheet,
                floatingSheetInset = ACTIONS_SHEET_INSET.dp
            )
        )
        nav.setRoot(
            HomeActionsSheetVC(
                context,
                onAction = { identifier -> homeVC.onHeaderAction(identifier) },
                dragHost = toolbarEditor
            )
        )
        window.present(
            nav,
            WWindow.PresentAnimation.ExpandFrom(
                actionsButton,
                cornerRadius = SEARCH_HEIGHT.dp / 2f,
                fillColor = WColor.SearchFieldBackground.color
            )
        )
    }

    // The Agent tab shows the global search only while its own search is open
    private var agentSearchOnClose: (() -> Unit)? = null

    private val isPhoneSearchShown: Boolean
        get() = shouldShowPhoneSearch(selectedTabId) || agentSearchOnClose != null ||
            isAgentBarHosted

    override val isAgentSearchSupported = true

    override fun openAgentSearch(onClose: () -> Unit): Boolean {
        if (selectedTabId != AppTabsManager.ID_AGENT || isTopChromeHidden) return false
        finishAgentSearch()
        agentSearchOnClose = onClose
        updateAgentChrome()
        updateAgentBar()
        searchEditText.requestFocus()
        searchEditText.showKeyboard()
        return true
    }

    private fun finishAgentSearch() {
        val onClose = agentSearchOnClose ?: return
        agentSearchOnClose = null
        updateAgentChrome()
        updateAgentBar()
        onClose()
    }

    private fun showSearchChrome() {
        val shouldShow = isPhoneSearchShown || agentBarMorph.shouldKeepToolbar
        searchView.alpha = 1f
        searchView.isVisible = shouldShow
        actionsButton.alpha = if (editedToolbarItem == MToolbarItem.ACTIONS) 0f else 1f
        actionsButton.isVisible = shouldShow
        for (item in toolbarHideableItems) {
            val button = getToolbarView(item)
            if (item == editedToolbarItem) {
                button.alpha = 0f
                button.isInvisible = true
                continue
            }
            button.alpha = 1f
            button.isVisible = shouldShow && (isToolbarItemShown(item) || item in toolbarFadingOut)
        }
        agentBarMorph.apply()
    }

    // The Agent tab: the page paging has committed to, or will land on, while the finger is up
    private var committedTabId = AppTabsManager.ID_HOME

    // The order the pager draws its pages in, the Agent page last
    private fun orderAgentPageLast(pages: RecyclerView, childCount: Int, i: Int): Int {
        var page: View? = navForOrNull(AppTabsManager.ID_AGENT)
        while (page != null && page.parent !== pages) page = page.parent as? View
        val agentIndex = page?.let(pages::indexOfChild) ?: -1
        return when {
            agentIndex < 0 || i < agentIndex -> i
            i == childCount - 1 -> agentIndex
            else -> i + 1
        }
    }

    /** Holds the Agent list's bar where the toolbar is while the Agent page slides under it */
    private fun keepAgentBarOnToolbar() {
        val list = findAgentList() ?: return
        val page = navForOrNull(AppTabsManager.ID_AGENT) ?: return
        if (!page.isAttachedToWindow) return
        page.clipChildren = false
        val pageLocation = IntArray(2).also(page::getLocationInWindow)
        val pagerLocation = IntArray(2).also(tabPager::getLocationInWindow)
        list.setHostedBarShift((pagerLocation[0] - pageLocation[0]).toFloat())
    }

    // A tapped tab commits at once, and the pages its slide passes over don't
    private var springingTabId: Int? = null

    private fun commitPage(index: Int) {
        val tabId = topTabIds.getOrNull(index) ?: return
        springingTabId?.let { if (tabId != it) return }
        if (committedTabId == tabId) return
        committedTabId = tabId
        updateAgentBar()
    }

    private fun findAgentList(): AgentThreadListVC? =
        navForOrNull(AppTabsManager.ID_AGENT)?.viewControllers?.firstOrNull() as? AgentThreadListVC

    // The Agent list's bar grows out of the toolbar while the list is the tab's root screen on top and shows its
    // bar; without one (the consent screen) the tab has no toolbar
    private val isAgentBarHosted: Boolean
        get() = selectedTabId == AppTabsManager.ID_AGENT && agentSearchOnClose == null &&
            (navForOrNull(AppTabsManager.ID_AGENT)?.viewControllers?.size ?: 1) <= 1 &&
            findAgentList()?.isBarShown == true

    // The search circle's magnifier, where the field draws its own
    private val agentCircleIcon by lazy {
        AppCompatImageView(context).apply {
            setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_search_24)
            setColorFilter(WColor.SecondaryText.color)
            alpha = 0f
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
    }

    private val agentCircleButton by lazy {
        WFrameLayout(context).apply {
            id = View.generateViewId()
            isClickable = true
            isFocusable = true
            contentDescription = LocaleController.getString("Search")
            visibility = View.INVISIBLE
            setOnClickListener { findAgentList()?.openSearchFromBar() }
        }
    }

    private val agentBarMorphDelegate = lazy {
        AgentRootBarMorph(
            searchView = searchView,
            actionsButton = actionsButton,
            actionsIcon = actionsButtonIcon,
            toolbarButtons = toolbarActionButtons,
            isHeld = { it === editedToolbarView || it === landingToolbarView },
            getButtonFade = { toolbarFades[toolbarHideableItems[it].ordinal] },
            circleButton = agentCircleButton,
            layoutToolbar = ::layoutToolbar,
            onProgress = { progress ->
                agentBarProgress = progress.coerceIn(0f, 1f)
                applyStickyGradientAlpha()
                findAgentList()?.setHostedBarProgress(progress)
            },
            applyTextAlpha = { alpha ->
                // The field's text and magnifier fade; the circle's own magnifier takes the place of its,
                // growing from its size to the design's
                if (searchEditText.alpha != alpha) searchEditText.alpha = alpha
                agentCircleIcon.alpha = 1 - alpha
                val iconScale = FIELD_ICON_SCALE + (1 - FIELD_ICON_SCALE) * (1 - alpha)
                agentCircleIcon.scaleX = iconScale
                agentCircleIcon.scaleY = iconScale
            },
            onSettled = { showSearchChrome() }
        )
    }
    private val agentBarMorph by agentBarMorphDelegate

    // The Agent list keeps its own fade under its bar, in its own colour: the toolbar's gives way as the bar grows
    private var agentBarProgress = 0f

    private fun applyStickyGradientAlpha() {
        stickyBottomGradientView?.alpha = 1 - agentBarProgress
    }

    // The toolbar the Agent list's bar grows out of
    private val agentBarHost = object : AgentListBarHost {
        // The bar keeps the line of the shown toolbar while a chat covers it and the toolbar has gone
        override val agentBarBottomInset: Int
            get() = (searchTopOffset(shownToolbarExtraGap) - SEARCH_HEIGHT.dp).roundToInt()

        override fun onAgentBarStateChanged() = updateAgentBar()
    }

    private fun updateAgentBar(isInstant: Boolean = false) {
        if (isAgentBarReleased) return
        val list = findAgentList()
        list?.barHost = agentBarHost
        val agentDepth = navForOrNull(AppTabsManager.ID_AGENT)?.viewControllers?.size ?: 1
        val isAgent = committedTabId == AppTabsManager.ID_AGENT && agentSearchOnClose == null &&
            list != null
        val isUnderChat = list?.isBarCovered ?: (agentDepth > 1)
        // A list without its bar sends the circle away as a chat over it does
        val isCovered = isUnderChat || list?.isBarShown != true
        // A tab opened onto a chat finds the toolbar already away
        val shouldJump = isInstant || (selectedTabId != AppTabsManager.ID_AGENT && isUnderChat)
        agentBarMorph.setTargets(
            isAgent = isAgent,
            isCovered = isCovered,
            isComposing = list?.isComposing == true,
            isSearchAway = list?.isSearchAway == true,
            isAnimated = !shouldJump
        )
        // Whether the toolbar shows decides its line
        updateSearchPosition()
        showSearchChrome()
        if (selectedTabId == AppTabsManager.ID_AGENT) {
            updateTopChromeVisibility(selectedTabId)
            // Paging waits while a question is written
            tabPager.isUserInputEnabled = directTabTransition == null &&
                !isTopChromeHidden && list?.isComposing != true &&
                shouldShowPhoneTopTabs(AppTabsManager.ID_AGENT, agentDepth)
        }
    }

    private fun updateAgentChrome() {
        tabPager.isUserInputEnabled = directTabTransition == null &&
            !isTopChromeHidden && shouldShowPhoneTopTabs(
                selectedTabId,
                activeNavigationController?.viewControllers?.size ?: 1
            )
        updateTopChromeVisibility(selectedTabId)
        showSearchChrome()
        updateStickyBottomGradient()
        activeNavigationController?.insetsUpdated()
    }

    override fun navStackUpdated(nav: WNavigationController) {
        if (nav === navForOrNull(AppTabsManager.ID_AGENT) && nav.viewControllers.size > 1) {
            findAgentList()?.setBarCovered(true)
        }
        if (nav === activeNavigationController) updateAgentChrome()
        updateAgentBar()
    }

    private var stickyBottomGradientView: View? = null
    private var stickyBottomGradientDrawable: StickyBottomGradientDrawable? = null

    private val keyboardVisible = FloatAnimator(220L, AnimatorUtils.DECELERATE_INTERPOLATOR, 0f) {
        render()
    }

    private fun render() {
        syncToastHostPosition()
        syncUpdateButtonPosition()
        updateSearchPosition()
        updateStickyGradientHeight()
        onUpdateAdditionalHeight()
    }

    private fun updateSearchPosition() {
        // The toolbar keeps the line it has while shown, also as the Agent list's bar, whatever covers the list
        searchView.translationY = -(searchTopOffset(shownToolbarExtraGap) - SEARCH_HEIGHT.dp)
        actionsButton.translationY = searchView.translationY
        toolbarActionButtons.forEach { it.translationY = searchView.translationY }
        agentCircleButton.translationY = searchView.translationY
        if (agentBarCoverView.parent != null) {
            // From the circle's halo, swollen mid-morph, down to the screen's bottom edge
            val haloMargin = 2 * WGlassView.GLASS_PADDING_DP.dp
            val height = (searchTopOffset(shownToolbarExtraGap) + haloMargin).roundToInt()
            if (agentBarCoverView.layoutParams.height != height) {
                agentBarCoverView.updateLayoutParams { this.height = height }
            }
        }
    }

    private fun onUpdateAdditionalHeight() {
        activeNavigationController?.insetsUpdated()
        // The search overlay reserves the same bottom height, so it has to follow the keyboard too.
        searchOverlayNav?.insetsUpdated()
    }

    override fun setupViews() {
        super.setupViews()

        setTopBlur(visible = false, animated = false)

        view.alpha = 0f
        view.doOnLayout { view.fadeIn() }

        WalletCore.registerObserver(this)

        view.addView(contentView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(toastHostView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(searchView, ConstraintLayout.LayoutParams(SEARCH_HEIGHT.dp, SEARCH_HEIGHT.dp))
        searchView.addView(
            agentCircleIcon,
            FrameLayout.LayoutParams(
                CIRCLE_ICON_SIZE.dp,
                CIRCLE_ICON_SIZE.dp,
                Gravity.START or Gravity.CENTER_VERTICAL
            ).apply { marginStart = CIRCLE_ICON_START.dp }
        )
        searchGlass = WGlassView.attachTo(
            searchView,
            24f.dp,
            GlassProviders.pill(WColor.SearchFieldBackground),
            root = contentView
        )
        for (background in toolbarBackgroundsSync.views) {
            background.id = View.generateViewId()
            background.visibility = View.GONE
            view.addView(
                background,
                ConstraintLayout.LayoutParams(SEARCH_HEIGHT.dp, SEARCH_HEIGHT.dp)
            )
            toolbarBackgroundGlasses += WGlassView.attachTo(
                background,
                SEARCH_HEIGHT.dp / 2f,
                GlassProviders.pill(WColor.SearchFieldBackground),
                root = contentView
            )
        }
        for (item in toolbarButtonItems) {
            view.addView(
                getToolbarView(item),
                ConstraintLayout.LayoutParams(SEARCH_HEIGHT.dp, SEARCH_HEIGHT.dp)
            )
        }
        view.viewTreeObserver.addOnPreDrawListener(toolbarBackgroundsListener)
        view.addView(
            agentCircleButton,
            ConstraintLayout.LayoutParams(SEARCH_HEIGHT.dp, SEARCH_HEIGHT.dp)
        )
        ensureStickyBottomGradientView()
        view.addView(
            topAvatarView,
            ConstraintLayout.LayoutParams(TOP_AVATAR_SIZE.dp, TOP_AVATAR_SIZE.dp)
        )
        topAvatarGlass = WGlassView.attachTo(
            topAvatarView,
            TOP_AVATAR_SIZE.dp / 2f,
            GlassProviders.pill(WColor.Background),
            contentView
        )
        view.addView(
            topTabsControl,
            ConstraintLayout.LayoutParams(0, TOP_TABS_HEIGHT.dp)
        )
        topTabsGlass = WGlassView.attachTo(
            topTabsControl,
            TOP_TABS_HEIGHT.dp / 2f,
            GlassProviders.pill(WColor.Background),
            contentView
        )
        view.addView(agentCoverView, ConstraintLayout.LayoutParams(0, 0))
        view.addView(agentBarCoverView, ConstraintLayout.LayoutParams(0, 0))
        HomeStatusController.addListener(topAvatarStatusListener)
        view.setConstraints {
            val searchHorizontalMargin =
                (ViewConstants.HORIZONTAL_PADDINGS + 6).toFloat()
            for (item in MToolbarItem.entries) {
                toStart(getToolbarView(item), searchHorizontalMargin)
                toBottom(getToolbarView(item))
            }
            // Synced in absolute x, so anchored left
            for (background in toolbarBackgroundsSync.views) {
                toLeft(background)
                toBottom(background)
            }
            toStart(agentCircleButton, searchHorizontalMargin)
            toBottom(agentCircleButton)
            toCenterX(toastHostView)
            toBottom(toastHostView)
            toTop(agentCoverView)
            toStart(agentCoverView)
            toEnd(agentCoverView)
            toBottom(agentBarCoverView)
            toStart(agentBarCoverView)
            toEnd(agentBarCoverView)
            stickyBottomGradientView?.let {
                toBottom(it)
            }
        }
        updateTopChromeLayout()
        view.addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
            if (right - left != oldRight - oldLeft) view.post { agentBarMorph.apply() }
        }

        // The app opens on the first tab in the user's order, unless it takes over the tab another
        // container showed
        val initialTab = pendingSelectedTab ?: firstTabId
        pendingSelectedTab = null
        reloadTopTabs(initialTab)
        contentView.addView(
            tabPager,
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        if (initialTab != selectedTabId) selectTab(initialTab)
        updateTopAvatar()
        showSearchChrome()
        adoptPendingSearchText()
        view.post {
            activeNavigationController?.insetsUpdated()
            // preload other tabs
            if (AppTabsManager.contains(AppTabsManager.ID_EXPLORE)) {
                getNavigationStack(AppTabsManager.ID_EXPLORE)
            }
        }

        updateToastAvailability()
        checkForUpdate()
        updateTheme()
        precacheReceiveBackground()
        pagePreloader = createPagePreloader().also { it.start() }
    }

    private fun presentTabMenu(anchorView: View): Boolean {
        if (tabMenuPopup != null || isDisappeared || isTopChromeHidden ||
            !anchorView.isShown || !anchorView.isEnabled
        ) {
            return false
        }
        val popupHost = PopupHelpers.popupHost ?: return false
        finishDirectTabTransition()
        val tabs = topTabIds.mapNotNull { tabId ->
            AppTabsManager.registeredTabs.firstOrNull { it.intId == tabId }
        }
        if (tabs.isEmpty()) return false
        val items = tabs.map(::createTabMenuItem)
        val menuOrder = tabs.map { it.id }.toMutableList()
        val menuWidth = WMenuPopupView.measureWidth(context, items)
            .coerceAtMost(popupHost.getContentAreaBounds().width())

        var presentedPopup: INavigationPopup? = null
        presentedPopup = WMenuPopup.present(
            view = anchorView,
            items = items,
            popupWidth = menuWidth,
            positioning = WMenuPopup.Positioning.ALIGNED,
            backdropStyle = WMenuPopup.BackdropStyle.BlurDimmed,
            placement = { width, _ ->
                val bounds = popupHost.getContentAreaBounds()
                vec2i(
                    ((popupHost.width - width) / 2).coerceIn(bounds.left, bounds.right - width),
                    anchorView.getLocationInWindow().y
                )
            },
            shouldMorphFromSource = true,
            onDidDismiss = {
                if (tabMenuPopup === presentedPopup) tabMenuPopup = null
            },
            isSlideSelectionEnabled = true,
            onReorder = { fromPosition, toPosition ->
                menuOrder.add(toPosition, menuOrder.removeAt(fromPosition))
                isApplyingTabMenuOrder = true
                try {
                    AppTabsManager.reorderTabs(menuOrder)
                } finally {
                    isApplyingTabMenuOrder = false
                }
            }
        )
        tabMenuPopup = presentedPopup
        return true
    }

    private fun createTabMenuItem(tab: AppTabsManager.AppTab): WMenuPopup.Item {
        val (iconResId, subtitleKey) = when (tab.intId) {
            AppTabsManager.ID_HOME ->
                IconsR.drawable.ic_tab_menu_wallet to "View your assets and activity"

            AppTabsManager.ID_MARKET ->
                IconsR.drawable.ic_tab_menu_market to "\$perps_explore_market"

            AppTabsManager.ID_FUTURES ->
                IconsR.drawable.ic_tab_menu_futures to "\$perps_explore_futures"

            AppTabsManager.ID_AGENT ->
                IconsR.drawable.ic_tab_menu_agent to "Ask AI and follow the news"

            AppTabsManager.ID_EXPLORE ->
                IconsR.drawable.ic_tab_menu_explore to "\$perps_explore_apps"

            AppTabsManager.ID_PORTFOLIO ->
                IconsR.drawable.ic_tab_menu_portfolio to "\$agent_hint_portfolio_title"

            else -> tab.filledIconRes to null
        }
        val animationResId = when (tab.intId) {
            AppTabsManager.ID_HOME -> IconsR.raw.tab_menu_wallet
            AppTabsManager.ID_MARKET -> IconsR.raw.tab_menu_market
            AppTabsManager.ID_FUTURES -> IconsR.raw.tab_menu_futures
            AppTabsManager.ID_AGENT -> IconsR.raw.tab_menu_agent
            AppTabsManager.ID_EXPLORE -> IconsR.raw.tab_menu_explore
            else -> null
        }
        return WMenuPopup.Item(
            config = WMenuPopup.Item.Config.Item(
                icon = WMenuPopup.Item.Config.Icon(
                    iconResId = iconResId,
                    tintColor = WColor.PrimaryText,
                    iconSize = 34.dp,
                    animationResId = animationResId
                ),
                title = LocaleController.getString(tab.labelKey),
                subtitle = subtitleKey?.let(LocaleController::getString),
                rowStyle = WMenuPopup.RowStyle.WALLET
            ),
            onTap = {
                if (!isDisappeared && tab.intId in topTabIds &&
                    AppTabsManager.contains(tab.intId)
                ) {
                    selectTab(tab.intId)
                }
            }
        )
    }

    private fun dismissTabMenu() {
        val popup = tabMenuPopup ?: return
        tabMenuPopup = null
        popup.dismiss()
    }

    private var walletSwitcherPopup: IPopup? = null

    private fun presentWalletSwitcherPopup(
        anchorView: View,
        positioning: WMenuPopup.Positioning = WMenuPopup.Positioning.BELOW
    ): Boolean {
        val accounts = WalletCore.getAllAccounts()
        val manageWalletsItem = WMenuPopup.Item(
            config = WMenuPopup.Item.Config.Item(
                icon = WMenuPopup.Item.Config.Icon(
                    iconResId = org.mytonwallet.app_air.icons.R.drawable.ic_manage_30,
                    tintColor = WColor.SubtitleText,
                    iconSize = 28.dp,
                    iconMargin = 17.dp
                ),
                title = LocaleController.getString("Manage Wallets")
            ),
            hasSeparator = true,
            onTap = {
                val window = window ?: return@Item
                val navVC = WNavigationController(
                    window,
                    PresentationConfig(
                        style = WNavigationController.PresentationStyle.BottomSheet
                    )
                )
                val walletsTabsVC = WalletContextManager.delegate?.get()?.getWalletsTabsVC(
                    MWalletSettingsViewMode.LIST
                ) as? WViewController ?: return@Item
                navVC.setRoot(walletsTabsVC)
                window.present(navVC)
            }
        ).apply { testViewId = UIComponentsR.id.wallet_switcher_manage }
        val addAccountItem = WMenuPopup.Item(
            config = WMenuPopup.Item.Config.Item(
                icon = WMenuPopup.Item.Config.Icon(
                    iconResId = org.mytonwallet.app_air.icons.R.drawable.ic_add,
                    tintColor = WColor.SubtitleText,
                    iconSize = 28.dp,
                    iconMargin = 17.dp
                ),
                title = LocaleController.getString("Add Wallet")
            ),
            hasSeparator = false,
            onTap = {
                val window = window ?: return@Item
                val nav = WNavigationController(
                    window,
                    PresentationConfig(
                        style = WNavigationController.PresentationStyle.BottomSheet,
                        aboveKeyboard = true
                    )
                )
                val addAccountVC = WalletContextManager.delegate?.get()
                    ?.getAddAccountVC(MBlockchainNetwork.MAINNET) as? WViewController
                    ?: return@Item
                nav.setRoot(addAccountVC)
                window.present(nav)
            }
        ).apply { testViewId = UIComponentsR.id.wallet_switcher_add }
        val systemBars = navigationController?.getSystemBars()
        val freeSpaceToShowAccounts = if (positioning == WMenuPopup.Positioning.ABOVE) {
            (anchorView.top + anchorView.translationY).roundToInt() - (systemBars?.top ?: 0)
        } else {
            view.height - anchorView.bottom - (systemBars?.bottom ?: 0)
        } - 110.dp

        if (freeSpaceToShowAccounts < 0) return false

        val numberOfAccountsCapacity = freeSpaceToShowAccounts / 56.dp

        val numberOfAccountsToShow =
            accounts.size.coerceAtMost(numberOfAccountsCapacity.coerceAtMost(10))

        lateinit var popup: IPopup
        val menuItems =
            listOf(manageWalletsItem) +
                accounts.take(numberOfAccountsToShow).mapIndexed { i, account ->
                    val hasSeparator = i == numberOfAccountsToShow - 1
                    WMenuPopup.Item(
                        config = WMenuPopup.Item.Config.CustomView(
                            AccountItemView(
                                context = context,
                                accountData = AccountItemView.AccountData(
                                    accountId = account.accountId,
                                    title = account.name,
                                    network = account.network,
                                    byChain = account.byChain,
                                    accountType = account.accountType
                                ),
                                showArrow = false,
                                isTrusted = true,
                                hasSeparator = hasSeparator,
                                showBalance = true,
                                onSelect = {
                                    popup.dismiss()
                                    val isActive =
                                        account.accountId == AccountStore.activeAccountId
                                    if (isActive) return@AccountItemView
                                    WalletCore.activateAccount(
                                        account.accountId,
                                        notifySDK = true
                                    ) { res, _ ->
                                        if (res != null) {
                                            WalletCore.notifyEvent(
                                                WalletEvent.AccountChangedInApp(
                                                    persistedAccountsModified = false
                                                )
                                            )
                                        }
                                    }
                                }
                            )
                        ),
                        hasSeparator = hasSeparator
                    ).apply { testViewId = UIComponentsR.id.wallet_switcher_account }
                } +
                listOf(addAccountItem)

        popup = WMenuPopup.present(
            view = anchorView,
            items = menuItems,
            yOffset = (if (positioning == WMenuPopup.Positioning.ABOVE) 3 else -3).dp,
            positioning = positioning,
            backdropStyle = WMenuPopup.BackdropStyle.BlurDimmed,
            centerHorizontally = true,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                anchorView,
                roundRadius = 100f.dp,
                horizontalOffset = 0,
                verticalOffset = 0
            )

        )
        walletSwitcherPopup = popup
        return true
    }

    override fun notifyThemeChanged() {
        super.notifyThemeChanged()
        if (isDisappeared) {
            navStacks.forEach {
                it.viewControllers.lastOrNull()?.pendingThemeChange = true
            }
            return
        }
        navStacks.forEach { nav ->
            if (nav === activeNavigationController) return@forEach
            nav.updateTheme()
            nav.viewControllers.lastOrNull()?.applyThemeChanges()
        }
    }

    override val isTinted = true
    override fun updateTheme() {
        finishDirectTabTransition()
        dismissTabMenu()
        super.updateTheme()

        val tintColor = WColor.Tint.color

        updateActionsButtonMorph()

        for (navView in navStacks) {
            if (navView.parent != null) {
                navView.refreshRootTopOverlay()
                continue
            }
            navView.updateTheme()
        }

        updateFloatingButtonBackground?.apply {
            backgroundColor = tintColor
        }
        topTabsControl.setBackgroundColor(
            Color.TRANSPARENT,
            TOP_TABS_HEIGHT.dp / 2f,
            clipToBounds = true
        )
        topTabsGlass?.updateTheme()
        topAvatarGlass?.updateTheme()
        toolbarBackgroundGlasses.forEach { it.updateTheme() }
        actionsButtonRipple.rippleColor = WColor.BackgroundRipple.color
        toolbarAccountsRipple.rippleColor = WColor.BackgroundRipple.color
        toolbarAccountsIconViews.forEach { it.updateTheme() }
        toolbarAccountsRingDrawable.color = WColor.Tint.color
        toolbarAccountsRingView.invalidate()
        toolbarScanRipple.rippleColor = WColor.BackgroundRipple.color
        toolbarScanIcon.setColorFilter(WColor.SecondaryText.color)
        toolbarActionIcons.forEach { it.setColorFilter(WColor.SecondaryText.color) }
        toolbarActionItemButtons.values.forEach {
            (it.foreground as? WRippleDrawable)?.rippleColor = WColor.BackgroundRipple.color
        }
        agentCircleIcon.setColorFilter(WColor.SecondaryText.color)
        agentBarMorph.apply()
        topTabsControl.paintColor = WColor.Tint.color.colorWithAlpha(31)
        topTabsControl.primaryTextColorOverride = WColor.Tint.color
        topTabsControl.updateTheme()
        topTabsControl.secondaryTextColor = WColor.SecondaryText.color
        topTabsControl.invalidate()
        topAvatarRipple.backgroundColor = Color.TRANSPARENT
        topAvatarRipple.rippleColor = WColor.BackgroundRipple.color
        topAvatarIconView.updateTheme()
        alternateTopAvatarIconView.updateTheme()
        topAvatarRingDrawable.color = WColor.Tint.color
        topAvatarRingView.invalidate()
        updateStickyBottomGradient()
        updateSearchPosition()

        searchView.updateTheme()

        render()
    }

    override fun viewWillAppear() {
        if (isDisappeared && !isKeyboardOpen) {
            keyboardVisible.forcedValue = 0f
        }
        super.viewWillAppear()
        activeNavigationController?.viewWillAppear()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        activeNavigationController?.viewDidAppear()
        hasSelectedPageAppeared = true
        pagePreloader?.schedule()
        updateToastAvailability()
        // Re-host any full-screen VCs carried over from the tablet container, now that this VC is the
        // root of the window nav (which is the phone's main navigation controller).
        val tabToPresentOverMain = pendingTabToPresentOverMain
        if (tabToPresentOverMain != null) {
            pendingTabToPresentOverMain = null
            val stack = detachNavigationStack(tabToPresentOverMain).ifEmpty {
                listOf(
                    SettingsVC(context)
                )
            }
            adoptPushedOverMain(stack + takePendingPushedOverMain())
        } else {
            adoptPendingPushedOverMain()
        }
    }

    override fun selectedTabForExport(selectedItemId: Int): Int {
        val pushedRoot = navigationController?.viewControllers?.getOrNull(1)
        return when (pushedRoot) {
            is SettingsVC -> AppTabsManager.ID_SETTINGS
            else -> selectedItemId
        }
    }

    // Full-screen pushes on phone live in the window nav, above this PhoneTabsVC root.
    override fun exportPushedOverMain(): List<WViewController> {
        val pushed = navigationController?.detachAboveRoot() ?: return emptyList()
        val tabId = when (pushed.firstOrNull()) {
            is SettingsVC -> AppTabsManager.ID_SETTINGS
            else -> null
        }
        if (tabId != null) {
            replaceNavigationStack(tabId, pushed)
            return emptyList()
        }
        return pushed
    }

    override fun adoptPushedOverMain(pushed: List<WViewController>) {
        navigationController?.adoptAboveRoot(pushed)
    }

    override fun viewDidEnterForeground() {
        super.viewDidEnterForeground()
        updateToastAvailability()
        pagePreloader?.resume()
    }

    override fun viewWillDisappear() {
        finishDirectTabTransition()
        dismissTabMenu()
        super.viewWillDisappear()
        activeNavigationController?.viewWillDisappear()
        toastHostView.setToastEnabled(false)
        searchView.clearAutoComplete()
    }

    override fun updateProtectedView() {
        for (navView in navStacks) {
            fun updateProtectedViewForChildren(parentView: ViewGroup) {
                for (child in parentView.children) {
                    if (child is WProtectedView) child.updateProtectedView()
                    if (child is ViewGroup) updateProtectedViewForChildren(child)
                }
            }
            updateProtectedViewForChildren(navView)
        }
    }

    private val keyboardHeight: Float
        get() {
            val height = (window?.imeInsets?.bottom ?: 0) -
                (window?.systemBars?.bottom ?: 0) -
                (if (window?.hasMinimizedBrowser == true) 56.dp else 0)
            if (height <= 0) return 0f
            return (height + searchKeyboardLift).toFloat()
        }

    private val searchKeyboardLift: Int
        get() = (SEARCH_KEYBOARD_GAP.dp - 1.dp - bottomOverlayExtraGap).coerceAtLeast(0)

    override fun insetsUpdated() {
        super.insetsUpdated()

        keyboardVisible.animatedValue = keyboardHeight
        onUpdateAdditionalHeight()
        render()
        updateTopChromeLayout()

        if (!isKeyboardOpen &&
            searchEditText.hasFocus() &&
            cachedExploreVC?.shouldKeepSearchActiveOnKeyboardDismiss != true
        ) {
            searchEditText.clearFocus()
        }
        updateStickyGradientHeight()
    }

    private val shouldShowStickyBottomGradientView: Boolean
        get() = WGlobalStorage.isGradientNavigationBarActive() && isPhoneSearchShown

    // The toolbar keeps its line on every tab, the Agent tab's bar included
    private val bottomOverlayExtraGap: Int
        get() = if (WGlobalStorage.isGradientNavigationBarActive() && isPhoneSearchShown) {
            0
        } else {
            BOTTOM_EXTRA_GAP.dp
        }

    private val shownToolbarExtraGap: Int
        get() = if (WGlobalStorage.isGradientNavigationBarActive()) 0 else BOTTOM_EXTRA_GAP.dp

    private fun ensureStickyBottomGradientView(): View {
        stickyBottomGradientView?.let { return it }
        val gradientView = View(context).apply {
            id = View.generateViewId()
        }
        stickyBottomGradientView = gradientView
        gradientView.alpha = 1 - agentBarProgress
        view.addView(
            gradientView,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                stickyGradientFullHeight()
            )
        )
        restackChromeAboveGradient()
        return gradientView
    }

    private fun restackChromeAboveGradient() {
        if (topTabsControl.parent != null) {
            topAvatarGlass?.bringToFront()
            topAvatarView.bringToFront()
            topTabsGlass?.bringToFront()
            topTabsControl.bringToFront()
            agentCoverView.bringToFront()
        }
        searchOverlayNav?.bringToFront()
        bottomReversedCornerView?.bringToFront()
        stickyBottomGradientView?.bringToFront()
        searchGlass?.bringToFront()
        searchView.bringToFront()
        toolbarBackgroundsSync.views.forEachIndexed { index, background ->
            toolbarBackgroundGlasses.getOrNull(index)?.bringToFront()
            background.bringToFront()
        }
        for (item in toolbarButtonItems) getToolbarView(item).bringToFront()
        agentCircleButton.bringToFront()
        if (agentBarCoverView.parent != null) agentBarCoverView.bringToFront()
        toastHostView.bringToFront()
    }

    private fun stickyGradientFullHeight(): Int = bottomBarHeight +
        (window?.minimizedBrowserHeight ?: 0f).roundToInt() +
        (SEARCH_BOTTOM_MARGIN + SEARCH_HEIGHT).dp +
        stickyGradientKeyboardHeight.roundToInt()

    // The gradient follows the search bar above the keyboard.
    private val stickyGradientKeyboardHeight: Float
        get() = keyboardVisible.value.coerceAtLeast(0f)

    private fun updateStickyGradientHeight() {
        val gradient = stickyBottomGradientView ?: return
        val target = stickyGradientFullHeight()
        val params = gradient.layoutParams ?: return
        if (params.height != target) {
            params.height = target
            gradient.layoutParams = params
        }
        stickyBottomGradientDrawable?.setStops(computeGradientStops())
    }

    // The fade spans the whole chrome above the bottom inset and turns solid at its top.
    private fun computeGradientStops(): FloatArray {
        val full = stickyGradientFullHeight()
        if (full <= 0) return floatArrayOf(0f, 1f, 1f)
        val solidHeight = (window?.systemBars?.bottom ?: 0) + stickyGradientKeyboardHeight
        val insetRatio = (solidHeight / full).coerceIn(0f, 1f)
        return floatArrayOf(0f, 1f - insetRatio, 1f)
    }

    private fun updateStickyBottomGradient() {
        if (shouldShowStickyBottomGradientView) {
            if (stickyBottomGradientView == null) {
                val gradientView = ensureStickyBottomGradientView()
                view.setConstraints {
                    toBottom(gradientView)
                }
            }
            // The page colour of every tab; on the Agent list it has faded for the list's own
            stickyBackgroundColor = WColor.SecondaryBackground.color
            val drawable = StickyBottomGradientDrawable(
                intArrayOf(
                    stickyBackgroundColor.colorWithAlpha(0),
                    stickyBackgroundColor.colorWithAlpha(GRADIENT_ALPHA),
                    stickyBackgroundColor.colorWithAlpha(GRADIENT_ALPHA)
                )
            )
            drawable.setStops(computeGradientStops())
            stickyBottomGradientDrawable = drawable
            stickyBottomGradientView?.background = drawable
        } else {
            if (stickyBottomGradientView?.parent != null) {
                view.removeView(stickyBottomGradientView)
                stickyBottomGradientView = null
            }
        }
    }

    override fun switchToExplore(targetUri: Uri?) {
        navigationController?.popToRoot(false)
        if (!AppTabsManager.contains(AppTabsManager.ID_EXPLORE)) {
            window?.dismissToRoot()
            val exploreVC = ExploreVC(context)
            navigationController?.push(exploreVC)
            targetUri?.let { exploreVC.findSiteAndOpenTargetUri(it) }
            return
        }
        selectTab(AppTabsManager.ID_EXPLORE)
        window?.dismissToRoot()
        targetUri?.let { cachedExploreVC?.findSiteAndOpenTargetUri(it) }
    }

    override fun switchToMarket() {
        navigationController?.popToRoot(false)
        if (!AppTabsManager.contains(AppTabsManager.ID_MARKET)) {
            // Market is an optional tab the user may have hidden, and a deeplink must still land
            // on the screen, so push it onto the current stack instead of selecting a missing tab.
            window?.dismissToRoot()
            navigationController?.push(MarketVC(context))
            return
        }
        selectTab(AppTabsManager.ID_MARKET)
        window?.dismissToRoot()
    }

    override fun switchToFutures() {
        if (!PerpsAvailability.isAvailable()) return
        navigationController?.popToRoot(false)
        if (!AppTabsManager.contains(AppTabsManager.ID_FUTURES)) {
            window?.dismissToRoot()
            navigationController?.push(FuturesVC(context))
            return
        }
        selectTab(AppTabsManager.ID_FUTURES)
        window?.dismissToRoot()
    }

    override fun switchToAgent(
        prompt: String?,
        entryPoint: AgentV2EntryPoint,
        thread: AgentV2ThreadSummary?
    ): Boolean {
        if (!AppTabsManager.contains(AppTabsManager.ID_AGENT)) return false
        navigationController?.popToRoot(false)
        if (selectedTabId != AppTabsManager.ID_AGENT) selectTab(AppTabsManager.ID_AGENT)
        window?.dismissToRoot()
        openAgentChat(prompt, entryPoint, thread)
        return true
    }

    override fun switchToSettings(pushVC: WViewController?) {
        navigationController?.popToRoot(false)
        window?.dismissToRoot()
        navigationController?.push(SettingsVC(context), animated = pushVC == null)
        pushVC?.let { navigationController?.push(it) }
    }

    override val isOnHomeScreen: Boolean
        get() {
            val homeNavigationController =
                navForOrNull(AppTabsManager.ID_HOME) ?: return false
            return selectedTabId == AppTabsManager.ID_HOME &&
                window?.topViewController == this &&
                homeNavigationController.viewControllers.size == 1
        }
    override val mainNavigationController: WNavigationController?
        get() = navigationController

    override val activeNavigationController: WNavigationController?
        get() {
            return navForOrNull(selectedTabId)
        }

    private fun createUpdateButtonIfNeeded() {
        if (updateFloatingButton == null) {
            val button = WLabel(context).apply {
                setStyle(adaptiveFontSize(), WFont.Medium)
                text = LocaleController.getStringWithKeyValues(
                    "Update %app_name%",
                    listOf(
                        Pair("%app_name%", context.getString(BaseR.string.app_locale_name_key))
                    )
                )
                gravity = Gravity.CENTER
                updateFloatingButtonBackground = WRippleDrawable.create(24f.dp).apply {
                    backgroundColor = WColor.Tint.color
                    rippleColor = WColor.BackgroundRipple.color
                }
                background = updateFloatingButtonBackground
                setTextColor(WColor.White)
                setPadding(20.dp, 0, 20.dp, 0)
                elevation = 6f.dp
                alpha = 0f
                setOnClickListener {
                    val url = if (EnvironmentStore.isAndroidDirect) {
                        EnvironmentStore.appVersion?.let { v ->
                            val template =
                                context.getString(BaseR.string.app_direct_apk_version_url_template)
                            if (template.isNotEmpty()) template.format(v) else ""
                        } ?: context.getString(BaseR.string.app_direct_apk_release_url)
                    } else {
                        context.getString(BaseR.string.app_install_url)
                    }
                    if (url.isNotEmpty()) {
                        window?.startActivityCatching(Intent(Intent.ACTION_VIEW, url.toUri()))
                    }
                }
            }

            updateFloatingButton = button
            view.addView(
                button,
                ViewGroup.LayoutParams(
                    WRAP_CONTENT,
                    48.dp
                )
            )
            view.setConstraints {
                toBottom(button)
                toCenterX(button)
            }
            syncUpdateButtonPosition()
        }
    }

    private fun syncUpdateButtonPosition() {
        updateFloatingButton?.translationY = -(searchTopOffset() + ViewConstants.GAP.dp)
    }

    private var isShowingUpdateButton = false
    private fun showUpdateButton() {
        if (isShowingUpdateButton) return
        isShowingUpdateButton = true
        createUpdateButtonIfNeeded()
        updateFloatingButton?.isGone = false
        updateFloatingButton?.fadeIn()
    }

    private fun hideUpdateButton() {
        if (!isShowingUpdateButton) return
        isShowingUpdateButton = false
        updateFloatingButton?.let { button ->
            if (button.isVisible) {
                button.fadeOut {
                    if (!isShowingUpdateButton) button.isGone = true
                }
            }
        }
    }

    private fun checkForUpdate(selectedItemId: Int = selectedTabId) {
        if (ConfigStore.isAppUpdateRequired == true &&
            !DEBUG_MODE &&
            UPDATE_BUTTON_AVAILABLE_TABS.contains(selectedItemId)
        ) {
            showUpdateButton()
        } else {
            hideUpdateButton()
        }
    }

    override fun onExploreCreated(exploreVC: ExploreVC) {
        exploreVC.onBestSearchMatchActionChanged = searchView::setBestMatchAction
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (walletEvent.javaClass.simpleName.startsWith("Account")) {
            when (walletEvent) {
                is WalletEvent.AccountWillChange,
                is WalletEvent.AccountChanged,
                is WalletEvent.AccountChangedInApp,
                is WalletEvent.AccountRemoved,
                WalletEvent.AccountsReset,
                is WalletEvent.ConfigReceived,
                WalletEvent.AccountConfigReceived,
                WalletEvent.AppTabsChanged,
                WalletEvent.AppBackground -> finishDirectTabTransition()

                else -> Unit
            }
        }
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                dismissTabMenu()
                toolbarEditor.cancel()
                updateTopAvatar()
                updateToolbarAvailability()
                if (!AccountStore.isPushedTemporary && !walletEvent.isSavingTemporaryAccount) {
                    navigationController?.popToRootUnlessDisplaying(walletEvent.accountId)
                }
            }

            is WalletEvent.TemporaryAccountSaved -> {
                updateTopAvatar()
                navigationController?.popToRoot(false)
                ToastHelper.notifyViewWalletAdded(this, accountId = walletEvent.accountId)
            }

            is WalletEvent.AccountChangedInApp, WalletEvent.AddNewWalletCompletion -> {
                dismissTabMenu()
                updateTopAvatar()
                if (selectedTabId != AppTabsManager.ID_HOME) {
                    selectTab(AppTabsManager.ID_HOME, isInstant = true)
                }
                window?.minimizedBrowser?.dismissAll()
            }

            is WalletEvent.ConfigReceived -> {
                dismissTabMenu()
                checkForUpdate()
            }

            WalletEvent.ToolbarSettingsChanged -> onToolbarSettingsChanged()

            is WalletEvent.AccountWillChange, WalletEvent.AccountChangeAborted -> {
                scheduleToolbarAccountChange()
                routeWalletEvent(walletEvent)
            }

            WalletEvent.AppTabsChanged -> {
                if (!AppTabsManager.contains(selectedTabId)) {
                    selectTab(AppTabsManager.ID_HOME)
                }
                reloadTopTabs()
            }

            else -> {
                routeWalletEvent(walletEvent)
            }
        }
    }

    override fun onBackPressed(): Boolean {
        finishDirectTabTransition()
        searchOverlayNav?.takeIf { it.viewControllers.isNotEmpty() }?.let { nav ->
            if (nav.viewControllers.size > 1) return nav.onBackPressed()
            if (searchEditText.hasFocus()) {
                clearSearchFocus()
            } else {
                updateSearch(null, focused = false)
            }
            return false
        }
        return activeNavigationController?.onBackPressed() ?: true
    }

    override fun getBottomNavigationHeight(): Int {
        if (!isPhoneSearchShown) {
            return (window?.systemBars?.bottom ?: 0) +
                (window?.minimizedBrowserHeight ?: 0f).roundToInt()
        }
        val additionalHeight = (
            (SEARCH_BOTTOM_MARGIN + SEARCH_HEIGHT + SEARCH_TOP_MARGIN).dp +
                keyboardHeight +
                (window?.minimizedBrowserHeight ?: 0f)
            ).roundToInt()
        return additionalHeight + bottomBarHeight + bottomOverlayExtraGap
    }

    /**
     * Hosts the global search screen. It sits above the top tabs but below the search field, so the
     * tabs stay in place under the search screen and are already in position once it fades out.
     */
    private var searchOverlayNav: WNavigationController? = null

    /**
     * Attaches the layer on first use. It stays transparent until [revealSearchOverlay], so a caller
     * that ends up not pushing anything leaves the chrome untouched.
     */
    override val searchOverlayNavigationController: WNavigationController?
        get() {
            searchOverlayNav?.let { return it }
            val window = window ?: return null
            val nav = WNavigationController(window)
            nav.tabBarController = this
            nav.searchOverlayHost = this
            nav.alpha = 0f
            searchOverlayNav = nav
            view.addView(nav, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            restackChromeAboveGradient()
            topChromeBlurViews.forEach {
                it.setupWith(nav)
                it.updateTheme()
            }
            nav.insetsUpdated()
            return nav
        }

    override fun revealSearchOverlay() {
        val nav = searchOverlayNav?.takeIf { it.viewControllers.isNotEmpty() } ?: return
        finishDirectTabTransition()
        tabPager.isUserInputEnabled = false
        topTabsControl.isEnabled = false
        topAvatarView.isEnabled = false
        nav.fadeIn(SEARCH_OVERLAY_ANIMATION)
        fadeTopChromeForSearch(visible = false)
    }

    override fun hideSearchOverlay() {
        finishAgentSearch()
        val nav = searchOverlayNav ?: return
        searchOverlayNav = null
        topChromeBlurViews.forEach {
            it.setupWith(contentView)
            it.updateTheme()
        }
        if (nav.viewControllers.isEmpty()) {
            // Never revealed, so nothing to fade and the chrome was left alone.
            view.removeView(nav)
            return
        }
        if (!isTopChromeHidden) {
            tabPager.isUserInputEnabled = directTabTransition == null && shouldShowPhoneTopTabs(
                selectedTabId,
                activeNavigationController?.viewControllers?.size ?: 1
            )
            topTabsControl.isEnabled = true
            topAvatarView.isEnabled = true
        }
        // Keep the search screen on-screen through the fade, then tear the stack down. Touches are
        // blocked meanwhile so the outgoing layer cannot swallow taps meant for what is behind it.
        nav.blockTouches()
        nav.fadeOut(SEARCH_OVERLAY_ANIMATION) {
            nav.viewControllers.forEach { it.viewWillDisappear() }
            // Detached so the outgoing search cannot clear focus of a replacement session.
            nav.searchOverlayHost = null
            nav.tabBarController = null
            nav.onDestroy()
            view.removeView(nav)
        }
        fadeTopChromeForSearch(visible = true)
    }

    private fun fadeTopChromeForSearch(visible: Boolean) {
        if (!visible) dismissTabMenu()
        val showTabs = visible &&
            !isTopChromeHidden &&
            shouldShowPhoneTopTabs(
                selectedTabId,
                activeNavigationController?.viewControllers?.size ?: 1
            )
        val showAvatar = shouldShowTopAvatar(showTabs)
        fadeTopChromeView(topTabsControl, showTabs)
        fadeTopChromeView(topAvatarView, showAvatar)
    }

    private fun fadeTopChromeView(view: View?, visible: Boolean) {
        view ?: return
        view.animate().cancel()
        if (visible) {
            view.isVisible = true
            view.fadeIn(SEARCH_OVERLAY_ANIMATION)
        } else {
            view.fadeOut(SEARCH_OVERLAY_ANIMATION) {
                view.isInvisible = true
            }
        }
    }

    private fun updateSearch(query: String?, focused: Boolean) {
        searchExplore(query, focused, searchOverlayNavigationController ?: return)
    }

    override fun setSearchText(text: String) {
        searchView.setSearchText(text)
    }

    override fun clearSearchFocus() {
        // Keep the IME up for another screen's focused field.
        val focusedView = searchEditText.rootView.findFocus()
        if (focusedView != null && focusedView !== searchEditText) {
            searchEditText.clearFocus()
            return
        }
        // hideKeyboard() drops focus too. Clearing focus alone would leave the IME up, so the
        // search screen popped out from behind a keyboard with nothing left to type into.
        searchEditText.hideKeyboard()
    }

    // The first of the tabs the top bar shows, in the user's order
    private val firstTabId: Int
        get() = AppTabsManager.orderedTabs.firstOrNull {
            it.intId !in PHONE_PUSHED_TAB_IDS
        }?.intId ?: AppTabsManager.ID_HOME

    override fun switchToFirstTab(): Boolean = selectTabIfNeeded(firstTabId)

    override fun switchToWallet(): Boolean = selectTabIfNeeded(AppTabsManager.ID_HOME)

    private fun selectTabIfNeeded(id: Int): Boolean {
        if (selectedTabId == id) return false
        selectTab(id)
        return true
    }

    override fun hideTabBar() {
        if (isTopChromeHidden) return
        finishDirectTabTransition()
        dismissTabMenu()
        isTopChromeHidden = true
        tabPager.isUserInputEnabled = false
        topTabsControl.isEnabled = false
        topAvatarView.isEnabled = false
        hideTopChromeView(topTabsControl)
        hideTopChromeView(topAvatarView)
    }

    private var isTopChromeHiddenByOverlap = false
    private val bottomChromeFader = OverlappedChromeFader()

    override fun hideChromeOverlapping(windowRect: Rect): Boolean {
        val isScreenChromeHidden = super.hideChromeOverlapping(windowRect)
        val topFrames = listOf(topTabsControl, topAvatarView).mapNotNull { it.frameInWindow() }
        if (!isTopChromeHidden && topFrames.any { Rect.intersects(it, windowRect) }) {
            hideTabBar()
            isTopChromeHiddenByOverlap = true
        }
        val toolbarViews = MToolbarItem.entries.map(::getToolbarView)
        val bottomViews = toolbarViews + listOfNotNull(stickyBottomGradientView)
        val isBottomChromeHidden = bottomChromeFader.hideIfOverlapping(
            windowRect,
            bottomViews.mapNotNull { it.frameInWindow() },
            bottomViews
        )
        return isScreenChromeHidden || isTopChromeHiddenByOverlap || isBottomChromeHidden
    }

    override fun showOverlappedChrome() {
        super.showOverlappedChrome()
        if (isTopChromeHiddenByOverlap) {
            isTopChromeHiddenByOverlap = false
            showTabBar()
        }
        bottomChromeFader.show()
    }

    override fun showTabBar() {
        if (!isTopChromeHidden) return
        isTopChromeHidden = false
        tabPager.isUserInputEnabled = directTabTransition == null && shouldShowPhoneTopTabs(
            selectedTabId,
            activeNavigationController?.viewControllers?.size ?: 1
        )
        topTabsControl.isEnabled = true
        topAvatarView.isEnabled = true
        val shouldShowTabs = shouldShowPhoneTopTabs(
            selectedTabId,
            activeNavigationController?.viewControllers?.size ?: 1
        )
        val shouldShowAvatar = shouldShowTopAvatar(shouldShowTabs)
        showTopChromeView(topTabsControl, shouldShowTabs)
        showTopChromeView(topAvatarView, shouldShowAvatar)
    }

    private fun updateToastAvailability(selectedItemId: Int = selectedTabId) {
        val homeNavigationController = navForOrNull(AppTabsManager.ID_HOME)
        val isMainHomeVisible =
            selectedItemId == AppTabsManager.ID_HOME &&
                window?.topViewController == this &&
                homeNavigationController?.viewControllers?.size == 1

        toastHostView.setToastEnabled(isMainHomeVisible)
    }

    private fun syncToastHostPosition() {
        toastHostView.translationY =
            -(searchTopOffset() + ViewConstants.GAP.dp - TOAST_HOST_BOTTOM_MARGIN.dp)
    }

    // Distance from the container bottom to the top edge of the search bar.
    private fun searchTopOffset(extraGap: Int = bottomOverlayExtraGap): Float = bottomBarHeight +
        keyboardVisible.value.coerceAtLeast(0f) +
        (window?.minimizedBrowserHeight ?: 0f) +
        3.dp + extraGap +
        SEARCH_HEIGHT.dp

    override fun onDestroy() {
        toolbarEditor.cancel()
        Choreographer.getInstance().removeFrameCallback(toolbarAccountChangeFrame)
        view.viewTreeObserver.removeOnPreDrawListener(toolbarBackgroundsListener)
        finishDirectTabTransition()
        dismissTabMenu()
        releaseAgentBar()
        pagePreloader?.destroy()
        pagePreloader = null
        super.onDestroy()
        HomeStatusController.removeListener(topAvatarStatusListener)
        searchOverlayNav?.let { nav ->
            nav.viewControllers.forEach { it.viewWillDisappear() }
            view.removeView(nav)
            nav.onDestroy()
        }
        searchOverlayNav = null
    }
}
