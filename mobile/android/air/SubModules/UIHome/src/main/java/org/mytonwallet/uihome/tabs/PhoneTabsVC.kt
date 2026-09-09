package org.mytonwallet.uihome.tabs

import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.InsetDrawable
import android.net.Uri
import android.text.InputType
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.animation.doOnEnd
import androidx.core.graphics.ColorUtils
import androidx.core.net.toUri
import androidx.core.view.children
import androidx.core.view.doOnLayout
import androidx.core.view.doOnPreDraw
import androidx.core.view.get
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.widget.doAfterTextChanged
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import kotlin.math.abs
import kotlin.math.roundToInt
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import me.vkryl.android.animatorx.FloatAnimator
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVC
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WNavigationController.PresentationConfig
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.commonViews.AccountItemView
import org.mytonwallet.app_air.uicomponents.commonViews.UpdateStatusView
import org.mytonwallet.app_air.uicomponents.commonViews.toast.ToastHost
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.drawable.StickyBottomGradientDrawable
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.extensions.setupSpringFling
import org.mytonwallet.app_air.uicomponents.extensions.springToItem
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.HomeStatusController
import org.mytonwallet.app_air.uicomponents.helpers.ToastHelper
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
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
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketVC
import org.mytonwallet.app_air.uisettings.viewControllers.settings.SettingsVC
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.EnvironmentStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import org.mytonwallet.uihome.home.HomeVC
import org.mytonwallet.uihome.home.actions.HomeActionsSheetVC
import org.mytonwallet.uihome.tabs.views.FloatingBottomNavigationView
import org.mytonwallet.uihome.tabs.views.IBottomNavigationView

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
        private const val ACTIONS_BUTTON_GAP = 12
        private const val ACTIONS_ICON_SIZE = 18

        private const val ACTIONS_SHEET_INSET = 8

        private const val TOAST_HOST_BOTTOM_MARGIN = 12

        const val BOTTOM_TABS_LAYOUT_HEIGHT = 75
        const val BOTTOM_TABS_BOTTOM_MARGIN = -7
        const val BOTTOM_TABS_BOTTOM_TO_NAV_DIFF = 2

        private const val EXPERIMENTAL_BOTTOM_EXTRA_GAP = 7

        private const val SEARCH_OVERLAY_ANIMATION = AnimationConstants.VERY_VERY_QUICK_ANIMATION
        internal const val TOP_TABS_HEIGHT = 44
        private const val TOP_TABS_THUMB_HEIGHT = 36f
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

        private val EXPERIMENTAL_PUSHED_TAB_IDS = setOf(
            IBottomNavigationView.ID_AGENT,
            IBottomNavigationView.ID_SETTINGS
        )

        private val UPDATE_BUTTON_AVAILABLE_TABS = setOf(
            IBottomNavigationView.ID_HOME,
            IBottomNavigationView.ID_SETTINGS
        )

        private const val GRADIENT_ALPHA = 229
    }

    override val isSwipeBackAllowed = false
    override var ignoreSideGuttering = false

    override var currentTabId: Int
        get() = bottomNavigationView.selectedItemId
        set(value) {
            if (experimentalTopTabsEnabled && value in EXPERIMENTAL_PUSHED_TAB_IDS) {
                pendingSelectedTab = IBottomNavigationView.ID_HOME
                pendingTabToPresentOverMain = value
            } else {
                pendingSelectedTab = value
            }
        }
    private var pendingSelectedTab: Int? = null
    private var pendingTabToPresentOverMain: Int? = null

    override fun onExploreCreated(exploreVC: ExploreVC) {
        if (!experimentalTopTabsEnabled) {
            searchGlass?.setupWith(exploreVC.view)
        }
    }

    override fun exportSearchText(): String = if (searchMatchedSite != null) {
        searchKeyword
    } else {
        (searchEditText.text?.toString() ?: "")
    }

    override fun restoreSearchText(text: String) {
        searchEditText.setText(text)
    }

    override fun detachMountedStacks() {
        // With experimental top tabs the stacks live inside the pager's pages rather than directly
        // in contentView; exportStacks() removes each nav from its own parent.
        contentView.removeAllViews()
    }

    private val contentView = WView(context)

    private inner class ExperimentalTabPageView : FrameLayout(context) {
        init {
            layoutParams = RecyclerView.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        }

        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private val hitRect = Rect()
        private var initialRawX = 0f
        private var initialRawY = 0f
        private var lastRawX = 0f
        private var trackingGesture = false
        private var horizontalGesture = false
        private var verticalGesture = false
        private var allowParentPager = false
        private var nestedOwnsHorizontalGesture = false

        fun bind(navigationController: WNavigationController) {
            if (childCount == 1 && getChildAt(0) === navigationController) return
            removeAllViews()
            (navigationController.parent as? ViewGroup)?.removeView(navigationController)
            addView(navigationController, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }

        fun unbind() {
            // Recycling mid-swipe would otherwise strand the fake drag, since only this view's
            // touch stream ends it, and every later beginFakeDrag() would fail.
            if (experimentalTabPager.isFakeDragging) experimentalTabPager.endFakeDrag()
            resetGestureTracking()
            removeAllViews()
        }

        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    initialRawX = event.rawX
                    initialRawY = event.rawY
                    lastRawX = event.rawX
                    trackingGesture = true
                    horizontalGesture = false
                    verticalGesture = false
                    val startedInHorizontalChild =
                        hasTouchedScrollableChild(
                            this,
                            initialRawX.toInt(),
                            initialRawY.toInt(),
                            -1
                        ) ||
                            hasTouchedScrollableChild(
                                this,
                                initialRawX.toInt(),
                                initialRawY.toInt(),
                                1
                            )
                    allowParentPager = !startedInHorizontalChild
                    super.requestDisallowInterceptTouchEvent(!allowParentPager)
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialRawX
                    val dy = event.rawY - initialRawY
                    val stepDx = event.rawX - lastRawX
                    lastRawX = event.rawX
                    if (!horizontalGesture && !verticalGesture) {
                        if (abs(dx) > touchSlop && abs(dx) > abs(dy)) {
                            horizontalGesture = true
                        } else if (abs(dy) > touchSlop && abs(dy) > abs(dx)) {
                            verticalGesture = true
                            allowParentPager = false
                            super.requestDisallowInterceptTouchEvent(true)
                        }
                    }
                    if (horizontalGesture) {
                        if (experimentalTabPager.isFakeDragging) {
                            experimentalTabPager.fakeDragBy(stepDx)
                            return true
                        }
                        if (!nestedOwnsHorizontalGesture) {
                            val direction = if (dx < 0f) 1 else -1
                            val nestedCanScroll = hasTouchedScrollableChild(
                                this,
                                initialRawX.toInt(),
                                initialRawY.toInt(),
                                direction
                            )
                            if (!allowParentPager &&
                                !nestedCanScroll &&
                                experimentalTabPager.isUserInputEnabled &&
                                experimentalTabPager.beginFakeDrag()
                            ) {
                                val cancelEvent = MotionEvent.obtain(event).apply {
                                    action = MotionEvent.ACTION_CANCEL
                                }
                                super.dispatchTouchEvent(cancelEvent)
                                cancelEvent.recycle()
                                experimentalTabPager.fakeDragBy(stepDx)
                                return true
                            }
                            nestedOwnsHorizontalGesture = nestedCanScroll
                            allowParentPager = !nestedCanScroll
                            super.requestDisallowInterceptTouchEvent(!allowParentPager)
                        }
                    }
                }
            }

            if (
                (
                    event.actionMasked == MotionEvent.ACTION_UP ||
                        event.actionMasked == MotionEvent.ACTION_CANCEL
                    ) &&
                experimentalTabPager.isFakeDragging
            ) {
                experimentalTabPager.endFakeDrag()
                resetGestureTracking()
                return true
            }
            val handled = super.dispatchTouchEvent(event)
            if (event.actionMasked == MotionEvent.ACTION_UP ||
                event.actionMasked == MotionEvent.ACTION_CANCEL
            ) {
                resetGestureTracking()
            }
            return handled
        }

        private fun resetGestureTracking() {
            trackingGesture = false
            horizontalGesture = false
            verticalGesture = false
            allowParentPager = false
            nestedOwnsHorizontalGesture = false
            super.requestDisallowInterceptTouchEvent(false)
        }

        override fun requestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {
            if (trackingGesture) {
                super.requestDisallowInterceptTouchEvent(!allowParentPager)
            } else {
                super.requestDisallowInterceptTouchEvent(disallowIntercept)
            }
        }

        private fun hasTouchedScrollableChild(
            candidate: View,
            rawX: Int,
            rawY: Int,
            direction: Int
        ): Boolean {
            if (!candidate.isShown ||
                !candidate.getGlobalVisibleRect(hitRect) ||
                !hitRect.contains(rawX, rawY)
            ) {
                return false
            }
            if (candidate is ViewGroup) {
                for (index in candidate.childCount - 1 downTo 0) {
                    if (
                        hasTouchedScrollableChild(
                            candidate.getChildAt(index),
                            rawX,
                            rawY,
                            direction
                        )
                    ) {
                        return true
                    }
                }
            }
            return candidate !== this && candidate.canScrollHorizontally(direction)
        }
    }

    private inner class ExperimentalTabPageHolder(val page: ExperimentalTabPageView) :
        RecyclerView.ViewHolder(page)

    private inner class ExperimentalTabPagerAdapter :
        RecyclerView.Adapter<ExperimentalTabPageHolder>() {
        init {
            setHasStableIds(true)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
            ExperimentalTabPageHolder(ExperimentalTabPageView())

        override fun onBindViewHolder(holder: ExperimentalTabPageHolder, position: Int) {
            holder.page.bind(getNavigationStack(topTabIds[position]))
        }

        override fun onViewRecycled(holder: ExperimentalTabPageHolder) {
            holder.page.unbind()
        }

        override fun getItemCount(): Int = topTabIds.size

        override fun getItemId(position: Int): Long = topTabIds[position].toLong()
    }

    private var updateFloatingButton: WLabel? = null
    private var updateFloatingButtonBackground: WRippleDrawable? = null
    private var stickyBackgroundColor =
        if (ThemeManager.isDark) WColor.SecondaryBackground.color else WColor.Background.color

    private val experimentalTopTabsEnabled = WGlobalStorage.areTopTabsEnabled()
    private val searchHintKey
        get() = if (experimentalTopTabsEnabled) "Search or Ask" else "Search app or enter address"

    private val bottomTabsHeight: Int
        get() = if (experimentalTopTabsEnabled) {
            0
        } else {
            BOTTOM_TABS_LAYOUT_HEIGHT.dp + BOTTOM_TABS_BOTTOM_MARGIN.dp
        }

    override val minimizedBlurRootView: ViewGroup?
        get() = contentView
    val bottomBarHeight: Int
        get() {
            return (window?.systemBars?.bottom ?: 0) + (-2).dp
        }

    override fun rootTopInsetForTab(id: Int): Int {
        if (!experimentalTopTabsEnabled) return 0
        if (id == IBottomNavigationView.ID_SETTINGS) return 0
        return (WNavigationBar.DEFAULT_HEIGHT + 2).dp
    }

    private var isSwitchingTabs = false
    private var selectingTabId: Int? = null

    private val tabListener = object : IBottomNavigationView.Listener {
        override fun onTabSelected(itemId: Int, isReselect: Boolean): Boolean {
            if (isReselect) {
                navForOrNull(itemId)?.apply {
                    if (viewControllers.size == 1) scrollToTop() else popToRoot()
                }
                return true
            }
            if (isSwitchingTabs) return false

            selectingTabId = itemId
            if (experimentalTopTabsEnabled) {
                updateTopChromeVisibility(itemId)
            }
            checkForUpdate(itemId)
            val isAgent = itemId == IBottomNavigationView.ID_AGENT
            ignoreSideGuttering = isAgent
            val wasAgent = bottomNavigationView.selectedItemId == IBottomNavigationView.ID_AGENT
            if (wasAgent != isAgent) updateBottomNavigationBackground(itemId)
            bottomReversedCornerView?.setHorizontalPadding(
                if (ignoreSideGuttering) 0f else ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat()
            )

            val newNav = getNavigationStack(itemId)
            updateToastAvailability(itemId)
            val oldNav = if (experimentalTopTabsEnabled) {
                activeNavigationController
            } else {
                contentView[0] as? WNavigationController
            }

            val searchVisible = shouldShowSearch(itemId)
            if (searchView.hasFocus() && (experimentalTopTabsEnabled || !searchVisible)) {
                searchView.clearFocus()
            }

            if (experimentalTopTabsEnabled) {
                switchExperimentalTab(itemId, oldNav, newNav)
                selectingTabId = null
                return true
            }

            if (newNav.parent != null) {
                selectingTabId = null
                return true // switching navigation bottom bar view type
            }

            oldNav?.viewWillDisappear()

            val animationsEnabled = WGlobalStorage.getAreAnimationsActive()

            if (animationsEnabled) {
                fadeSearchChrome(searchView, searchVisible)

                newNav.alpha = 0f
                newNav.scaleX = 0.98f
                newNav.scaleY = 0.98f

                contentView.addView(
                    newNav,
                    0,
                    ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                )

                newNav.viewWillAppear()

                isSwitchingTabs = true

                oldNav?.animate()
                    ?.alpha(0f)
                    ?.scaleX(0.98f)
                    ?.scaleY(0.98f)
                    ?.setDuration(AnimationConstants.VERY_VERY_QUICK_ANIMATION)
                    ?.setInterpolator(CubicBezierInterpolator.EASE_OUT)
                    ?.withEndAction {
                        contentView.removeView(oldNav)
                        isSwitchingTabs = false
                        oldNav.alpha = 1f
                        oldNav.scaleX = 1f
                        oldNav.scaleY = 1f
                    }

                newNav.animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(AnimationConstants.VERY_VERY_QUICK_ANIMATION)
                    .setInterpolator(CubicBezierInterpolator.EASE_OUT)
                    .withEndAction {
                        // A full-screen push may interrupt this appearance before the animation ends.
                        if (newNav.isDisappeared) return@withEndAction
                        newNav.viewDidAppear()
                    }
                    .start()
            } else {
                setSearchChromeVisible(searchVisible)

                oldNav?.let { contentView.removeView(it) }
                contentView.addView(
                    newNav,
                    ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                )
                newNav.viewWillAppear()
                newNav.viewDidAppear()
            }
            selectingTabId = null
            return true
        }
    }

    override val bottomNavigationView: IBottomNavigationView =
        FloatingBottomNavigationView(context, contentView).also { it.listener = tabListener }

    private var topTabIds = emptyList<Int>()
    private val experimentalTabPagerAdapter = ExperimentalTabPagerAdapter()
    private var pendingTabAppearance: WNavigationController? = null
    private val experimentalTabPager by lazy {
        ViewPager2(context).apply {
            id = View.generateViewId()
            adapter = experimentalTabPagerAdapter
            offscreenPageLimit = ViewPager2.OFFSCREEN_PAGE_LIMIT_DEFAULT
            registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
                override fun onPageScrolled(
                    position: Int,
                    positionOffset: Float,
                    positionOffsetPixels: Int
                ) {
                    topTabsControl.updateThumbPosition(
                        index = position,
                        offset = position + positionOffset,
                        targetIndex = currentItem,
                        force = false,
                        isAnimatingToPosition = false
                    )
                }

                override fun onPageScrollStateChanged(state: Int) {
                    if (state != ViewPager2.SCROLL_STATE_IDLE) return
                    val index = currentItem
                    topTabsControl.updateThumbPosition(
                        index = index,
                        offset = index.toFloat(),
                        targetIndex = index,
                        force = true,
                        isAnimatingToPosition = false
                    )
                    val tabId = topTabIds.getOrNull(index)
                    if (selectingTabId == null &&
                        tabId != null &&
                        bottomNavigationView.selectedItemId != tabId
                    ) {
                        bottomNavigationView.selectedItemId = tabId
                    }
                    completePendingTabAppearance()
                }
            })
            (getChildAt(0) as? RecyclerView)?.itemAnimator = null
            setupSpringFling { it }
        }
    }

    private fun switchExperimentalTab(
        itemId: Int,
        oldNav: WNavigationController?,
        newNav: WNavigationController
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
        val previousIndex = experimentalTabPager.currentItem
        val animated = WGlobalStorage.getAreAnimationsActive()
        if (animated && previousIndex != index && experimentalTabPager.width > 0) {
            experimentalTabPager.springToItem(index) {
                completePendingTabAppearance()
            }
        } else {
            experimentalTabPager.setCurrentItem(index, false)
            completePendingTabAppearance()
        }
    }

    private fun completePendingTabAppearance() {
        pendingTabAppearance?.let { nav ->
            if (!nav.isDisappeared) {
                nav.viewDidAppear()
            }
        }
        pendingTabAppearance = null
    }

    private val topTabsDelegate = object : WClearSegmentedControl.Delegate {
        override fun onIndexChanged(to: Int, animated: Boolean) {
            topTabIds.getOrNull(to)?.let { bottomNavigationView.selectedItemId = it }
        }

        override fun onItemMoved(from: Int, to: Int) {}

        override fun enterReorderingMode() {}
    }
    private val topTabsControl by lazy {
        WClearSegmentedControl(
            context,
            horizontalPaddingDp = 1f,
            thumbHeightDp = TOP_TABS_THUMB_HEIGHT
        ).apply {
            paintColor = WColor.Tint.color.colorWithAlpha(31)
            primaryTextColorOverride = WColor.Tint.color
            fillAvailableWidth = true
        }
    }
    private var topTabsGlass: WGlassView? = null

    private val topAvatarRipple by lazy {
        WRippleDrawable.create(TOP_AVATAR_SIZE.dp / 2f)
    }
    private val topAvatarIconView by lazy {
        AccountIconView(
            context,
            AccountIconView.Usage.ViewItem(16f.dp)
        )
    }
    private val alternateTopAvatarIconView by lazy {
        AccountIconView(
            context,
            AccountIconView.Usage.ViewItem(16f.dp)
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
        applyTopAvatarStatus(state, animated)
    }
    private var topAvatarAccountId: String? = null
    private val topAvatarView by lazy {
        WFrameLayout(context).apply {
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
            setOnLongClickListener {
                presentWalletSwitcherPopup(it, WMenuPopup.Positioning.BELOW)
            }
        }
    }
    private var topAvatarGlass: WGlassView? = null
    private var isTopChromeHidden = false

    private fun reloadTopTabs(selectedItemId: Int = bottomNavigationView.selectedItemId) {
        if (!experimentalTopTabsEnabled) return
        val tabs = AppTabsManager.orderedTabs.filter {
            it.intId !in EXPERIMENTAL_PUSHED_TAB_IDS
        }
        topTabIds = tabs.map { it.intId }
        val requestedIndex = topTabIds.indexOf(selectedItemId)
        val selectedIndex = requestedIndex.coerceAtLeast(0)
        if (requestedIndex < 0) {
            // The requested tab has no page (e.g. Agent/Settings, which are pushed instead), so
            // keep the selected id in sync with the page the pager actually shows.
            topTabIds.getOrNull(selectedIndex)?.let {
                if (bottomNavigationView.selectedItemId != it) {
                    bottomNavigationView.selectedItemId = it
                }
            }
        }
        topTabsControl.setItems(
            tabs.map {
                WClearSegmentedControl.Item(
                    title = LocaleController.getString(it.labelKey),
                    onRemove = null,
                    onClick = null
                )
            },
            selectedIndex,
            topTabsDelegate
        )
        experimentalTabPagerAdapter.notifyDataSetChanged()
        if (topTabIds.isNotEmpty()) {
            experimentalTabPager.setCurrentItem(selectedIndex, false)
        }
        updateTopChromeVisibility(selectedItemId)
    }

    private fun updateTopChromeVisibility(selectedItemId: Int) {
        val shouldShowTabs =
            !isTopChromeHidden && selectedItemId != IBottomNavigationView.ID_SETTINGS
        val shouldShowAvatar = shouldShowTabs && AccountStore.activeAccount != null
        topTabsControl.isVisible = shouldShowTabs
        topAvatarView.isVisible = shouldShowAvatar
        if (!isTopChromeHidden) {
            topTabsControl.alpha = 1f
            topAvatarView.alpha = 1f
        }
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
        val shouldShow = state !is UpdateStatusView.State.Updated
        topAvatarRingView.animate().cancel()
        if (!animated) {
            topAvatarRingView.alpha = if (shouldShow) 1f else 0f
            topAvatarRingView.isInvisible = !shouldShow
            return
        }
        if (shouldShow) {
            topAvatarRingView.isVisible = true
            topAvatarRingView.fadeIn(AnimationConstants.QUICK_ANIMATION)
        } else {
            topAvatarRingView.fadeOut(AnimationConstants.QUICK_ANIMATION) {
                if (topAvatarStatus is UpdateStatusView.State.Updated) {
                    topAvatarRingView.isInvisible = true
                }
            }
        }
    }

    private fun updateTopAvatar() {
        if (!experimentalTopTabsEnabled) return
        val account = AccountStore.activeAccount
        if (account != null) {
            val currentIcon = visibleTopAvatarIconView ?: topAvatarIconView.also {
                visibleTopAvatarIconView = it
            }
            if (topAvatarAccountId == null || topAvatarAccountId == account.accountId) {
                currentIcon.config(account)
                topAvatarAccountId = account.accountId
            } else {
                val nextIcon = if (currentIcon === topAvatarIconView) {
                    alternateTopAvatarIconView
                } else {
                    topAvatarIconView
                }
                currentIcon.animate().cancel()
                nextIcon.animate().cancel()
                currentIcon.alpha = 1f
                currentIcon.isVisible = true
                nextIcon.config(account)
                nextIcon.alpha = 0f
                nextIcon.isVisible = true
                visibleTopAvatarIconView = nextIcon
                topAvatarAccountId = account.accountId

                if (WGlobalStorage.getAreAnimationsActive() && topAvatarView.isAttachedToWindow) {
                    currentIcon.animate()
                        .alpha(0f)
                        .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                        .setInterpolator(CubicBezierInterpolator.EASE_OUT)
                        .withEndAction {
                            if (visibleTopAvatarIconView !== currentIcon) {
                                currentIcon.isInvisible = true
                            }
                        }
                        .start()
                    nextIcon.animate()
                        .alpha(1f)
                        .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                        .setInterpolator(CubicBezierInterpolator.EASE_OUT)
                        .start()
                } else {
                    currentIcon.alpha = 0f
                    currentIcon.isInvisible = true
                    nextIcon.alpha = 1f
                }
            }
        }
        updateTopChromeVisibility(bottomNavigationView.selectedItemId)
    }

    private fun updateTopChromeLayout() {
        if (!experimentalTopTabsEnabled || topTabsControl.parent == null) return
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
        view.setConstraints {
            toTopPx(topAvatarView, top)
            toEndPx(
                topAvatarView,
                endSystemInset + TOP_AVATAR_END_MARGIN.dp
            )
            toTopPx(topTabsControl, top + TOP_TABS_CENTERING_OFFSET.dp)
            toStartPx(
                topTabsControl,
                startSystemInset + TOP_TABS_START_MARGIN.dp
            )
            toEndPx(
                topTabsControl,
                endSystemInset + TOP_TABS_END_MARGIN.dp
            )
        }
    }

    private val toastHostView by lazy {
        ToastHost(context).apply {
            attachBlurRoot(contentView)
        }
    }

    var isProcessingSearchKeyword = false
    private val topChromeBlurViews
        get() = listOfNotNull(searchGlass, topTabsGlass, topAvatarGlass)
    private val searchEditText by lazy {
        object : WSearchEditText(context) {
            override fun onFocusChanged(
                focused: Boolean,
                direction: Int,
                previouslyFocusedRect: Rect?
            ) {
                super.onFocusChanged(focused, direction, previouslyFocusedRect)
                searchFocused.animatedValue = focused
            }

            override fun onSelectionChanged(selStart: Int, selEnd: Int) {
                super.onSelectionChanged(selStart, selEnd)
                if (isProcessingSearchKeyword || searchMatchedSite == null) return

                val keyword = searchKeyword
                val autoCompleteText = text?.toString()
                doOnPreDraw {
                    if (isProcessingSearchKeyword ||
                        searchMatchedSite == null ||
                        searchKeyword != keyword ||
                        text?.toString() != autoCompleteText
                    ) {
                        return@doOnPreDraw
                    }
                    isProcessingSearchKeyword = true
                    removeAutoCompleteSuffix()
                    searchMatchedSite = null
                    isProcessingSearchKeyword = false
                }
            }
        }.apply {
            hint = LocaleController.getString(searchHintKey)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            doAfterTextChanged { editable ->
                if (isProcessingSearchKeyword) return@doAfterTextChanged
                val suffixStart = autoCompleteSuffixStart()
                val keyword =
                    if (suffixStart >= 0) {
                        editable?.substring(0, suffixStart) ?: ""
                    } else {
                        editable?.toString() ?: ""
                    }
                if (keyword == searchKeyword) return@doAfterTextChanged
                if (suffixStart >= 0) {
                    isProcessingSearchKeyword = true
                    removeAutoCompleteSuffix()
                    isProcessingSearchKeyword = false
                }
                val shouldCheckForMatchingUrl = keyword.length > searchKeyword.length
                searchKeyword = keyword
                searchMatchedSite = null
                updateSearch(searchKeyword, hasFocus())
                if (shouldCheckForMatchingUrl) {
                    post {
                        if (searchKeyword == keyword && this@apply.text?.toString() == keyword) {
                            checkForMatchingUrl(keyword)
                        }
                    }
                }
            }
            onFocusChangeListener = View.OnFocusChangeListener { _, hasFocus ->
                if (isProcessingSearchKeyword) return@OnFocusChangeListener
                if (!hasFocus &&
                    (context as? android.app.Activity)?.isChangingConfigurations == true
                ) {
                    return@OnFocusChangeListener
                }
                val query = if (hasFocus) text?.toString() else null
                updateSearch(query, hasFocus)
                checkForMatchingUrl(query ?: "")
            }
            setOnEditorActionListener { _, actionId, event ->
                if (actionId == EditorInfo.IME_ACTION_DONE ||
                    (
                        event?.action == KeyEvent.ACTION_DOWN &&
                            event.keyCode == KeyEvent.KEYCODE_ENTER
                        )
                ) {
                    val submittedText = text.toString()
                    if (submittedText.isBlank()) {
                        clearFocus()
                        hideKeyboard()
                        return@setOnEditorActionListener true
                    }
                    if (WalletContextManager.delegate?.get()?.handleDeeplink(submittedText) ==
                        true
                    ) {
                        setText("")
                        clearFocus()
                        hideKeyboard()
                        return@setOnEditorActionListener true
                    }
                    val matchedSite = searchMatchedSite
                    val onBestMatchResolved: (Boolean) -> Unit = { opened ->
                        if (opened) {
                            setText("")
                            clearFocus()
                            hideKeyboard()
                        } else {
                            val config = matchedSite?.let {
                                InAppBrowserConfig(
                                    url = it.url,
                                    injectDappConnect = true,
                                    saveInVisitedHistory = true
                                )
                            } ?: run {
                                val (isValidUrl, uri) = InAppBrowserVC.convertToUri(submittedText)
                                if (!isValidUrl) {
                                    ExploreHistoryStore.saveSearchHistory(submittedText)
                                }
                                InAppBrowserConfig(
                                    url = uri.toString(),
                                    injectDappConnect = true,
                                    saveInVisitedHistory = isValidUrl
                                )
                            }
                            val inAppBrowserVC = InAppBrowserVC(
                                context,
                                this@PhoneTabsVC,
                                config
                            )
                            window?.let { window ->
                                val nav = WNavigationController(window)
                                nav.setRoot(inAppBrowserVC)
                                window.present(nav, onCompletion = {
                                    setText("")
                                })
                            }
                            clearFocus()
                            hideKeyboard()
                        }
                    }
                    if (cachedExploreVC?.openBestSearchMatch(onBestMatchResolved) == true) {
                        return@setOnEditorActionListener true
                    }
                    onBestMatchResolved(false)
                    return@setOnEditorActionListener true
                }
                false
            }
        }
    }
    private var searchGlass: WGlassView? = null
    private val searchView by lazy {
        WFrameLayout(context).apply {
            alpha = 0f
            visibility = View.INVISIBLE
            translationY = -SEARCH_BOTTOM_MARGIN.dp.toFloat()
            setBackgroundColor(Color.TRANSPARENT, 24f.dp, clipToBounds = true)
            addView(searchEditText, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    // Round "+" button beside the search field (top-tabs mode only); opens the actions sheet,
    // or morphs into an "X" that closes the search while it has focus.
    private var actionsButtonGlass: WGlassView? = null
    private val actionsButtonIcon by lazy {
        AppCompatImageView(context).apply {
            setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_plus_thick)
            setColorFilter(WColor.TextOnTint.color)
        }
    }
    private val actionsButtonRipple by lazy {
        WRippleDrawable.create(SEARCH_HEIGHT.dp / 2f).apply {
            rippleColor = WColor.TextOnTint.color.colorWithAlpha(64)
        }
    }
    private val actionsButton by lazy {
        WFrameLayout(context).apply {
            alpha = 0f
            visibility = View.INVISIBLE
            isClickable = true
            contentDescription = LocaleController.getString("More actions")
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
        }
    }

    private fun updateActionsButtonMorph() {
        val fraction = searchFocused.floatValue
        actionsButton.contentDescription = LocaleController.getString(
            if (searchEditText.hasFocus()) "Close" else "More actions"
        )
        actionsButtonIcon.rotation = 45f * fraction
        val iconColor =
            ColorUtils.blendARGB(WColor.TextOnTint.color, WColor.PrimaryText.color, fraction)
        actionsButtonIcon.setColorFilter(iconColor)
        actionsButtonRipple.rippleColor = iconColor.colorWithAlpha(64)
        actionsButton.setBackgroundColor(
            ColorUtils.blendARGB(WColor.Tint.color, WColor.Background.color, fraction),
            SEARCH_HEIGHT.dp / 2f
        )
    }

    private fun presentActionsSheet() {
        val window = window ?: return
        val homeVC = navForOrNull(IBottomNavigationView.ID_HOME)
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
            HomeActionsSheetVC(context) { identifier ->
                homeVC.onHeaderAction(identifier)
            }
        )
        window.present(
            nav,
            WWindow.PresentAnimation.ExpandFrom(
                actionsButton,
                cornerRadius = SEARCH_HEIGHT.dp / 2f,
                fillColor = WColor.Tint.color
            )
        )
    }

    private fun fadeSearchChrome(target: View, visible: Boolean) {
        if (visible) {
            target.visibility = View.VISIBLE
        }
        target.animate()
            .alpha(if (visible) 1f else 0f)
            .setDuration(AnimationConstants.VERY_VERY_QUICK_ANIMATION)
            .setInterpolator(CubicBezierInterpolator.EASE_OUT)
            .withEndAction {
                if (!visible) {
                    target.visibility = View.INVISIBLE
                }
            }
            .start()
    }

    private fun setSearchChromeVisible(visible: Boolean) {
        searchView.alpha = if (visible) 1f else 0f
        searchView.visibility = if (visible) View.VISIBLE else View.INVISIBLE
        if (experimentalTopTabsEnabled) {
            actionsButton.alpha = searchView.alpha
            actionsButton.visibility = searchView.visibility
        }
    }

    val searchWidth by lazy {
        val hintWidth = searchEditText.paint.measureText(
            LocaleController.getString(searchHintKey)
        ).ceilToInt()
        (62.dp + hintWidth).coerceAtMost(320.dp)
    }

    private var stickyBottomGradientView: View? = null
    private var stickyBottomGradientDrawable: StickyBottomGradientDrawable? = null

    private val keyboardVisible = FloatAnimator(220L, AnimatorUtils.DECELERATE_INTERPOLATOR, 0f) {
        render()
    }

    private var searchFocused =
        BoolAnimator(
            AnimationConstants.VERY_QUICK_ANIMATION,
            CubicBezierInterpolator.EASE_BOTH,
            false
        ) { _, _, _, _ ->
            updateSearchWidth()
            if (experimentalTopTabsEnabled) updateActionsButtonMorph()
        }

    private fun render() {
        val keyboardHeight = keyboardVisible.value.coerceAtLeast(0f)
        val minimizedNavHeightPx = minimizedNavHeight ?: 0f

        val tabsHeight = bottomTabsHeight

        val contentHeight = tabsHeight + keyboardHeight + minimizedNavHeightPx

        val hiddenTranslationY = (1f - visibilityFraction) * contentHeight

        // Alpha
        bottomNavigationView.alpha = if (experimentalTopTabsEnabled) 0f else visibilityFraction
        minimizedNav?.alpha = visibilityFraction

        // Bottom navigation height
        bottomNavigationView.layoutParams?.let { params ->
            val newHeight = if (experimentalTopTabsEnabled) {
                0
            } else {
                bottomBarHeight +
                    (visibilityFraction * contentHeight).roundToInt() +
                    ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()
            }

            if (params.height != newHeight) {
                params.height = newHeight
                bottomNavigationView.layoutParams = params
            }
        }

        // Bottom navigation translation
        bottomNavigationView.translationY = if (experimentalTopTabsEnabled) {
            0f
        } else {
            contentHeight -
                (bottomTabsHeight + minimizedNavHeightPx) +
                BOTTOM_TABS_BOTTOM_TO_NAV_DIFF.dp * visibilityFraction
        }
        syncToastHostPosition()
        updateExperimentalSearchPosition()

        updateStickyGradientHeight()

        // Minimized nav animation
        if (activeVisibilityValueAnimator?.isRunning == true) {
            minimizedNav?.let { nav ->
                nav.y = minimizedNavY!! + hiddenTranslationY
                minimizedNavGlass?.let {
                    applyMinimizedShadowProgress(
                        nav,
                        it.alpha,
                        nav.width,
                        nav.height,
                        24.dp.toFloat()
                    )
                }
            }
        }
        onUpdateAdditionalHeight()
    }

    private fun updateExperimentalSearchPosition() {
        if (!experimentalTopTabsEnabled) return
        searchView.translationY = -(searchTopOffset() - SEARCH_HEIGHT.dp)
        actionsButton.translationY = searchView.translationY
    }

    private fun onUpdateAdditionalHeight() {
        activeNavigationController?.insetsUpdated()
        // The search overlay reserves the same bottom height, so it has to follow the keyboard too.
        searchOverlayNav?.insetsUpdated()
    }

    private fun updateSearchWidth() {
        if (!experimentalTopTabsEnabled && searchView.layoutParams != null) {
            val newWidth = lerp(
                searchWidth.toFloat(),
                view.width - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp - 20f.dp,
                searchFocused.floatValue
            ).roundToInt()
            if (searchView.layoutParams.width != newWidth) {
                searchView.layoutParams = searchView.layoutParams.apply {
                    width = newWidth
                }
            }
        }
        searchEditText.setPaddingDpLocalized(
            lerp(22f, 16f, searchFocused.floatValue).ceilToInt(),
            0,
            lerp(0f, 48f, searchFocused.floatValue).ceilToInt(),
            0
        )
    }

    override fun setupViews() {
        super.setupViews()

        setTopBlur(visible = false, animated = false)

        view.alpha = 0f
        view.doOnLayout { view.fadeIn() }

        WalletCore.registerObserver(this)

        bottomNavigationView.clipChildren = false
        bottomNavigationView.clipToPadding = false
        bottomNavigationView.visibility =
            if (experimentalTopTabsEnabled) View.INVISIBLE else View.VISIBLE

        view.addView(contentView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(bottomNavigationView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(toastHostView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(
            searchView,
            ConstraintLayout.LayoutParams(
                if (experimentalTopTabsEnabled) 0 else searchWidth,
                SEARCH_HEIGHT.dp
            )
        )
        searchGlass = WGlassView.attachTo(
            searchView,
            24f.dp,
            GlassProviders.pill(WColor.SearchFieldBackground),
            root = if (experimentalTopTabsEnabled) contentView else null
        )
        if (experimentalTopTabsEnabled) {
            view.addView(
                actionsButton,
                ConstraintLayout.LayoutParams(SEARCH_HEIGHT.dp, SEARCH_HEIGHT.dp)
            )
            actionsButtonGlass = WGlassView.attachTo(
                actionsButton,
                SEARCH_HEIGHT.dp / 2f,
                GlassProviders.shadowOnly(),
                root = null
            )
        }
        ensureStickyBottomGradientView()
        if (experimentalTopTabsEnabled) {
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
            HomeStatusController.addListener(topAvatarStatusListener)
        }
        view.setConstraints {
            if (experimentalTopTabsEnabled) {
                val searchHorizontalMargin =
                    (ViewConstants.HORIZONTAL_PADDINGS + 6).toFloat()
                toStart(searchView, searchHorizontalMargin)
                endToStart(searchView, actionsButton, ACTIONS_BUTTON_GAP.toFloat())
                toBottom(searchView)
                toEnd(actionsButton, searchHorizontalMargin)
                toBottom(actionsButton)
            } else {
                toCenterX(searchView)
                bottomToTop(searchView, bottomNavigationView)
            }
            toCenterX(toastHostView)
            if (experimentalTopTabsEnabled) {
                toBottom(toastHostView)
            } else {
                bottomToTop(toastHostView, bottomNavigationView)
            }
            toBottom(bottomNavigationView)
            toCenterX(bottomNavigationView)
            stickyBottomGradientView?.let {
                toBottom(it)
            }
        }
        updateTopChromeLayout()

        val initialTab = pendingSelectedTab ?: IBottomNavigationView.ID_HOME
        reloadTopTabs(initialTab)
        if (experimentalTopTabsEnabled) {
            contentView.addView(
                experimentalTabPager,
                ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            )
        } else {
            contentView.addView(
                getNavigationStack(initialTab),
                ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            )
        }
        pendingSelectedTab?.let { tab ->
            pendingSelectedTab = null
            if (tab != IBottomNavigationView.ID_HOME) bottomNavigationView.selectedItemId = tab
        }
        updateTopAvatar()
        setSearchChromeVisible(shouldShowSearch(initialTab))
        adoptPendingSearchText()
        view.post {
            activeNavigationController?.insetsUpdated()
            // preload other tabs
            if (AppTabsManager.contains(IBottomNavigationView.ID_EXPLORE)) {
                getNavigationStack(IBottomNavigationView.ID_EXPLORE)
            }
            if (!experimentalTopTabsEnabled) {
                getNavigationStack(IBottomNavigationView.ID_SETTINGS)
            }
        }

        if (!experimentalTopTabsEnabled) {
            bottomNavigationView.post {
                setupWalletSwitcherPopup()
            }
        }
        updateToastAvailability()
        checkForUpdate()
        updateTheme()
        precacheReceiveBackground()
    }

    private fun setupWalletSwitcherPopup() {
        val settingsItemView = bottomNavigationView.getSettingsItemView() ?: return
        settingsItemView.setOnLongClickListener { settingsItemView ->
            presentWalletSwitcherPopup(settingsItemView, WMenuPopup.Positioning.ABOVE)
        }
    }

    private fun presentWalletSwitcherPopup(
        anchorView: View,
        positioning: WMenuPopup.Positioning
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
        )
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
        )
        val freeSpaceToShowAccounts = if (positioning == WMenuPopup.Positioning.BELOW) {
            view.height -
                anchorView.bottom -
                (navigationController?.getSystemBars()?.bottom ?: 0) -
                110.dp
        } else {
            view.height -
                (navigationController?.getSystemBars()?.top ?: 0) -
                WNavigationBar.DEFAULT_HEIGHT.dp -
                bottomNavigationView.height -
                110.dp
        }

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
                    )
                } +
                listOf(addAccountItem)

        popup = WMenuPopup.present(
            view = anchorView,
            items = menuItems,
            yOffset = if (positioning == WMenuPopup.Positioning.BELOW) (-3).dp else 3.dp,
            positioning = positioning,
            centerHorizontally = true,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                anchorView,
                roundRadius = 100f.dp,
                horizontalOffset = 0,
                verticalOffset = if (positioning == WMenuPopup.Positioning.BELOW) 0 else (-4).dp
            )
        )
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
        if (experimentalTopTabsEnabled) {
            navStacks.forEach { nav ->
                if (nav === activeNavigationController) return@forEach
                nav.updateTheme()
                nav.viewControllers.lastOrNull()?.applyThemeChanges()
            }
        }
    }

    override val isTinted = true
    override fun updateTheme() {
        super.updateTheme()

        val tintColor = WColor.Tint.color

        if (experimentalTopTabsEnabled) {
            updateActionsButtonMorph()
        }

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
        if (experimentalTopTabsEnabled) {
            topTabsControl.setBackgroundColor(
                Color.TRANSPARENT,
                TOP_TABS_HEIGHT.dp / 2f,
                clipToBounds = true
            )
            topTabsGlass?.updateTheme()
            topAvatarGlass?.updateTheme()
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
        }
        updateBottomNavigationBackground()
        updateExperimentalSearchPosition()

        searchEditText.highlightColor = tintColor.colorWithAlpha(51)
        isProcessingSearchKeyword = true
        checkForMatchingUrl(searchKeyword)
        isProcessingSearchKeyword = false

        render()
    }

    override fun viewWillAppear() {
        if (experimentalTopTabsEnabled && isDisappeared && !isKeyboardOpen) {
            keyboardVisible.forcedValue = 0f
        }
        super.viewWillAppear()
        activeNavigationController?.viewWillAppear()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        activeNavigationController?.viewDidAppear()
        updateToastAvailability()
        // Re-host any full-screen VCs carried over from the tablet container, now that this VC is the
        // root of the window nav (which is the phone's main navigation controller).
        val tabToPresentOverMain = pendingTabToPresentOverMain
        if (tabToPresentOverMain != null) {
            pendingTabToPresentOverMain = null
            val stack = detachNavigationStack(tabToPresentOverMain).ifEmpty {
                listOf(
                    when (tabToPresentOverMain) {
                        IBottomNavigationView.ID_AGENT -> AgentVC(context)
                        else -> SettingsVC(context)
                    }
                )
            }
            adoptPushedOverMain(stack + takePendingPushedOverMain())
        } else {
            adoptPendingPushedOverMain()
        }
    }

    override fun selectedTabForExport(selectedItemId: Int): Int {
        if (!experimentalTopTabsEnabled) return selectedItemId
        val pushedRoot = navigationController?.viewControllers?.getOrNull(1)
        return when (pushedRoot) {
            is SettingsVC -> IBottomNavigationView.ID_SETTINGS
            is AgentVC -> IBottomNavigationView.ID_AGENT
            else -> selectedItemId
        }
    }

    // Full-screen pushes on phone live in the window nav, above this PhoneTabsVC root.
    override fun exportPushedOverMain(): List<WViewController> {
        val pushed = navigationController?.detachAboveRoot() ?: return emptyList()
        val tabId = if (experimentalTopTabsEnabled) {
            when (pushed.firstOrNull()) {
                is SettingsVC -> IBottomNavigationView.ID_SETTINGS
                is AgentVC -> IBottomNavigationView.ID_AGENT
                else -> null
            }
        } else {
            null
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
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        activeNavigationController?.viewWillDisappear()
        toastHostView.setToastEnabled(false)
        clearSearchAutoComplete()
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
                bottomTabsHeight -
                (if (minimizedNav != null) 56.dp else 0)
            if (height <= 0) return 0f
            return (height + searchKeyboardLift).toFloat()
        }

    private val searchKeyboardLift: Int
        get() = if (experimentalTopTabsEnabled) {
            (SEARCH_KEYBOARD_GAP.dp - 1.dp - bottomOverlayExtraGap).coerceAtLeast(0)
        } else {
            0
        }

    override fun insetsUpdated() {
        super.insetsUpdated()

        keyboardVisible.animatedValue = keyboardHeight
        onUpdateAdditionalHeight()
        if (!experimentalTopTabsEnabled) bottomNavigationView.insetsUpdated(bottomBarHeight)
        render()
        if (experimentalTopTabsEnabled) {
            updateExperimentalSearchPosition()
        } else {
            searchView.translationY =
                ViewConstants.TOOLBAR_RADIUS.dp - SEARCH_BOTTOM_MARGIN.dp.toFloat()
        }
        updateTopChromeLayout()

        if (!isKeyboardOpen &&
            searchEditText.hasFocus() &&
            cachedExploreVC?.shouldKeepSearchActiveOnKeyboardDismiss != true
        ) {
            searchEditText.clearFocus()
        }
        if (searchMatchedSite != null && !isKeyboardOpen) {
            clearSearchAutoComplete()
        }
        updateSearchWidth()
        updateStickyGradientHeight()
    }

    private val shouldShowStickyBottomGradientView: Boolean
        get() = WGlobalStorage.isGradientNavigationBarActive()

    private val bottomOverlayExtraGap: Int
        get() = if (experimentalTopTabsEnabled && !shouldShowStickyBottomGradientView) {
            EXPERIMENTAL_BOTTOM_EXTRA_GAP.dp
        } else {
            0
        }

    private fun ensureStickyBottomGradientView(): View {
        stickyBottomGradientView?.let { return it }
        val gradientView = View(context).apply {
            id = View.generateViewId()
        }
        stickyBottomGradientView = gradientView
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
        bottomNavigationView.bringToFront()
        if (experimentalTopTabsEnabled && topTabsControl.parent != null) {
            topAvatarGlass?.bringToFront()
            topAvatarView.bringToFront()
            topTabsGlass?.bringToFront()
            topTabsControl.bringToFront()
        }
        if (experimentalTopTabsEnabled) {
            searchOverlayNav?.bringToFront()
            bottomReversedCornerView?.bringToFront()
            stickyBottomGradientView?.bringToFront()
            minimizedNavGlass?.bringToFront()
            minimizedNav?.bringToFront()
            searchGlass?.bringToFront()
            searchView.bringToFront()
            actionsButtonGlass?.bringToFront()
            actionsButton.bringToFront()
            toastHostView.bringToFront()
        }
    }

    private fun stickyGradientFullHeight(): Int = bottomTabsHeight +
        bottomBarHeight +
        (minimizedNavHeight ?: 0f).roundToInt() +
        if (experimentalTopTabsEnabled) {
            (SEARCH_BOTTOM_MARGIN + SEARCH_HEIGHT).dp + stickyGradientKeyboardHeight.roundToInt()
        } else {
            0
        }

    // In top-tabs mode the gradient follows the search bar above the keyboard.
    private val stickyGradientKeyboardHeight: Float
        get() = if (experimentalTopTabsEnabled) keyboardVisible.value.coerceAtLeast(0f) else 0f

    private fun updateStickyGradientHeight() {
        val gradient = stickyBottomGradientView ?: return
        val target = stickyGradientFullHeight()
        val params = gradient.layoutParams ?: return
        if (params.height != target) {
            params.height = target
            gradient.layoutParams = params
        }
        stickyBottomGradientDrawable?.setStops(computeGradientStops(visibilityFraction))
    }

    // The fade always turns solid at the top of the bottom inset. Expanded, it spans the
    // whole chrome above the inset; collapsed, only ADDITIONAL_GRADIENT_HEIGHT above it.
    private fun computeGradientStops(vis: Float): FloatArray {
        val full = stickyGradientFullHeight()
        if (full <= 0) return floatArrayOf(0f, 1f, 1f)
        val solidHeight = (window?.systemBars?.bottom ?: 0) + stickyGradientKeyboardHeight
        val insetRatio = (solidHeight / full).coerceIn(0f, 1f)
        val solidStart = 1f - insetRatio
        val collapsedFadeStart =
            (solidStart - ViewConstants.ADDITIONAL_GRADIENT_HEIGHT.dp / full).coerceIn(0f, 1f)
        return floatArrayOf(
            lerp(collapsedFadeStart, 0f, vis),
            solidStart,
            1f
        )
    }

    private fun updateBottomNavigationBackground(
        selectedItemId: Int = bottomNavigationView.selectedItemId
    ) {
        if (shouldShowStickyBottomGradientView) {
            if (stickyBottomGradientView == null) {
                val gradientView = ensureStickyBottomGradientView()
                view.setConstraints {
                    toBottom(gradientView)
                }
            }
            stickyBackgroundColor =
                if (ThemeManager.isDark && selectedItemId != IBottomNavigationView.ID_AGENT) {
                    WColor.SecondaryBackground.color
                } else {
                    WColor.Background.color
                }
            val drawable = StickyBottomGradientDrawable(
                intArrayOf(
                    stickyBackgroundColor.colorWithAlpha(0),
                    stickyBackgroundColor.colorWithAlpha(GRADIENT_ALPHA),
                    stickyBackgroundColor.colorWithAlpha(GRADIENT_ALPHA)
                )
            )
            drawable.setStops(computeGradientStops(visibilityFraction))
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
        if (!AppTabsManager.contains(IBottomNavigationView.ID_EXPLORE)) return
        navigationController?.popToRoot(false)
        bottomNavigationView.selectedItemId = IBottomNavigationView.ID_EXPLORE
        window?.dismissToRoot()
        targetUri?.let { cachedExploreVC?.findSiteAndOpenTargetUri(it) }
    }

    override fun switchToMarket() {
        navigationController?.popToRoot(false)
        if (!AppTabsManager.contains(IBottomNavigationView.ID_MARKET)) {
            // Market is an optional tab the user may have hidden, and a deeplink must still land
            // on the screen, so push it onto the current stack instead of selecting a missing tab.
            window?.dismissToRoot()
            navigationController?.push(MarketVC(context))
            return
        }
        bottomNavigationView.selectedItemId = IBottomNavigationView.ID_MARKET
        window?.dismissToRoot()
    }

    override fun switchToAgent(prompt: String?, pinnedMessageId: String?): Boolean {
        if (experimentalTopTabsEnabled) {
            navigationController?.popToRoot(false)
            window?.dismissToRoot()
            navigationController?.push(
                AgentVC(
                    context,
                    initialPrompt = prompt,
                    initialPinnedMessageId = pinnedMessageId
                )
            )
            return true
        }
        if (!AppTabsManager.contains(IBottomNavigationView.ID_AGENT)) return false
        navigationController?.popToRoot(false)
        bottomNavigationView.selectedItemId = IBottomNavigationView.ID_AGENT
        window?.dismissToRoot()
        if (!pinnedMessageId.isNullOrBlank()) {
            showAgentMessage(pinnedMessageId)
        } else {
            submitAgentPrompt(prompt)
        }
        return true
    }

    override fun switchToSettings(pushVC: WViewController?) {
        navigationController?.popToRoot(false)
        if (experimentalTopTabsEnabled) {
            window?.dismissToRoot()
            navigationController?.push(SettingsVC(context), animated = pushVC == null)
            pushVC?.let { navigationController?.push(it) }
            return
        }
        bottomNavigationView.selectedItemId = IBottomNavigationView.ID_SETTINGS
        window?.dismissToRoot()
        pushVC?.let {
            navigationController?.push(it)
        }
    }

    override val isOnHomeScreen: Boolean
        get() {
            val homeNavigationController =
                navForOrNull(IBottomNavigationView.ID_HOME) ?: return false
            return bottomNavigationView.selectedItemId == IBottomNavigationView.ID_HOME &&
                window?.topViewController == this &&
                homeNavigationController.viewControllers.size == 1
        }
    override val mainNavigationController: WNavigationController?
        get() = navigationController

    override val activeNavigationController: WNavigationController?
        get() {
            return navForOrNull(bottomNavigationView.selectedItemId)
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
                setPadding(16.dp, 12.dp, 16.dp, 12.dp)
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
                    WRAP_CONTENT
                )
            )
            view.setConstraints {
                if (experimentalTopTabsEnabled) {
                    toBottomPx(
                        button,
                        bottomBarHeight + ViewConstants.GAP.dp
                    )
                } else {
                    bottomToTop(
                        button,
                        bottomNavigationView,
                        ViewConstants.GAP.toFloat()
                    )
                }
                toCenterX(button)
            }
        }
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

    private fun checkForUpdate(selectedItemId: Int = bottomNavigationView.selectedItemId) {
        if (ConfigStore.isAppUpdateRequired == true &&
            !DEBUG_MODE &&
            UPDATE_BUTTON_AVAILABLE_TABS.contains(selectedItemId)
        ) {
            showUpdateButton()
        } else {
            hideUpdateButton()
        }
    }

    var searchMatchedSite: MExploreHistory.VisitedSite? = null
    var searchKeyword = ""
    private fun checkForMatchingUrl(keyword: String) {
        searchKeyword = keyword
        if (keyword.isEmpty()) return
        searchMatchedSite =
            if (!isKeyboardOpen) {
                null
            } else {
                ExploreHistoryStore.exploreHistory?.visitedSites?.firstOrNull {
                    it.url.toUri().host?.startsWith(keyword) == true ||
                        it.url.startsWith(keyword)
                }
            }
        val wasProcessingSearchKeyword = isProcessingSearchKeyword
        isProcessingSearchKeyword = true
        searchEditText.removeAutoCompleteSuffix()
        isProcessingSearchKeyword = wasProcessingSearchKeyword
        searchMatchedSite?.let { matchedSite ->
            val urlPart = matchedSite.url.toUri().let { uri ->
                if (uri.host?.startsWith(keyword) == true) {
                    uri.host
                } else {
                    "${uri.scheme}://${uri.host}"
                }
            }
            val txt = "$urlPart — ${matchedSite.title}"
            if (txt.length <= keyword.length ||
                !txt.startsWith(keyword) ||
                searchEditText.text?.toString() != keyword
            ) {
                return
            }
            val suffix = SpannableString(txt.substring(keyword.length))
            suffix.setSpan(
                ForegroundColorSpan(WColor.Tint.color),
                ((urlPart?.length ?: 0) - keyword.length).coerceIn(0, suffix.length),
                suffix.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            isProcessingSearchKeyword = true
            searchEditText.appendAutoCompleteSuffix(suffix)
            isProcessingSearchKeyword = wasProcessingSearchKeyword
            searchView.post {
                searchView.scrollTo(0, 0)
            }
        }
    }

    private fun clearSearchAutoComplete() {
        searchEditText.removeAutoCompleteSuffix()
        checkForMatchingUrl(searchKeyword)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                updateTopAvatar()
                if (!AccountStore.isPushedTemporary && !walletEvent.isSavingTemporaryAccount) {
                    navigationController?.popToRoot(false)
                }
            }

            is WalletEvent.TemporaryAccountSaved -> {
                updateTopAvatar()
                navigationController?.popToRoot(false)
                ToastHelper.notifyViewWalletAdded(this, accountId = walletEvent.accountId)
            }

            is WalletEvent.AccountChangedInApp, WalletEvent.AddNewWalletCompletion -> {
                updateTopAvatar()
                if (bottomNavigationView.selectedItemId != IBottomNavigationView.ID_HOME) {
                    bottomNavigationView.selectedItemId = IBottomNavigationView.ID_HOME
                }
                dismissMinimized(false)
            }

            is WalletEvent.ConfigReceived -> {
                checkForUpdate()
            }

            WalletEvent.AppTabsChanged -> {
                if (!AppTabsManager.contains(bottomNavigationView.selectedItemId)) {
                    bottomNavigationView.selectedItemId = IBottomNavigationView.ID_HOME
                }
                bottomNavigationView.reloadTabs()
                reloadTopTabs()
            }

            else -> {
                routeWalletEvent(walletEvent)
            }
        }
    }

    private var visibilityFraction = 1f
    private var visibilityTarget = 1f
    private var activeVisibilityValueAnimator: ValueAnimator? = null
    override fun scrollingUp() {
        if (experimentalTopTabsEnabled) return
        if (visibilityTarget == 1f) return
        bottomNavigationView.setTabsEnabled(true)
        activeVisibilityValueAnimator?.cancel()
        activeVisibilityValueAnimator = ValueAnimator.ofFloat(visibilityFraction, 1f).apply {
            duration =
                (AnimationConstants.VERY_QUICK_ANIMATION * (1f - visibilityFraction)).toLong()
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                visibilityFraction = animatedValue as Float
                render()
            }
            visibilityTarget = 1f
            start()
        }
    }

    override fun scrollingDown() {
        if (experimentalTopTabsEnabled) return
        if (visibilityTarget == 0f) return
        bottomNavigationView.setTabsEnabled(false)
        activeVisibilityValueAnimator?.cancel()
        activeVisibilityValueAnimator = ValueAnimator.ofFloat(visibilityFraction, 0f).apply {
            duration =
                (AnimationConstants.VERY_QUICK_ANIMATION * visibilityFraction).toLong()
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                visibilityFraction = animatedValue as Float
                render()
            }
            visibilityTarget = 0f
            start()
        }
    }

    override fun onBackPressed(): Boolean {
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
        val keyboard = keyboardHeight
        val minimizedNavHeight = minimizedNavHeight ?: 0f
        val selectedItemId = selectingTabId ?: bottomNavigationView.selectedItemId
        val isSearchOverlayingContent = experimentalTopTabsEnabled ||
            selectedItemId == IBottomNavigationView.ID_EXPLORE
        val additionalHeight =
            (
                (
                    if (isSearchOverlayingContent) {
                        (
                            SEARCH_BOTTOM_MARGIN + SEARCH_HEIGHT +
                                SEARCH_TOP_MARGIN
                            ).dp
                    } else {
                        0
                    }
                    ) +
                    keyboard +
                    minimizedNavHeight
                ).roundToInt()
        return bottomTabsHeight + additionalHeight + bottomBarHeight + bottomOverlayExtraGap
    }

    private fun shouldShowSearch(tabId: Int): Boolean =
        experimentalTopTabsEnabled || tabId == IBottomNavigationView.ID_EXPLORE

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
            if (!experimentalTopTabsEnabled) return null
            searchOverlayNav?.let { return it }
            val window = window ?: return null
            val nav = WNavigationController(window)
            nav.tabBarController = this
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
        experimentalTabPager.isUserInputEnabled = false
        topTabsControl.isEnabled = false
        topAvatarView.isEnabled = false
        nav.fadeIn(SEARCH_OVERLAY_ANIMATION)
        fadeTopChromeForSearch(visible = false)
    }

    override fun hideSearchOverlay() {
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
            experimentalTabPager.isUserInputEnabled = true
            topTabsControl.isEnabled = true
            topAvatarView.isEnabled = true
        }
        // Keep the search screen on-screen through the fade, then tear the stack down. Touches are
        // blocked meanwhile so the outgoing layer cannot swallow taps meant for what is behind it.
        nav.blockTouches()
        nav.fadeOut(SEARCH_OVERLAY_ANIMATION) {
            nav.viewControllers.forEach { it.viewWillDisappear() }
            nav.onDestroy()
            view.removeView(nav)
        }
        fadeTopChromeForSearch(visible = true)
    }

    private fun fadeTopChromeForSearch(visible: Boolean) {
        val showTabs = visible &&
            !isTopChromeHidden &&
            bottomNavigationView.selectedItemId != IBottomNavigationView.ID_SETTINGS
        val showAvatar = showTabs && AccountStore.activeAccount != null
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
        if (cachedExploreVC == null && AppTabsManager.contains(IBottomNavigationView.ID_EXPLORE)) {
            getNavigationStack(IBottomNavigationView.ID_EXPLORE)
        }
        val exploreVC = cachedExploreVC ?: return
        if (experimentalTopTabsEnabled) {
            exploreVC.search(
                query,
                focused,
                targetNavigationController = searchOverlayNavigationController,
                isGlobalSearch = true
            )
        } else {
            exploreVC.search(query, focused)
        }
    }

    private var minimizedNav: WNavigationController? = null
    private var minimizedNavHeight: Float? = null
    private var minimizedNavY: Float? = null
    private var minimizedNavGlass: WGlassView? = null

    private fun attachMinimizedShadow(nav: WNavigationController) {
        nav.elevation = 0f
        if (minimizedNavGlass == null) {
            minimizedNavGlass = WGlassView(context).also {
                it.alpha = 0f
                it.glassPadding = WGlassView.GLASS_PADDING_DP.dp
                it.setProvider(GlassProviders.shadowOnly())
                view.addView(it, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
                minimizedNav?.bringToFront()
            }
        }
    }

    private fun detachMinimizedShadow(nav: WNavigationController?) {
        minimizedNavGlass?.let { view.removeView(it) }
        minimizedNavGlass = null
        nav?.elevation = 0f
    }

    private fun applyMinimizedShadowProgress(
        nav: WNavigationController,
        fraction: Float,
        width: Int,
        height: Int,
        radius: Float
    ) {
        val shadow = minimizedNavGlass
        if (shadow != null) {
            shadow.alpha = fraction
            val l = nav.left + nav.translationX
            val t = nav.top + nav.translationY
            shadow.setTargetRect(l, t, l + width, t + height, radius)
        } else {
            nav.elevation = fraction * 1.5f.dp
        }
    }

    private var onMaximizeProgress: ((progress: Float) -> Unit)? = null
    override fun minimize(
        nav: WNavigationController,
        onProgress: (progress: Float) -> Unit,
        onMaximizeProgress: (progress: Float) -> Unit
    ) {
        if (window?.navigationControllers?.lastOrNull() != nav) {
            onMaximizeProgress(1f)
            return
        }
        if (minimizedNav != null) dismissMinimized(false)
        this.onMaximizeProgress = onMaximizeProgress
        minimizedNav = nav
        nav.window.detachLastNav()
        attachMinimizedShadow(nav)
        view.addView(nav)
        if (experimentalTopTabsEnabled) restackChromeAboveGradient()
        val initialHeight = nav.height
        val finalHeight = 48.dp
        val initialWidth = nav.width
        val customFinalWidth =
            if (experimentalTopTabsEnabled) null else bottomNavigationView.getMinimizedWidth()
        val finalWidth = customFinalWidth ?: (initialWidth - 20.dp)
        val finalTranslationX =
            if (customFinalWidth != null) (initialWidth - finalWidth) / 2f else 10.dp.toFloat()
        val containerHeight = view.height.takeIf { it > 0 }
            ?: (window?.windowView?.height ?: 0)
        val finalY = containerHeight -
            bottomBarHeight -
            finalHeight - 4.dp - bottomOverlayExtraGap
        val finalMinimizedNavHeight = finalHeight + 8f.dp
        minimizedNavHeight = if (experimentalTopTabsEnabled) 0f else finalMinimizedNavHeight
        updateStickyGradientHeight()
        bottomNavigationView.translationY =
            -(BOTTOM_TABS_BOTTOM_MARGIN.dp + bottomBarHeight + finalMinimizedNavHeight) +
            BOTTOM_TABS_BOTTOM_TO_NAV_DIFF.dp
        syncToastHostPosition()
        render()

        fun onUpdate(animatedFraction: Float) {
            if (experimentalTopTabsEnabled) {
                minimizedNavHeight = animatedFraction * finalMinimizedNavHeight
                updateStickyGradientHeight()
                render()
            }
            val navY = animatedFraction * finalY
            minimizedNavY = navY
            nav.translationY = navY
            val animatedHeight = finalHeight +
                ((initialHeight - finalHeight) * (1 - animatedFraction)).roundToInt()
            val animatedWidth = finalWidth +
                ((initialWidth - finalWidth) * (1 - animatedFraction)).roundToInt()
            nav.layoutParams = nav.layoutParams.apply {
                onProgress(animatedFraction)
                height = animatedHeight
                width = animatedWidth
            }
            nav.translationX = animatedFraction * finalTranslationX
            val radius = 24.dp * animatedFraction
            nav.setBackgroundColor(Color.TRANSPARENT, radius, true)
            applyMinimizedShadowProgress(
                nav,
                animatedFraction,
                animatedWidth,
                animatedHeight,
                radius
            )
        }

        if (WGlobalStorage.getAreAnimationsActive()) {
            ValueAnimator.ofInt(0, 1)
                .apply {
                    duration = AnimationConstants.VERY_VERY_QUICK_ANIMATION
                    interpolator = AccelerateDecelerateInterpolator()

                    addUpdateListener {
                        onUpdate(animatedFraction)
                    }

                    start()
                }
        } else {
            onUpdate(1f)
        }
    }

    override fun maximize() {
        maximize(animated = WGlobalStorage.getAreAnimationsActive())
    }

    fun maximize(animated: Boolean) {
        val nav = minimizedNav ?: return
        this.minimizedNav = null
        val initialHeight = nav.height
        val finalHeight = view.height
        val initialWidth = nav.width
        val finalWidth = view.width
        val initialY = nav.y
        val initialMinimizedNavHeight = minimizedNavHeight ?: 0f
        val minimizedNavTranslationX = nav.translationX

        fun onUpdate(animatedFraction: Float) {
            if (experimentalTopTabsEnabled) {
                minimizedNavHeight = (1 - animatedFraction) * initialMinimizedNavHeight
                updateStickyGradientHeight()
                render()
            }
            onMaximizeProgress?.invoke(animatedFraction)
            val topY = (1 - animatedFraction) * initialY
            nav.translationY = topY
            val animatedHeight = finalHeight +
                ((initialHeight - finalHeight) * (1 - animatedFraction)).roundToInt()
            val animatedWidth = finalWidth +
                ((initialWidth - finalWidth) * (1 - animatedFraction)).roundToInt()
            nav.layoutParams = nav.layoutParams.apply {
                height = animatedHeight
                width = animatedWidth
            }
            nav.translationX = (1 - animatedFraction) * minimizedNavTranslationX
            val radius = 24.dp * (1 - animatedFraction)
            nav.setBackgroundColor(Color.TRANSPARENT, radius, radius > 0f)
            applyMinimizedShadowProgress(
                nav,
                1f - animatedFraction,
                animatedWidth,
                animatedHeight,
                radius
            )
        }

        fun onEnd() {
            minimizedNavHeight = 0f
            updateStickyGradientHeight()
            bottomNavigationView.translationY =
                -(BOTTOM_TABS_BOTTOM_MARGIN.dp + bottomBarHeight + minimizedNavHeight!!)
            syncToastHostPosition()
            render()
            detachMinimizedShadow(nav)
            view.removeView(nav)
            window?.attachNavigationController(nav)
        }

        if (animated) {
            ValueAnimator.ofInt(0, 1)
                .apply {
                    duration = AnimationConstants.VERY_VERY_QUICK_ANIMATION
                    interpolator = AccelerateDecelerateInterpolator()

                    onMaximizeProgress?.invoke(0f)
                    addUpdateListener {
                        onUpdate(animatedFraction)
                    }

                    doOnEnd {
                        onEnd()
                    }

                    start()
                }
        } else {
            onMaximizeProgress?.invoke(0f)
            onUpdate(1f)
            onEnd()
        }
    }

    override fun dismissMinimized(animated: Boolean) {
        val nav = minimizedNav ?: return
        val initialMinimizedNavHeight = if (experimentalTopTabsEnabled) {
            minimizedNavHeight ?: 0f
        } else {
            48.dp.toFloat()
        }

        fun onUpdate(animatedFraction: Float) {
            minimizedNavHeight = (1 - animatedFraction) * initialMinimizedNavHeight
            updateStickyGradientHeight()
            bottomNavigationView.translationY =
                -(BOTTOM_TABS_BOTTOM_MARGIN.dp + bottomBarHeight + minimizedNavHeight!!) +
                BOTTOM_TABS_BOTTOM_TO_NAV_DIFF.dp * (1 - animatedFraction)
            syncToastHostPosition()
            render()
            val fadedAlpha = visibilityFraction * (1 - animatedFraction)
            nav.alpha = fadedAlpha
            minimizedNavGlass?.alpha = fadedAlpha
        }

        fun onEnd() {
            if (minimizedNav !== nav) return
            nav.willBeDismissed()
            detachMinimizedShadow(nav)
            view.removeView(nav)
            nav.onDestroy()
            minimizedNav = null
            minimizedNavY = null
        }
        if (!animated) {
            onUpdate(1f)
            onEnd()
            return
        }
        ValueAnimator.ofInt(0, 1)
            .apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION
                interpolator = DecelerateInterpolator()

                addUpdateListener {
                    onUpdate(animatedFraction)
                }
                doOnEnd {
                    onEnd()
                }

                start()
            }
    }

    override fun setSearchText(text: String) {
        searchView.requestFocus()
        searchEditText.setText(text)
    }

    override fun clearSearchFocus() {
        // hideKeyboard() drops focus too. Clearing focus alone would leave the IME up, so the
        // search screen popped out from behind a keyboard with nothing left to type into.
        searchEditText.hideKeyboard()
    }

    override fun switchToFirstTab(): Boolean {
        if (bottomNavigationView.selectedItemId != IBottomNavigationView.ID_HOME) {
            bottomNavigationView.selectedItemId = IBottomNavigationView.ID_HOME
            return true
        }
        return false
    }

    override fun hideTabBar() {
        if (experimentalTopTabsEnabled) {
            if (isTopChromeHidden) return
            isTopChromeHidden = true
            experimentalTabPager.isUserInputEnabled = false
            topTabsControl.isEnabled = false
            topAvatarView.isEnabled = false
            hideTopChromeView(topTabsControl)
            hideTopChromeView(topAvatarView)
        } else {
            bottomNavigationView.fadeOut()
        }
    }

    override fun showTabBar() {
        if (experimentalTopTabsEnabled) {
            if (!isTopChromeHidden) return
            isTopChromeHidden = false
            experimentalTabPager.isUserInputEnabled = true
            topTabsControl.isEnabled = true
            topAvatarView.isEnabled = true
            val shouldShowTabs =
                bottomNavigationView.selectedItemId != IBottomNavigationView.ID_SETTINGS
            val shouldShowAvatar = shouldShowTabs && AccountStore.activeAccount != null
            showTopChromeView(topTabsControl, shouldShowTabs)
            showTopChromeView(topAvatarView, shouldShowAvatar)
        } else {
            bottomNavigationView.fadeIn()
        }
    }

    private fun updateToastAvailability(selectedItemId: Int = bottomNavigationView.selectedItemId) {
        val homeNavigationController = navForOrNull(IBottomNavigationView.ID_HOME)
        val isMainHomeVisible =
            selectedItemId == IBottomNavigationView.ID_HOME &&
                window?.topViewController == this &&
                homeNavigationController?.viewControllers?.size == 1

        toastHostView.setToastEnabled(isMainHomeVisible)
    }

    private fun syncToastHostPosition() {
        toastHostView.translationY = if (experimentalTopTabsEnabled) {
            -(searchTopOffset() + ViewConstants.GAP.dp - TOAST_HOST_BOTTOM_MARGIN.dp)
        } else {
            bottomNavigationView.translationY + ViewConstants.TOOLBAR_RADIUS.dp
        }
    }

    // Distance from the container bottom to the top edge of the search bar.
    private fun searchTopOffset(): Float = bottomBarHeight +
        keyboardVisible.value.coerceAtLeast(0f) +
        (minimizedNavHeight ?: 0f) +
        3.dp + bottomOverlayExtraGap +
        SEARCH_HEIGHT.dp

    override fun onDestroy() {
        super.onDestroy()
        HomeStatusController.removeListener(topAvatarStatusListener)
        minimizedNav?.let { nav ->
            nav.willBeDismissed()
            detachMinimizedShadow(nav)
            view.removeView(nav)
            nav.onDestroy()
        }
        minimizedNav = null
        searchOverlayNav?.let { nav ->
            nav.viewControllers.forEach { it.viewWillDisappear() }
            view.removeView(nav)
            nav.onDestroy()
        }
        searchOverlayNav = null
        onMaximizeProgress = null
        bottomNavigationView.listener = null
    }
}
