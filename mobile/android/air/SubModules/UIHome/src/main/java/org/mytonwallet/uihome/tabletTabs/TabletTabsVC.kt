package org.mytonwallet.uihome.tabletTabs

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.net.Uri
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewTreeObserver
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import androidx.core.view.doOnPreDraw
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import kotlin.math.abs
import kotlin.math.roundToInt
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import me.vkryl.android.animatorx.FloatAnimator
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.StickyBottomGradientDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.HomeStatusController
import org.mytonwallet.app_air.uicomponents.helpers.OverlappedChromeFader
import org.mytonwallet.app_air.uicomponents.helpers.frameInWindow
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.uifutures.viewControllers.futures.FuturesVC
import org.mytonwallet.app_air.uimarket.viewControllers.market.MarketVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.PerpsAvailability
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.uihome.home.HomeVC
import org.mytonwallet.uihome.home.views.header.HomeHeaderView
import org.mytonwallet.uihome.tabletTabs.views.TabletSidePanelView
import org.mytonwallet.uihome.tabs.AppTabsManager
import org.mytonwallet.uihome.tabs.BaseTabsVC
import org.mytonwallet.uihome.tabs.PhoneTabsVC
import org.mytonwallet.uihome.tabs.views.HomeSearchField
import org.mytonwallet.uihome.walletsTabs.WalletsTabsVC

@SuppressLint("ViewConstructor")
class TabletTabsVC(context: Context) :
    BaseTabsVC(context),
    WThemedView,
    WalletCore.EventObserver {
    @Suppress("PropertyName")
    override val TAG = "TabletTabs"

    override val shouldDisplayTopBar = false
    override val ignoreSideGuttering = true
    override val isSwipeBackAllowed = false

    companion object {
        const val DEFAULT_PANEL_WIDTH = 360
        const val MIN_PANEL_WIDTH = 270
        const val MAX_PANEL_WIDTH = 360
        private const val RESIZE_HANDLE_WIDTH = 24
        private const val BOTTOM_GRADIENT_ALPHA = 229

        internal const val SEARCH_TOP_MARGIN = 8
        private const val ACCESSORY_GAP = 8
        private const val SEARCH_BOTTOM_MARGIN = 1
        private const val SEARCH_BOTTOM_EXTRA_GAP = 7
        private const val SEARCH_KEYBOARD_GAP = 12

        private fun buildTabDefs() = AppTabsManager.orderedTabs.map {
            TabletSidePanelView.TabDef(it.intId, it.iconRes, it.filledIconRes, it.labelKey)
        }
    }

    // The app opens on the first tab in the user's order
    override var currentTabId: Int = firstTabId

    private val firstTabId: Int
        get() = AppTabsManager.orderedTabs.firstOrNull()?.intId ?: AppTabsManager.ID_HOME

    // The content panel hosts a single navigation controller (the tablet main nav). Its root is a
    // host VC that shows the active per-tab stack; full-screen pushes stack above it.
    private val contentHostVC = TabletContentHostVC(context)
    private val contentNav by lazy {
        WNavigationController(window!!).apply {
            tabBarController = this@TabletTabsVC
            setRoot(contentHostVC)
        }
    }

    override fun detachMountedStacks() {
        // The Agent list's search closes with this container, which the phone layout does not take over
        finishAgentSearch()
        contentHostVC.detachContent()
        (contentNav.parent as? ViewGroup)?.removeView(contentNav)
    }

    private val sidePanel by lazy {
        TabletSidePanelView(
            viewController = this,
            tabDefs = buildTabDefs(),
            onTabSelected = { id -> selectTab(id) },
            onTabReselected = { id ->
                if ((mainNavigationController?.viewControllers?.size ?: 0) > 1) {
                    mainNavigationController?.popToRoot()
                }
                navForOrNull(id)?.apply {
                    if (viewControllers.size == 1) scrollToTop() else popToRoot()
                }
            },
            onTabsReordered = { intIds ->
                val ids = intIds.mapNotNull { intId ->
                    AppTabsManager.registeredTabs.firstOrNull { it.intId == intId }?.id
                }
                AppTabsManager.reorderTabs(ids)
            },
            onAccountSelected = { account -> onAccountSelected(account) },
            onWalletSettings = { presentWalletSettings() },
            onAddAccount = { presentAddAccount() },
            onHeaderSwipe = { progress, verticalOffset, actionsFadeInPercent ->
                homeVCInRightPanel()?.applyHorizontalSwipe(
                    progress,
                    verticalOffset,
                    actionsFadeInPercent
                )
            }
        )
    }
    private var pillShadow: WGlassView? = null
    private val headerView: HomeHeaderView get() = sidePanel.headerView
    private val contentPanel = WFrameLayout(context)
    private val bottomGradientView = View(context).apply { id = View.generateViewId() }
    private var bottomGradientDrawable: StickyBottomGradientDrawable? = null
    private var bottomGradientColor = 0

    private var searchGlass: WGlassView? = null
    private val searchField by lazy {
        HomeSearchField(
            context,
            onSearch = { query, focused -> updateSearch(query, focused) },
            onSubmit = { field -> submitExploreSearch(field) }
        ).apply {
            id = View.generateViewId()
        }
    }

    private val searchKeyboardLift =
        FloatAnimator(220L, AnimatorUtils.DECELERATE_INTERPOLATOR, 0f) {
            updateSearchFieldPosition()
        }

    private val minimizedBrowserDock = BoolAnimator(
        AnimationConstants.VERY_VERY_QUICK_ANIMATION,
        AccelerateDecelerateInterpolator()
    ) { _, _, _, _ ->
        view.invalidate()
    }

    private val searchCover = View(context).apply {
        id = View.generateViewId()
        alpha = 0f
        isVisible = false
        setOnClickListener { closeSearch() }
    }

    private var panelWidth =
        (
            (WGlobalStorage.getTabletPanelWidth() ?: DEFAULT_PANEL_WIDTH)
                .coerceIn(MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)
            ).dp

    private var dragStartRawX = 0f
    private var dragStartY = 0f
    private var dragStartWidth = 0
    private var isResizing = false
    private var resizeRejected = false
    private var forwardTarget: View? = null

    @SuppressLint("ClickableViewAccessibility")
    private val resizeHandle = View(context).apply {
        id = View.generateViewId()
        val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        setOnTouchListener { handle, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    isResizing = false
                    resizeRejected = false
                    dragStartRawX = event.rawX
                    dragStartY = event.y
                    dragStartWidth = sidePanel.width
                    forwardTarget =
                        if (handle.x + event.x >= sidePanel.x + sidePanel.width) {
                            contentPanel
                        } else {
                            sidePanel
                        }
                    forwardTouch(handle, event)
                }

                MotionEvent.ACTION_MOVE -> {
                    if (!isResizing && !resizeRejected) {
                        val dx = abs(event.rawX - dragStartRawX)
                        val dy = abs(event.y - dragStartY)
                        if (dy > touchSlop && dy > dx) {
                            resizeRejected = true
                        } else if (dx > touchSlop && dx > dy) {
                            isResizing = true
                            forwardCancel(handle, event)
                        }
                    }
                    if (isResizing) {
                        var delta = event.rawX - dragStartRawX
                        if (view.layoutDirection == View.LAYOUT_DIRECTION_RTL) delta = -delta
                        panelWidth = (dragStartWidth + delta.roundToInt())
                            .coerceIn(MIN_PANEL_WIDTH.dp, MAX_PANEL_WIDTH.dp)
                        applyPanelWidth()
                    } else {
                        forwardTouch(handle, event)
                    }
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (isResizing) {
                        isResizing = false
                        WGlobalStorage.setTabletPanelWidth(
                            (panelWidth / ApplicationContextHolder.density).roundToInt()
                        )
                    } else {
                        forwardTouch(handle, event)
                    }
                    forwardTarget = null
                }
            }
            true
        }
    }

    private fun forwardTouch(handle: View, event: MotionEvent) {
        val target = forwardTarget ?: return
        val copy = MotionEvent.obtain(event)
        copy.offsetLocation(handle.x - target.x, handle.y - target.y)
        target.dispatchTouchEvent(copy)
        copy.recycle()
    }

    private fun forwardCancel(handle: View, event: MotionEvent) {
        val target = forwardTarget ?: return
        val cancel = MotionEvent.obtain(event)
        cancel.action = MotionEvent.ACTION_CANCEL
        cancel.offsetLocation(handle.x - target.x, handle.y - target.y)
        target.dispatchTouchEvent(cancel)
        cancel.recycle()
        forwardTarget = null
    }

    private fun applyPanelWidth() {
        val lp = sidePanel.layoutParams ?: return
        val target = panelWidth.coerceAtMost(maxAllowedPanelWidth())
        if (lp.width != target) sidePanel.updateLayoutParams { width = target }
    }

    // The panel must never be wider than the content panel:
    // contentWidth = viewWidth - panelStart - panelWidth + overlap >= panelWidth
    private fun maxAllowedPanelWidth(): Int {
        if (view.width <= 0) return panelWidth
        val panelStart = (window?.systemBars?.left ?: 0) + ViewConstants.HORIZONTAL_PADDINGS.dp
        val overlap = ViewConstants.TABLET_PANELS_OVERLAP_WIDTH.dp.roundToInt()
        return (view.width - panelStart + overlap) / 2
    }

    private val statusListener = HomeStatusController.Listener { state, animated ->
        sidePanel.applyHeaderStatus(state, animated)
    }

    override fun setupViews() {
        super.setupViews()
        WalletCore.registerObserver(this)
        HomeStatusController.addListener(statusListener)

        view.addView(contentPanel, ViewGroup.LayoutParams(0, MATCH_PARENT))
        view.addView(bottomGradientView, ViewGroup.LayoutParams(0, 0))
        view.addView(sidePanel, ViewGroup.LayoutParams(panelWidth, 0))
        pillShadow = WGlassView.attachTo(
            sidePanel,
            ViewConstants.BLOCK_RADIUS.dp,
            GlassProviders.shadowOnly(),
            root = null,
            drawInFront = true
        )
        view.addView(resizeHandle, ViewGroup.LayoutParams(RESIZE_HANDLE_WIDTH.dp, 0))
        view.addView(searchCover, ViewGroup.LayoutParams(0, 0))
        view.addView(searchField, ViewGroup.LayoutParams(0, HomeSearchField.HEIGHT.dp))
        searchGlass = WGlassView.attachTo(
            searchField,
            24f.dp,
            GlassProviders.pill(WColor.SearchFieldBackground),
            root = contentPanel
        )
        view.setConstraints {
            startToEnd(contentPanel, sidePanel, -ViewConstants.TABLET_PANELS_OVERLAP_WIDTH)
            toEnd(contentPanel)
            toTop(contentPanel)
            toBottom(contentPanel)
            startToStart(bottomGradientView, contentPanel)
            endToEnd(bottomGradientView, contentPanel)
            toBottom(bottomGradientView)
            startToEndPx(resizeHandle, sidePanel, -(RESIZE_HANDLE_WIDTH / 2).dp)
            toTop(resizeHandle)
            toBottom(resizeHandle)
            toStart(searchCover)
            endToEnd(searchCover, sidePanel)
            toTop(searchCover)
            toBottom(searchCover)
        }

        contentPanel.addView(contentNav, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        contentPanel.addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
            if (left == oldLeft && right == oldRight) return@addOnLayoutChangeListener
            alignBottomBarToContentPanel()
            if (window?.hasMinimizedBrowser == true) window?.minimizedBrowser?.relayout()
        }
        mountActiveTab()
        sidePanel.setSelectedTab(currentTabId)
        updateMinimizedBrowserDock(animated = false)
        updateSearchVisibility()
        adoptPendingSearchText()
        updateTheme()
        applyPanelInsets()
        homeVCInRightPanel()
        view.viewTreeObserver.addOnPreDrawListener(searchCoverTracker)
        view.doOnPreDraw {
            applyPanelWidth()
            refreshHeader(animated = false)
            sidePanel.setAccounts(WalletCore.getAllAccounts())
            sidePanel.onLaidOut()
            contentNav.insetsUpdated()
            activeNavigationController?.insetsUpdated()
            adoptPendingPushedOverMain()
        }
        WalletCore.doOnBridgeReady {
            refreshHeader(animated = false)
        }
        precacheReceiveBackground()
    }

    private fun homeVCInRightPanel(): HomeVC? = (
        navForOrNull(AppTabsManager.ID_HOME)
            ?.viewControllers?.firstOrNull() as? HomeVC
        )
        ?.also { it.panelHeaderView = sidePanel.headerView }

    override fun navStackUpdated(nav: WNavigationController) {
        if (!isSelectingTab) updateMinimizedBrowserDock(animated = false)
        updateSearchVisibility()
        updateSearchFieldPosition()
        if (nav.parent != contentPanel) return
        updateBottomGradient()
        syncPanelHeaderAccounts()
    }

    private fun syncPanelHeaderAccounts() {
        val activeHome =
            contentNav.viewControllers.lastOrNull { it is HomeVC } as? HomeVC
        activeHome?.panelHeaderView = sidePanel.headerView
        val override = activeHome?.overrideAccountIds
        if (headerView.overrideAccountIds.contentEquals(override)) return
        headerView.overrideAccountIds = override
        refreshHeader(animated = false)
    }

    private fun presentWalletSettings() {
        val window = window ?: return
        val navVC = WNavigationController(
            window,
            WNavigationController.PresentationConfig(
                style = WNavigationController.PresentationStyle.BottomSheet
            )
        )
        navVC.setRoot(
            WalletsTabsVC(
                context,
                WGlobalStorage.getAccountSelectorViewMode() ?: MWalletSettingsViewMode.GRID
            )
        )
        window.present(navVC)
    }

    private fun presentAddAccount() {
        val window = window ?: return
        val navVC = WNavigationController(
            window,
            WNavigationController.PresentationConfig(
                style = WNavigationController.PresentationStyle.BottomSheet
            )
        )
        val addAccountVC = WalletContextManager.delegate?.get()
            ?.getAddAccountVC(MBlockchainNetwork.MAINNET) as? WViewController ?: return
        navVC.setRoot(addAccountVC)
        window.present(navVC)
    }

    private fun onAccountSelected(account: MAccount) {
        if (account.accountId == AccountStore.activeAccountId) return
        WalletCore.activateAccount(account.accountId, notifySDK = true) { res, _ ->
            if (res != null) {
                WalletCore.notifyEvent(
                    WalletEvent.AccountChangedInApp(persistedAccountsModified = false)
                )
            }
        }
    }

    private var isSelectingTab = false

    private fun selectTab(id: Int) {
        if (id == currentTabId) return
        finishAgentSearch()
        currentTabId = id
        updateBottomGradient()
        closeSearch()
        isSelectingTab = true
        mountActiveTab()
        contentNav.popToRoot(animated = false)
        isSelectingTab = false
        sidePanel.setSelectedTab(id)
        updateMinimizedBrowserDock(animated = true)
        updateSearchVisibility()
        updateSearchFieldPosition()
    }

    private fun shouldShowTabletSearch(tabId: Int): Boolean =
        tabId != AppTabsManager.ID_AGENT && tabId != AppTabsManager.ID_SETTINGS

    // The Agent tab shows the search field only while its chats are searched
    private var agentSearchOnClose: (() -> Unit)? = null

    private fun isTabletSearchShown(tabId: Int): Boolean = shouldShowTabletSearch(tabId) ||
        (tabId == AppTabsManager.ID_AGENT && agentSearchOnClose != null)

    override val isAgentSearchSupported = true

    override fun openAgentSearch(onClose: () -> Unit): Boolean {
        if (currentTabId != AppTabsManager.ID_AGENT || isSearchHiddenByTab) return false
        finishAgentSearch()
        agentSearchOnClose = onClose
        updateSearchVisibility()
        updateSearchFieldPosition()
        searchField.editText.requestFocus()
        searchField.editText.showKeyboard()
        return true
    }

    private fun finishAgentSearch() {
        val onClose = agentSearchOnClose ?: return
        agentSearchOnClose = null
        updateSearchVisibility()
        onClose()
    }

    private val mainStackDepth: Int
        get() = contentHostVC.navigationController?.viewControllers?.size ?: 1

    private val tabStackDepth: Int
        get() = activeNavigationController?.viewControllers?.size ?: 1

    private val reservesSearchHeight: Boolean
        get() = isTabletSearchShown(currentTabId) && mainStackDepth <= 1 && tabStackDepth <= 1

    private var appliedSearchReservation: Boolean? = null

    private fun updateSearchVisibility() {
        if (contentHostVC.navigationController?.parent !== contentPanel) return
        if (appliedSearchReservation != reservesSearchHeight) {
            appliedSearchReservation = reservesSearchHeight
            updateBottomGradient()
            activeNavigationController?.insetsUpdated()
            searchOverlayNav?.insetsUpdated()
        }
        val isRootShown = mainStackDepth <= 1 && tabStackDepth <= 1
        if (isSearchHiddenByTab || !isTabletSearchShown(currentTabId) || !isRootShown) {
            if (searchField.editText.hasFocus()) {
                clearSearchFocus()
            } else if (searchOverlayNav?.viewControllers?.isNotEmpty() == true) {
                updateSearch(null, focused = false)
            }
        }
        applySearchFieldAlpha()
    }

    // A screen pushed over the root covers the field like the root's own top bar.
    private val searchCoverTracker = ViewTreeObserver.OnPreDrawListener {
        applySearchFieldAlpha()
        applyMinimizedBrowserDockFraction()
        applyBottomGradientHeight()
        true
    }
    private val searchCoverLocation = IntArray(2)
    private val searchFieldLocation = IntArray(2)

    private fun rootScreenCoverage(): Float {
        val cover = when {
            mainStackDepth == 1 && tabStackDepth == 1 -> return 0f

            mainStackDepth == 1 && tabStackDepth == 2 ->
                activeNavigationController?.viewControllers?.getOrNull(1)?.view

            mainStackDepth == 2 && tabStackDepth == 1 ->
                contentHostVC.navigationController?.viewControllers?.getOrNull(1)?.view

            else -> return 1f
        } ?: return 0f
        if (!cover.isVisible || searchField.width == 0) return 0f
        cover.getLocationInWindow(searchCoverLocation)
        searchField.getLocationInWindow(searchFieldLocation)
        val coveredWidth = if (view.layoutDirection == View.LAYOUT_DIRECTION_RTL) {
            searchCoverLocation[0] + cover.width - searchFieldLocation[0]
        } else {
            searchFieldLocation[0] + searchField.width - searchCoverLocation[0]
        }
        val coveredFraction = (coveredWidth / searchField.width.toFloat()).coerceIn(0f, 1f)
        return cover.alpha * coveredFraction
    }

    private fun applySearchFieldAlpha() {
        if (searchField.parent == null) return
        val chromeAlpha =
            if (searchHiddenByTabId == null || isSearchHiddenByTab) searchChromeAlpha else 1f
        val alpha = chromeAlpha * (1f - rootScreenCoverage())
        if (searchField.alpha != alpha) {
            searchField.alpha = alpha
            searchGlass?.alpha = alpha
        }
        val isSearchVisible = isTabletSearchShown(currentTabId) && alpha > 0f
        if (searchField.isVisible != isSearchVisible) {
            searchField.isVisible = isSearchVisible
            searchGlass?.isVisible = isSearchVisible
        }
    }

    override fun onExploreCreated(exploreVC: ExploreVC) {
        exploreVC.onBestSearchMatchActionChanged = searchField::setBestMatchAction
    }

    override fun exportSearchText(): String = searchField.currentText()

    override fun restoreSearchText(text: String) {
        searchField.restoreText(text)
    }

    private fun updateSearch(query: String?, focused: Boolean) {
        searchExplore(query, focused, searchOverlayNavigationController ?: return)
    }

    private fun closeSearch() {
        val nav = searchOverlayNav?.takeIf { it.viewControllers.isNotEmpty() } ?: return
        if (nav.viewControllers.size > 1) nav.popToRoot(false)
        searchField.editText.setText("")
        if (searchField.editText.hasFocus()) {
            clearSearchFocus()
        } else {
            updateSearch(null, focused = false)
        }
    }

    private var searchOverlayNav: WNavigationController? = null

    override val searchOverlayNavigationController: WNavigationController?
        get() {
            searchOverlayNav?.let { return it }
            val window = window ?: return null
            val nav = WNavigationController(window)
            nav.tabBarController = this
            nav.searchOverlayHost = this
            nav.alpha = 0f
            searchOverlayNav = nav
            contentPanel.addView(nav, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            nav.insetsUpdated()
            return nav
        }

    override fun revealSearchOverlay() {
        val nav = searchOverlayNav?.takeIf { it.viewControllers.isNotEmpty() } ?: return
        nav.fadeIn(PhoneTabsVC.SEARCH_OVERLAY_ANIMATION)
        animateSearchExpansion(1f)
        searchCover.animate().cancel()
        searchCover.isVisible = true
        searchCover.fadeIn(PhoneTabsVC.SEARCH_OVERLAY_ANIMATION)
    }

    override fun hideSearchOverlay() {
        finishAgentSearch()
        val nav = searchOverlayNav ?: return
        searchOverlayNav = null
        if (nav.viewControllers.isEmpty()) {
            contentPanel.removeView(nav)
            return
        }
        // Keep it on screen through the fade, without taking taps.
        nav.blockTouches()
        nav.fadeOut(PhoneTabsVC.SEARCH_OVERLAY_ANIMATION) {
            nav.viewControllers.forEach { it.viewWillDisappear() }
            // Detached so the outgoing search cannot clear focus of a replacement session.
            nav.searchOverlayHost = null
            nav.tabBarController = null
            nav.onDestroy()
            contentPanel.removeView(nav)
        }
        animateSearchExpansion(0f)
        searchCover.animate().cancel()
        searchCover.fadeOut(PhoneTabsVC.SEARCH_OVERLAY_ANIMATION) {
            searchCover.isVisible = false
        }
    }

    private fun mountActiveTab() {
        val newNav = getNavigationStack(currentTabId)
        if (newNav.parent === contentHostVC.contentParent) return
        contentHostVC.setContent(newNav)
        newNav.insetsUpdated()
    }

    // Refresh the header's account + balance. Sync status is driven by HomeStatusController, not here.
    private fun refreshHeader(animated: Boolean) {
        val account = headerView.overrideAccountIds?.firstOrNull()
            ?.let { AccountStore.accountById(it) }
            ?: AccountStore.activeAccount
        account?.let { headerView.updateAccountData(it) }
        headerView.updateBalance(animated = animated)
    }

    private var appliedPanelStart = -1
    private var panelStartAnimator: ValueAnimator? = null

    private fun applyPanelInsets() {
        val top = window?.systemBars?.top ?: 0
        val barsLeft = window?.systemBars?.left ?: 0
        val start = barsLeft + ViewConstants.HORIZONTAL_PADDINGS.dp
        view.setConstraints {
            toTopPx(sidePanel, top)
            toBottom(sidePanel)
        }
        val from = appliedPanelStart
        appliedPanelStart = start
        panelStartAnimator?.cancel()
        if (from < 0 || from == start || view.width == 0 ||
            !WGlobalStorage.getAreAnimationsActive()
        ) {
            view.setConstraints { toStartPx(sidePanel, start) }
            sidePanel.gutterPadding = ViewConstants.HORIZONTAL_PADDINGS.dp
            return
        }
        panelStartAnimator = ValueAnimator.ofInt(from, start).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()

            addUpdateListener { animator ->
                val value = animator.animatedValue as Int
                view.setConstraints { toStartPx(sidePanel, value) }
                sidePanel.gutterPadding = (value - barsLeft).coerceAtLeast(0)
            }

            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    panelStartAnimator = null
                    applyPanelWidth()
                }
            })

            start()
        }
    }

    override val isTinted = true
    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        bottomGradientDrawable = null
        updateBottomGradient()
        sidePanel.updateTheme()
        applyPillShadowBottom()
        pillShadow?.updateTheme()
        searchGlass?.updateTheme()
        searchField.updateTheme()
        contentNav.updateTheme()
        searchOverlayNav?.updateTheme()
        for (nav in navStacks) {
            if (nav.parent != null && !contentHostVC.isDisappeared) continue
            nav.updateTheme()
        }
    }

    override fun rootTopAccessoryWidthsChanged() {
        updateSearchFieldPosition()
    }

    private val topContentNav: WNavigationController?
        get() = contentHostVC.navigationController?.takeIf { it.viewControllers.size > 1 }
            ?: activeNavigationController

    private val topContentViewController: WViewController?
        get() = topContentNav?.viewControllers?.lastOrNull()

    private val belowContentViewController: WViewController?
        get() {
            val vcs = topContentNav?.viewControllers ?: return null
            val below = vcs.getOrNull(vcs.size - 2)
            return if (below === contentHostVC) {
                activeNavigationController?.viewControllers?.lastOrNull()
            } else {
                below
            }
        }

    private fun updateMinimizedBrowserDock(animated: Boolean) {
        if (contentHostVC.navigationController?.parent !== contentPanel) return
        val docks = topContentViewController?.docksMinimizedBrowser == true
        if (minimizedBrowserDock.value == docks) return
        minimizedBrowserDock.changeValue(
            docks,
            animated && WGlobalStorage.getAreAnimationsActive() && searchField.isLaidOut
        )
        updateBottomGradient()
        contentNav.insetsUpdated()
        if (!isShowingPushedOverMain) activeNavigationController?.insetsUpdated()
        searchOverlayNav?.insetsUpdated()
    }

    private fun minimizedBrowserDockFraction(): Float {
        if (minimizedBrowserDock.state == BoolAnimator.State.INTERMEDIATE) {
            return minimizedBrowserDock.floatValue
        }
        val top = topContentViewController ?: return 0f
        val topDock = if (top.docksMinimizedBrowser) 1f else 0f
        val belowDock = belowContentViewController?.let {
            if (it.docksMinimizedBrowser) 1f else 0f
        } ?: return topDock
        if (topDock == belowDock) return topDock
        return lerp(belowDock, topDock, topContentPresence(top))
    }

    private fun topContentPresence(top: WViewController): Float {
        val topView = top.view
        if (topView.width == 0) return 1f
        val presence = topView.alpha * (1f - abs(topView.translationX) / topView.width)
        return presence.coerceIn(0f, 1f)
    }

    private var minimizedBrowserDockProgress = 0f
    private var lastDockedSpan: IntRange? = null
    private var lastDockedBottomInset: Int? = null

    private fun applyMinimizedBrowserDockFraction() {
        val fraction = minimizedBrowserDockFraction()
        searchField.translationY = -minimizedBrowserHeight * (1f - fraction)
        if (fraction == minimizedBrowserDockProgress) return
        minimizedBrowserDockProgress = fraction
        if (window?.hasMinimizedBrowser == true) window?.minimizedBrowser?.snapToRest()
    }

    private val searchMinimizedLift: Int
        get() = if (minimizedBrowserDock.value) 0 else minimizedBrowserHeight

    private val searchRestBottom: Int
        get() = searchRestBottom(searchMinimizedLift)

    private fun searchRestBottom(minimizedLift: Int): Int =
        (window?.systemBars?.bottom ?: 0) + minimizedLift +
            if (WGlobalStorage.isGradientNavigationBarActive()) {
                SEARCH_BOTTOM_MARGIN.dp
            } else {
                (SEARCH_BOTTOM_MARGIN + SEARCH_BOTTOM_EXTRA_GAP).dp
            }

    private val searchKeyboardLiftTarget: Float
        get() {
            val keyboard = window?.imeInsets?.bottom ?: 0
            if (keyboard <= 0) return 0f
            return (keyboard + SEARCH_KEYBOARD_GAP.dp - searchRestBottom)
                .coerceAtLeast(0)
                .toFloat()
        }

    private fun updateSearchFieldPosition() {
        if (searchField.parent == null) return
        val horizontalPadding = ViewConstants.HORIZONTAL_PADDINGS.dp
        val rootVC = activeNavigationController?.viewControllers?.firstOrNull()
        val leadingWidth = rootVC?.rootTopLeadingWidth ?: 0
        val trailingWidth = rootVC?.rootTopTrailingWidth ?: 0

        // The search screen covers the root's buttons.
        fun margin(accessoryWidth: Int): Int {
            if (accessoryWidth <= 0) return horizontalPadding
            return lerp(
                (accessoryWidth + ACCESSORY_GAP.dp).toFloat(),
                horizontalPadding.toFloat(),
                searchExpansion
            ).roundToInt()
        }
        view.setConstraints {
            toBottomPx(
                searchField,
                searchRestBottom(0) + searchKeyboardLift.value.coerceAtLeast(0f).roundToInt()
            )
            startToStartPx(
                searchField,
                contentPanel,
                ViewConstants.ADDITIONAL_TABLET_PADDING + margin(leadingWidth)
            )
            endToEndPx(searchField, contentPanel, systemBarEndInset + margin(trailingWidth))
        }
    }

    private var searchExpansion = 0f
    private var searchExpansionAnimator: ValueAnimator? = null

    private fun animateSearchExpansion(target: Float) {
        searchExpansionAnimator?.cancel()
        searchExpansionAnimator = null
        if (searchExpansion == target) return
        if (!WGlobalStorage.getAreAnimationsActive()) {
            searchExpansion = target
            updateSearchFieldPosition()
            return
        }
        searchExpansionAnimator = ValueAnimator.ofFloat(searchExpansion, target).apply {
            duration = PhoneTabsVC.SEARCH_OVERLAY_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener {
                searchExpansion = it.animatedValue as Float
                updateSearchFieldPosition()
            }
            start()
        }
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        headerView.viewWillAppear()
        contentNav.viewWillAppear()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        contentNav.viewDidAppear()
        // A phone<->tablet swap builds a brand-new container; refresh account/balance on appear so
        // they reflect current state (status is already seeded via the HomeStatusController listener).
        refreshHeader(animated = false)
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        headerView.viewWillDisappear()
        contentNav.viewWillDisappear()
    }

    override fun onSizeChanged(w: Int, h: Int, oldW: Int, oldH: Int) {
        super.onSizeChanged(w, h, oldW, oldH)
        if (w != oldW) view.doOnPreDraw { applyPanelWidth() }
    }

    private fun applyPillShadowBottom() {
        val gradientNav = WGlobalStorage.isGradientNavigationBarActive()
        val top = ViewConstants.BLOCK_RADIUS.dp
        val bottom = if (gradientNav) 0f else ViewConstants.TOOLBAR_RADIUS.dp
        pillShadow?.setRadius(top, top, bottom, bottom)
        pillShadow?.setBottomInset(if (gradientNav) 0f else sidePanel.contentBottomInset.toFloat())
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        alignBottomBarToContentPanel()
        applyPanelInsets()
        applyPanelWidth()
        sidePanel.updateInsets()
        applyPillShadowBottom()
        updateBottomGradient()
        contentNav.insetsUpdated()
        // The per-tab nav inside the host needs its insets too when it's the visible content.
        if (!isShowingPushedOverMain) activeNavigationController?.insetsUpdated()
        searchOverlayNav?.insetsUpdated()
        if (!isKeyboardOpen &&
            searchField.editText.hasFocus() &&
            cachedExploreVC?.shouldKeepSearchActiveOnKeyboardDismiss != true
        ) {
            searchField.editText.clearFocus()
        }
        searchKeyboardLift.animatedValue = searchKeyboardLiftTarget
        updateSearchFieldPosition()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                if (!AccountStore.isPushedTemporary && !walletEvent.isSavingTemporaryAccount) {
                    activeNavigationController?.popToRootUnlessDisplaying(walletEvent.accountId)
                    mainNavigationController?.popToRootUnlessDisplaying(walletEvent.accountId)
                }
                refreshHeader(animated = false)
                sidePanel.refreshAccountSelection()
            }

            is WalletEvent.AccountWillChange -> {
                // Status is handled by HomeStatusController; nothing tablet-specific to do here, but
                // keep the branch so the event isn't routed as a generic wallet event.
            }

            is WalletEvent.AccountChangedInApp -> {
                val activeAccountId = AccountStore.activeAccountId
                activeNavigationController?.popToRootUnlessDisplaying(activeAccountId)
                if (!AccountStore.isPushedTemporary) {
                    mainNavigationController?.popToRootUnlessDisplaying(activeAccountId)
                }
                sidePanel.setAccounts(WalletCore.getAllAccounts())
                sidePanel.refreshAccountSelection()
                refreshHeader(animated = false)
            }

            WalletEvent.AddNewWalletCompletion -> {
                if (currentTabId != AppTabsManager.ID_HOME) {
                    selectTab(AppTabsManager.ID_HOME)
                }
                sidePanel.setAccounts(WalletCore.getAllAccounts())
                refreshHeader(animated = false)
            }

            WalletEvent.BalanceChanged,
            WalletEvent.NotActiveAccountBalanceChanged,
            WalletEvent.TokensChanged,
            WalletEvent.BaseCurrencyChanged -> {
                headerView.updateBalance(animated = true)
                sidePanel.setAccounts(WalletCore.getAllAccounts())
            }

            is WalletEvent.AccountNameChanged -> {
                AccountStore.activeAccount?.let { headerView.updateAccountData(it) }
                sidePanel.setAccounts(WalletCore.getAllAccounts())
            }

            WalletEvent.NftCardUpdated -> {
                sidePanel.setAccounts(WalletCore.getAllAccounts())
                routeWalletEvent(walletEvent)
            }

            WalletEvent.AssetsAndActivityDataUpdated -> {
                AccountStore.activeAccountId?.let { headerView.updateAddressLabel(it) }
                routeWalletEvent(walletEvent)
            }

            WalletEvent.SideGuttersChanged -> {
                applyPanelInsets()
                applyPanelWidth()
                updateSearchFieldPosition()
            }

            WalletEvent.AppTabsChanged -> {
                if (!AppTabsManager.contains(currentTabId)) selectTab(AppTabsManager.ID_HOME)
                sidePanel.updateTabs(buildTabDefs())
            }

            else -> {
                routeWalletEvent(walletEvent)
            }
        }
    }

    override fun onBackPressed(): Boolean {
        searchOverlayNav?.takeIf { it.viewControllers.isNotEmpty() }?.let { nav ->
            if (nav.viewControllers.size > 1) return nav.onBackPressed()
            if (searchField.editText.hasFocus()) {
                clearSearchFocus()
            } else {
                updateSearch(null, focused = false)
            }
            return false
        }
        // Pop full-screen VCs pushed over the main nav first, then fall back to the active tab stack.
        if ((contentNav.viewControllers.size) > 1) return contentNav.onBackPressed()
        return activeNavigationController?.onBackPressed() ?: true
    }

    private val isShowingPushedOverMain: Boolean
        get() = contentNav.viewControllers.size > 1

    // ITabsVC /////////////////////////////////////////////////////////////////////////////////////
    override val mainNavigationController: WNavigationController?
        get() = contentNav

    // Full-screen pushes on tablet live in the content-panel nav, above the host root.
    override fun exportPushedOverMain(): List<WViewController> = contentNav.detachAboveRoot()

    override fun adoptPushedOverMain(pushed: List<WViewController>) {
        contentNav.adoptAboveRoot(pushed)
    }

    override val activeNavigationController: WNavigationController?
        get() = navForOrNull(currentTabId)

    override fun getBottomNavigationHeight(): Int =
        bottomNavigationHeight(reservesSearchHeight, minimizedBrowserDock.value)

    private fun bottomNavigationHeight(reservesSearchHeight: Boolean, docks: Boolean): Int {
        val minimizedLift = if (docks) 0 else minimizedBrowserHeight
        if (reservesSearchHeight) {
            return searchRestBottom(minimizedLift) + searchKeyboardLiftTarget.roundToInt() +
                (HomeSearchField.HEIGHT + PhoneTabsVC.SEARCH_TOP_MARGIN).dp
        }
        val systemBottom = window?.systemBars?.bottom ?: 0
        val keyboard = window?.imeInsets?.bottom ?: 0
        return maxOf(systemBottom + minimizedLift, keyboard)
    }

    private val minimizedBrowserHeight: Int
        get() = (window?.minimizedBrowserHeight ?: 0f).roundToInt()

    override val bottomBlurRootView: ViewGroup
        get() = contentPanel

    // Below the side panel, which draws its own bar.
    private fun alignBottomBarToContentPanel() {
        val bar = bottomReversedCornerView ?: return
        val index = view.indexOfChild(contentPanel) + 1
        if (view.indexOfChild(bar) != index) {
            view.removeView(bar)
            view.addView(bar, index)
        }
        val contentStart =
            if (LocaleController.isRTL) view.width - contentPanel.right else contentPanel.left
        bar.setSideInsets(
            (contentStart + ViewConstants.ADDITIONAL_TABLET_PADDING).toFloat(),
            systemBarEndInset.toFloat()
        )
        applyContentBottomBarPadding()
    }

    private var contentBottomBarPadding: Pair<Float, Float>? = null

    /** Null restores the default. */
    fun setContentBottomBarPadding(padding: Pair<Float, Float>?) {
        if (contentBottomBarPadding == padding) return
        contentBottomBarPadding = padding
        applyContentBottomBarPadding()
    }

    private fun applyContentBottomBarPadding() {
        val bar = bottomReversedCornerView ?: return
        val default = ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat()
        val (start, end) = contentBottomBarPadding ?: (default to default)
        bar.setHorizontalPadding(start, end)
    }

    // Outside contentPanel, so the minimized browser glass blurs the content, not this fade.
    private fun updateBottomGradient() {
        val topViewController =
            (if (isShowingPushedOverMain) contentNav else activeNavigationController)
                ?.viewControllers?.lastOrNull()
        val visible = WGlobalStorage.isGradientNavigationBarActive() &&
            topViewController?.let {
                it.forceBlurBottomView || it.additionalBottomGradientHeight > 0
            } != true
        bottomGradientView.isVisible = visible
        if (!visible) return
        val color = WColor.SecondaryBackground.color
        val drawable = bottomGradientDrawable?.takeIf { bottomGradientColor == color }
            ?: StickyBottomGradientDrawable(
                intArrayOf(
                    color.colorWithAlpha(0),
                    color.colorWithAlpha(BOTTOM_GRADIENT_ALPHA),
                    color.colorWithAlpha(BOTTOM_GRADIENT_ALPHA)
                )
            ).also {
                bottomGradientDrawable = it
                bottomGradientColor = color
                bottomGradientView.background = it
            }
        applyBottomGradientHeight()
    }

    private fun bottomGradientHeight(reservesSearchHeight: Boolean, docks: Boolean): Int =
        bottomNavigationHeight(reservesSearchHeight, docks) +
            ViewConstants.ADDITIONAL_GRADIENT_HEIGHT.dp.roundToInt()

    private val belowReservesSearchHeight: Boolean?
        get() {
            val depth = mainStackDepth + tabStackDepth
            if (depth <= 2) return null
            return isTabletSearchShown(currentTabId) && depth == 3
        }

    // Sized for both screens of a transition; stops show the current height.
    private fun applyBottomGradientHeight() {
        val drawable = bottomGradientDrawable ?: return
        if (!bottomGradientView.isVisible) return
        val height = bottomGradientHeight(reservesSearchHeight, minimizedBrowserDock.value)
        val belowReserves = belowReservesSearchHeight
        val belowDocks = belowContentViewController?.docksMinimizedBrowser == true
        val top = topContentViewController
        var visibleHeight = height
        var viewHeight = height
        if (belowReserves != null && top != null) {
            val belowHeight = bottomGradientHeight(belowReserves, belowDocks)
            visibleHeight =
                lerp(belowHeight.toFloat(), height.toFloat(), topContentPresence(top)).roundToInt()
            viewHeight = maxOf(height, belowHeight)
        } else if (minimizedBrowserDock.state == BoolAnimator.State.INTERMEDIATE) {
            val undocked = bottomGradientHeight(reservesSearchHeight, false)
            val docked = bottomGradientHeight(reservesSearchHeight, true)
            visibleHeight =
                lerp(
                    undocked.toFloat(),
                    docked.toFloat(),
                    minimizedBrowserDockProgress
                ).roundToInt()
            viewHeight = maxOf(undocked, docked)
        }
        if (bottomGradientView.layoutParams.height != viewHeight) {
            bottomGradientView.updateLayoutParams { this.height = viewHeight }
        }
        val laidOutHeight = bottomGradientView.height.takeIf { it > 0 } ?: viewHeight
        val solidHeight = maxOf(window?.systemBars?.bottom ?: 0, window?.imeInsets?.bottom ?: 0)
        val fadeStart = ((laidOutHeight - visibleHeight).toFloat() / laidOutHeight).coerceIn(0f, 1f)
        val solidStart = ((laidOutHeight - solidHeight).toFloat() / laidOutHeight)
            .coerceIn(fadeStart, 1f)
        drawable.setStops(floatArrayOf(fadeStart, solidStart, 1f))
    }

    override val minimizedBlurRootView: ViewGroup
        get() = contentPanel

    private val dockingViewController: WViewController?
        get() = topContentViewController?.takeIf { it.docksMinimizedBrowser }
            ?: belowContentViewController?.takeIf { it.docksMinimizedBrowser }

    // Kept for when the docked screen is gone.
    private val dockedSpan: IntRange?
        get() = dockingViewController?.minimizedBrowserSpan
            ?.also { lastDockedSpan = it }
            ?: lastDockedSpan

    private val dockedBottomInset: Int?
        get() = dockingViewController?.minimizedBrowserBottomInset
            ?.also { lastDockedBottomInset = it }
            ?: lastDockedBottomInset

    override val minimizedBrowserBottomInset: Int?
        get() {
            val progress = minimizedBrowserDockProgress
            if (progress <= 0f) return null
            val docked = dockedBottomInset ?: return null
            return lerp(
                (window?.systemBars?.bottom ?: 0).toFloat(),
                docked.toFloat(),
                progress
            ).roundToInt()
        }

    override val minimizedBrowserSpan: IntRange?
        get() {
            val span = panelMinimizedBrowserSpan ?: return null
            val progress = minimizedBrowserDockProgress
            if (progress <= 0f) return span
            val docked = dockedSpan ?: return span
            val first = lerp(span.first.toFloat(), docked.first.toFloat(), progress)
            val last = lerp(span.last.toFloat(), docked.last.toFloat(), progress)
            return first.roundToInt()..last.roundToInt()
        }

    private val panelMinimizedBrowserSpan: IntRange?
        get() {
            if (contentPanel.width == 0) return null
            val isRtl = view.layoutDirection == View.LAYOUT_DIRECTION_RTL
            val startPadding = ViewConstants.ADDITIONAL_TABLET_PADDING
            val left = contentPanel.left + if (isRtl) systemBarEndInset else startPadding
            val right = contentPanel.right - if (isRtl) startPadding else systemBarEndInset
            return left until right
        }

    override fun setSearchText(text: String) {
        if (!shouldShowTabletSearch(currentTabId)) selectTab(AppTabsManager.ID_HOME)
        contentNav.popToRoot(animated = false)
        searchField.setSearchText(text)
    }

    override fun clearSearchFocus() {
        // Keep the IME up for another screen's focused field.
        val focusedView = searchField.editText.rootView.findFocus()
        if (focusedView != null && focusedView !== searchField.editText) {
            searchField.editText.clearFocus()
            return
        }
        searchField.editText.hideKeyboard()
    }

    override fun switchToFirstTab(): Boolean = selectTabIfNeeded(firstTabId)

    override fun switchToWallet(): Boolean = selectTabIfNeeded(AppTabsManager.ID_HOME)

    private fun selectTabIfNeeded(id: Int): Boolean {
        if (currentTabId == id) return false
        selectTab(id)
        return true
    }

    // Tab-container navigation surface ////////////////////////////////////////////////////////////
    override val isOnHomeScreen: Boolean
        get() = currentTabId == AppTabsManager.ID_HOME &&
            window?.topViewController == this &&
            (activeNavigationController?.viewControllers?.size ?: 0) == 1

    override fun switchToExplore(targetUri: Uri?) {
        if (!AppTabsManager.contains(AppTabsManager.ID_EXPLORE)) {
            window?.dismissToRoot()
            val exploreVC = ExploreVC(context)
            activeNavigationController?.push(exploreVC)
            targetUri?.let { exploreVC.findSiteAndOpenTargetUri(it) }
            return
        }
        selectTab(AppTabsManager.ID_EXPLORE)
        window?.dismissToRoot()
        targetUri?.let { cachedExploreVC?.findSiteAndOpenTargetUri(it) }
    }

    override fun switchToMarket() {
        if (!AppTabsManager.contains(AppTabsManager.ID_MARKET)) {
            // Market is an optional tab the user may have hidden, and a deeplink must still land
            // on the screen, so push it onto the current stack instead of selecting a missing tab.
            window?.dismissToRoot()
            activeNavigationController?.push(MarketVC(context))
            return
        }
        selectTab(AppTabsManager.ID_MARKET)
        window?.dismissToRoot()
    }

    override fun switchToFutures() {
        if (!PerpsAvailability.isAvailable()) return
        if (!AppTabsManager.contains(AppTabsManager.ID_FUTURES)) {
            window?.dismissToRoot()
            activeNavigationController?.push(FuturesVC(context))
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
        selectTab(AppTabsManager.ID_AGENT)
        window?.dismissToRoot()
        contentNav.popToRoot(animated = false)
        openAgentChat(prompt, entryPoint, thread)
        return true
    }

    override fun switchToSettings(pushVC: WViewController?) {
        selectTab(AppTabsManager.ID_SETTINGS)
        window?.dismissToRoot()
        pushVC?.let { activeNavigationController?.push(it) }
    }

    // The tab whose root screen hid the field.
    private var searchHiddenByTabId: Int? = null

    private val isSearchHiddenByTab: Boolean
        get() = searchHiddenByTabId == currentTabId

    override fun hideTabBar() {
        searchHiddenByTabId = currentTabId
        updateSearchVisibility()
        animateSearchChromeAlpha(0f)
    }

    override fun showTabBar() {
        searchHiddenByTabId = null
        updateSearchVisibility()
        animateSearchChromeAlpha(1f)
    }

    private var isSearchHiddenByOverlap = false
    private val bottomGradientFader = OverlappedChromeFader()

    override fun hideChromeOverlapping(windowRect: Rect): Boolean {
        val isScreenChromeHidden = super.hideChromeOverlapping(windowRect)
        val bottomFrames =
            listOfNotNull(searchField.frameInWindow(), bottomGradientView.frameInWindow())
        if (searchHiddenByTabId == null && bottomFrames.any { Rect.intersects(it, windowRect) }) {
            hideTabBar()
            isSearchHiddenByOverlap = true
        }
        val isBottomGradientHidden = bottomGradientFader.hideIfOverlapping(
            windowRect,
            bottomFrames,
            listOf(bottomGradientView)
        )
        return isScreenChromeHidden || isSearchHiddenByOverlap || isBottomGradientHidden
    }

    override fun showOverlappedChrome() {
        super.showOverlappedChrome()
        if (isSearchHiddenByOverlap) {
            isSearchHiddenByOverlap = false
            showTabBar()
        }
        bottomGradientFader.show()
    }

    private var searchChromeAlpha = 1f
    private var searchChromeAnimator: ValueAnimator? = null

    private fun animateSearchChromeAlpha(target: Float) {
        searchChromeAnimator?.cancel()
        searchChromeAnimator = null
        if (!WGlobalStorage.getAreAnimationsActive()) {
            searchChromeAlpha = target
            applySearchFieldAlpha()
            return
        }
        searchChromeAnimator = ValueAnimator.ofFloat(searchChromeAlpha, target).apply {
            duration = AnimationConstants.QUICK_ANIMATION / 2
            addUpdateListener {
                searchChromeAlpha = it.animatedValue as Float
                applySearchFieldAlpha()
            }
            start()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        panelStartAnimator?.cancel()
        panelStartAnimator = null
        searchChromeAnimator?.cancel()
        searchChromeAnimator = null
        searchExpansionAnimator?.cancel()
        searchExpansionAnimator = null
        view.viewTreeObserver.takeIf { it.isAlive }?.removeOnPreDrawListener(searchCoverTracker)
        HomeStatusController.removeListener(statusListener)
        contentHostVC.detachContent()
        contentNav.onDestroy()
        sidePanel.onDestroy()
        searchOverlayNav?.let { nav ->
            nav.viewControllers.forEach { it.viewWillDisappear() }
            contentPanel.removeView(nav)
            nav.onDestroy()
        }
        searchOverlayNav = null
    }
}
