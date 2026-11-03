package org.mytonwallet.uihome.tabs

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.InsetDrawable
import android.net.Uri
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.net.toUri
import androidx.core.view.children
import androidx.core.view.doOnLayout
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import kotlin.math.roundToInt
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.FloatAnimator
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
import org.mytonwallet.app_air.uicomponents.commonViews.UpdateStatusView
import org.mytonwallet.app_air.uicomponents.commonViews.toast.ToastHost
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.drawable.StickyBottomGradientDrawable
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setupSpringFling
import org.mytonwallet.app_air.uicomponents.extensions.springToItem
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.HomeStatusController
import org.mytonwallet.app_air.uicomponents.helpers.RevealUpdates
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
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketVC
import org.mytonwallet.app_air.uisettings.viewControllers.settings.SettingsVC
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
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
        private const val ACTIONS_BUTTON_GAP = 12
        private const val ACTIONS_ICON_SIZE = 18

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

    private val contentView = WView(context)

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

    private fun selectTab(itemId: Int) {
        if (selectedTabId == itemId) {
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

        switchTab(itemId, oldNav, newNav)
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
                springingTabId == null && pendingTabAppearance == null &&
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
                    revealPage(position)
                    if (positionOffset > 0f) revealPage(position + 1)
                    // The Agent list's bar is hosted as soon as its page can show
                    val list = findAgentList()
                    if (list != null && list.barHost == null) updateAgentBar(isInstant = true)
                    topTabsControl.updateThumbPosition(
                        index = position,
                        offset = position + positionOffset,
                        targetIndex = currentItem,
                        force = false,
                        isAnimatingToPosition = false
                    )
                    keepAgentBarOnToolbar()
                }

                override fun onPageSelected(position: Int) {
                    commitPage(position)
                }

                override fun onPageScrollStateChanged(state: Int) {
                    // The finger or the pager took over from a tapped tab's slide
                    springingTabId = null
                    if (state != ViewPager2.SCROLL_STATE_IDLE) return
                    val index = currentItem
                    topTabsControl.updateThumbPosition(
                        index = index,
                        offset = index.toFloat(),
                        targetIndex = index,
                        force = true,
                        isAnimatingToPosition = false
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
        val previousIndex = tabPager.currentItem
        // The pages the slide passes over are mounted before it starts, so it runs without a pause
        for (page in minOf(previousIndex, index)..maxOf(previousIndex, index)) revealPage(page)
        val animated = WGlobalStorage.getAreAnimationsActive()
        if (animated && previousIndex != index && tabPager.width > 0) {
            springingTabId = itemId
            tabPager.springToItem(index) {
                if (springingTabId == itemId) springingTabId = null
                completePendingTabAppearance()
            }
        } else {
            tabPager.setCurrentItem(index, false)
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
        }
    }
    private var topTabsGlass: WGlassView? = null

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
    private var topAvatarAccountId: String? = null
    private val topAvatarView by lazy {
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
            setOnLongClickListener { presentWalletSwitcherPopup(it) }
        }
    }
    private var topAvatarGlass: WGlassView? = null
    private var isTopChromeHidden = false

    private fun reloadTopTabs(selectedItemId: Int = selectedTabId) {
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
        val shouldShowAvatar = shouldShowTabs && AccountStore.permanentActiveAccount != null
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
        val account = AccountStore.permanentActiveAccount
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

    private val topChromeBlurViews
        get() = listOfNotNull(searchGlass, actionsButtonGlass, topTabsGlass, topAvatarGlass)
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
    private var actionsButtonGlass: WGlassView? = null
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
            HomeActionsSheetVC(context) { identifier ->
                homeVC.onHeaderAction(identifier)
            }
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
        actionsButton.alpha = 1f
        actionsButton.isVisible = shouldShow
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
            circleButton = agentCircleButton,
            fullSearchWidth = {
                val margin = (ViewConstants.HORIZONTAL_PADDINGS + 6).dp
                view.width - 2 * margin - SEARCH_HEIGHT.dp - ACTIONS_BUTTON_GAP.dp
            },
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
        agentBarMorph.setTargets(isAgent, isCovered, list?.isComposing == true, !shouldJump)
        // Whether the toolbar shows decides its line
        updateSearchPosition()
        showSearchChrome()
        if (selectedTabId == AppTabsManager.ID_AGENT) {
            updateTopChromeVisibility(selectedTabId)
            // Paging waits while a question is written
            tabPager.isUserInputEnabled = !isTopChromeHidden && list?.isComposing != true &&
                shouldShowPhoneTopTabs(AppTabsManager.ID_AGENT, agentDepth)
        }
    }

    private fun updateAgentChrome() {
        tabPager.isUserInputEnabled = !isTopChromeHidden && shouldShowPhoneTopTabs(
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
        view.addView(searchView, ConstraintLayout.LayoutParams(0, SEARCH_HEIGHT.dp))
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
        view.addView(
            actionsButton,
            ConstraintLayout.LayoutParams(SEARCH_HEIGHT.dp, SEARCH_HEIGHT.dp)
        )
        actionsButtonGlass = WGlassView.attachTo(
            actionsButton,
            SEARCH_HEIGHT.dp / 2f,
            GlassProviders.pill(WColor.SearchFieldBackground),
            root = contentView
        )
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
            toStart(searchView, searchHorizontalMargin)
            endToStart(searchView, actionsButton, ACTIONS_BUTTON_GAP.toFloat())
            toBottom(searchView)
            // Shrunk into the Agent bar's search circle, the field keeps to its leading edge
            setHorizontalBias(searchView.id, 0f)
            toStart(agentCircleButton, searchHorizontalMargin)
            toBottom(agentCircleButton)
            toEnd(actionsButton, searchHorizontalMargin)
            toBottom(actionsButton)
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

        val initialTab = pendingSelectedTab ?: AppTabsManager.ID_HOME
        reloadTopTabs(initialTab)
        contentView.addView(
            tabPager,
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        pendingSelectedTab?.let { tab ->
            pendingSelectedTab = null
            if (tab != AppTabsManager.ID_HOME) selectTab(tab)
        }
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

    private fun presentWalletSwitcherPopup(anchorView: View): Boolean {
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
        val freeSpaceToShowAccounts = view.height -
            anchorView.bottom -
            (navigationController?.getSystemBars()?.bottom ?: 0) -
            110.dp

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
            yOffset = (-3).dp,
            positioning = WMenuPopup.Positioning.BELOW,
            backdropStyle = WMenuPopup.BackdropStyle.BlurDimmed,
            centerHorizontally = true,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                anchorView,
                roundRadius = 100f.dp,
                horizontalOffset = 0,
                verticalOffset = 0
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
        navStacks.forEach { nav ->
            if (nav === activeNavigationController) return@forEach
            nav.updateTheme()
            nav.viewControllers.lastOrNull()?.applyThemeChanges()
        }
    }

    override val isTinted = true
    override fun updateTheme() {
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
        actionsButtonGlass?.updateTheme()
        actionsButtonRipple.rippleColor = WColor.BackgroundRipple.color
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
        actionsButtonGlass?.bringToFront()
        actionsButton.bringToFront()
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
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                updateTopAvatar()
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
                updateTopAvatar()
                if (selectedTabId != AppTabsManager.ID_HOME) {
                    selectTab(AppTabsManager.ID_HOME)
                }
                window?.minimizedBrowser?.dismissAll()
            }

            is WalletEvent.ConfigReceived -> {
                checkForUpdate()
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
            tabPager.isUserInputEnabled = shouldShowPhoneTopTabs(
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
        val showTabs = visible &&
            !isTopChromeHidden &&
            shouldShowPhoneTopTabs(
                selectedTabId,
                activeNavigationController?.viewControllers?.size ?: 1
            )
        val showAvatar = showTabs && AccountStore.permanentActiveAccount != null
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

    override fun switchToFirstTab(): Boolean {
        if (selectedTabId != AppTabsManager.ID_HOME) {
            selectTab(AppTabsManager.ID_HOME)
            return true
        }
        return false
    }

    override fun hideTabBar() {
        if (isTopChromeHidden) return
        isTopChromeHidden = true
        tabPager.isUserInputEnabled = false
        topTabsControl.isEnabled = false
        topAvatarView.isEnabled = false
        hideTopChromeView(topTabsControl)
        hideTopChromeView(topAvatarView)
    }

    override fun showTabBar() {
        if (!isTopChromeHidden) return
        isTopChromeHidden = false
        tabPager.isUserInputEnabled = shouldShowPhoneTopTabs(
            selectedTabId,
            activeNavigationController?.viewControllers?.size ?: 1
        )
        topTabsControl.isEnabled = true
        topAvatarView.isEnabled = true
        val shouldShowTabs = shouldShowPhoneTopTabs(
            selectedTabId,
            activeNavigationController?.viewControllers?.size ?: 1
        )
        val shouldShowAvatar = shouldShowTabs && AccountStore.permanentActiveAccount != null
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
