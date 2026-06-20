package org.mytonwallet.uihome.tabletTabs

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import androidx.core.view.doOnPreDraw
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.PillShadowView
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.uihome.tabs.views.ExploreSearchBar
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.uihome.R
import org.mytonwallet.uihome.home.HomeVC
import org.mytonwallet.uihome.home.status.HomeStatusController
import org.mytonwallet.uihome.home.views.header.HomeHeaderView
import org.mytonwallet.uihome.tabletTabs.views.TabletSidePanelView
import org.mytonwallet.uihome.tabs.BaseTabsVC
import org.mytonwallet.uihome.tabs.views.IBottomNavigationView
import org.mytonwallet.uihome.walletsTabs.WalletsTabsVC
import kotlin.math.abs
import kotlin.math.roundToInt
import androidx.core.view.isVisible

@SuppressLint("ViewConstructor")
class TabletTabsVC(context: Context) : BaseTabsVC(context), WThemedView,
    WalletCore.EventObserver {
    override val TAG = "TabletTabs"

    override val shouldDisplayTopBar = false
    override val ignoreSideGuttering = true
    override val isSwipeBackAllowed = false

    companion object {
        const val DEFAULT_PANEL_WIDTH = 360
        const val MIN_PANEL_WIDTH = 270
        const val MAX_PANEL_WIDTH = 360
        private const val RESIZE_HANDLE_WIDTH = 24

        private const val SEARCH_BOTTOM_MARGIN = 16

        private val tabDefs = listOf(
            TabletSidePanelView.TabDef(
                IBottomNavigationView.ID_HOME,
                R.drawable.ic_home_thin, R.drawable.ic_home_filled, "Wallet"
            ),
            TabletSidePanelView.TabDef(
                IBottomNavigationView.ID_AGENT,
                R.drawable.ic_agent_thin, R.drawable.ic_agent_filled, "Agent"
            ),
            TabletSidePanelView.TabDef(
                IBottomNavigationView.ID_EXPLORE,
                R.drawable.ic_explore_thin, R.drawable.ic_explore_filled, "Explore"
            ),
            TabletSidePanelView.TabDef(
                IBottomNavigationView.ID_SETTINGS,
                R.drawable.ic_settings_thin, R.drawable.ic_settings_filled, "Settings"
            ),
        )
    }

    override var currentTabId: Int = IBottomNavigationView.ID_HOME

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
        contentHostVC.detachContent()
        (contentNav.parent as? ViewGroup)?.removeView(contentNav)
    }

    private val sidePanel by lazy {
        TabletSidePanelView(
            viewController = this,
            tabDefs = tabDefs,
            onTabSelected = { id -> selectTab(id) },
            onTabReselected = { id ->
                if ((mainNavigationController?.viewControllers?.size ?: 0) > 1) {
                    mainNavigationController?.popToRoot()
                }
                navForOrNull(id)?.apply {
                    if (viewControllers.size == 1) scrollToTop() else popToRoot()
                }
            },
            onAccountSelected = { account -> onAccountSelected(account) },
            onWalletSettings = { presentWalletSettings() },
            onAddAccount = { presentAddAccount() },
            onHeaderSwipe = { progress, verticalOffset, actionsFadeInPercent ->
                homeVCInRightPanel()?.applyHorizontalSwipe(
                    progress, verticalOffset, actionsFadeInPercent
                )
            },
        )
    }
    private var pillShadow: PillShadowView? = null
    private val headerView: HomeHeaderView get() = sidePanel.headerView
    private val contentPanel = WFrameLayout(context)

    private val searchBar by lazy {
        ExploreSearchBar(
            context,
            ExploreSearchBar.Config(
                onSearch = { query, focused ->
                    cachedExploreVC?.search(query, focused)
                },
                expandedWidthProvider = {
                    (contentPanel.width - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp - 40.dp - additionalTabletPadding - systemBarEndInset)
                        .coerceAtLeast(0)
                },
                presentBrowser = { config -> presentSearchBrowser(config) },
            )
        )
    }

    private var panelWidth =
        ((WGlobalStorage.getTabletPanelWidth() ?: DEFAULT_PANEL_WIDTH)
            .coerceIn(MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)).dp

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
                        if (handle.x + event.x >= sidePanel.x + sidePanel.width)
                            contentPanel else sidePanel
                    forwardTouch(handle, event)
                }

                MotionEvent.ACTION_MOVE -> {
                    if (!isResizing && !resizeRejected) {
                        val dx = abs(event.rawX - dragStartRawX)
                        val dy = abs(event.y - dragStartY)
                        if (dy > touchSlop && dy > dx)
                            resizeRejected = true
                        else if (dx > touchSlop && dx > dy) {
                            isResizing = true
                            forwardCancel(handle, event)
                        }
                    }
                    if (isResizing) {
                        var delta = event.rawX - dragStartRawX
                        if (view.layoutDirection == View.LAYOUT_DIRECTION_RTL)
                            delta = -delta
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
        if (lp.width != target)
            sidePanel.updateLayoutParams { width = target }
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
        view.addView(sidePanel, ViewGroup.LayoutParams(panelWidth, 0))
        pillShadow =
            PillShadowView.attachTo(
                sidePanel, ViewConstants.BLOCK_RADIUS.dp, drawInFront = true
            ).also { shadow ->
                sidePanel.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> shadow.sync() }
            }
        view.addView(resizeHandle, ViewGroup.LayoutParams(RESIZE_HANDLE_WIDTH.dp, 0))
        view.setConstraints {
            startToEnd(contentPanel, sidePanel, -ViewConstants.TABLET_PANELS_OVERLAP_WIDTH)
            toEnd(contentPanel)
            toTop(contentPanel)
            toBottom(contentPanel)
            startToEndPx(resizeHandle, sidePanel, -(RESIZE_HANDLE_WIDTH / 2).dp)
            toTop(resizeHandle)
            toBottom(resizeHandle)
        }

        contentPanel.addView(contentNav, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        contentPanel.addView(
            searchBar,
            FrameLayout.LayoutParams(
                searchBar.collapsedWidth,
                ExploreSearchBar.SEARCH_HEIGHT.dp,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            )
        )
        searchBar.attachShadow()
        cachedExploreVC?.let { searchBar.setupBlurWith(it.view) }
        mountActiveTab()
        sidePanel.setSelectedTab(currentTabId)
        updateSearchVisibility()
        adoptPendingSearchText()
        updateTheme()
        applyPanelInsets()
        homeVCInRightPanel()
        contentNav.viewWillAppear()
        contentNav.viewDidAppear()
        view.doOnPreDraw {
            applyPanelWidth()
            refreshHeader(animated = false)
            sidePanel.setAccounts(WalletCore.getAllAccounts())
            sidePanel.onLaidOut()
            contentNav.insetsUpdated()
            activeNavigationController?.insetsUpdated()
            updateSearchBarPosition()
            adoptPendingPushedOverMain()
        }
        WalletCore.doOnBridgeReady {
            refreshHeader(animated = false)
        }
        precacheReceiveBackground()
    }

    private fun homeVCInRightPanel(): HomeVC? {
        return (navForOrNull(IBottomNavigationView.ID_HOME)
            ?.viewControllers?.firstOrNull() as? HomeVC)
            ?.also { it.panelHeaderView = sidePanel.headerView }
    }

    override fun navStackUpdated(nav: WNavigationController) {
        if (nav.parent != contentPanel)
            return
        syncPanelHeaderAccounts()
    }

    private fun syncPanelHeaderAccounts() {
        val activeHome =
            contentNav.viewControllers.lastOrNull { it is HomeVC } as? HomeVC
        activeHome?.panelHeaderView = sidePanel.headerView
        val override = activeHome?.overrideAccountIds
        if (headerView.overrideAccountIds.contentEquals(override))
            return
        headerView.overrideAccountIds = override
        refreshHeader(animated = false)
    }

    private fun presentWalletSettings() {
        val navVC = WNavigationController(
            window!!, WNavigationController.PresentationConfig(
                style = WNavigationController.PresentationStyle.BottomSheet
            )
        )
        navVC.setRoot(
            WalletsTabsVC(
                context,
                WGlobalStorage.getAccountSelectorViewMode() ?: MWalletSettingsViewMode.GRID
            )
        )
        window?.present(navVC)
    }

    private fun presentAddAccount() {
        val navVC = WNavigationController(
            window!!, WNavigationController.PresentationConfig(
                style = WNavigationController.PresentationStyle.BottomSheet
            )
        )
        navVC.setRoot(
            WalletContextManager.delegate?.get()
                ?.getAddAccountVC(MBlockchainNetwork.MAINNET) as WViewController
        )
        window?.present(navVC)
    }

    private fun onAccountSelected(account: MAccount) {
        if (account.accountId == AccountStore.activeAccountId)
            return
        WalletCore.activateAccount(account.accountId, notifySDK = true) { res, _ ->
            if (res != null) {
                WalletCore.notifyEvent(
                    WalletEvent.AccountChangedInApp(persistedAccountsModified = false)
                )
            }
        }
    }

    private fun selectTab(id: Int) {
        if (id == currentTabId) return
        contentNav.popToRoot(animated = false)
        navForOrNull(currentTabId)?.viewWillDisappear()
        currentTabId = id
        mountActiveTab()
        sidePanel.setSelectedTab(id)
        updateSearchVisibility()
    }

    private val isExploreTab: Boolean
        get() = currentTabId == IBottomNavigationView.ID_EXPLORE

    private fun updateSearchVisibility() {
        val visible = isExploreTab
        if (visible == (searchBar.isVisible))
            return
        if (!visible && searchBar.editText.hasFocus())
            searchBar.editText.clearFocus()
        searchBar.visibility = if (visible) View.VISIBLE else View.INVISIBLE
        searchBar.syncShadow()
        activeNavigationController?.insetsUpdated()
    }

    override fun onExploreCreated(exploreVC: ExploreVC) {
        searchBar.setupBlurWith(exploreVC.view)
    }

    override fun exportSearchText(): String = searchBar.currentText()

    override fun restoreSearchText(text: String) {
        searchBar.restoreText(text)
    }

    private fun presentSearchBrowser(config: InAppBrowserConfig) {
        val window = window ?: return
        val inAppBrowserVC = InAppBrowserVC(context, this, config)
        val nav = WNavigationController(window)
        nav.setRoot(inAppBrowserVC)
        window.present(nav, onCompletion = {
            searchBar.editText.setText("")
        })
        searchBar.editText.clearFocus()
        searchBar.hideKeyboard()
    }

    private fun mountActiveTab() {
        val newNav = getNavigationStack(currentTabId)
        if (newNav.parent === contentHostVC.contentParent) return
        contentHostVC.setContent(newNav)
        newNav.viewWillAppear()
        newNav.viewDidAppear()
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
        sidePanel.updateTheme()
        applyPillShadowBottom()
        pillShadow?.updateTheme()
        searchBar.updateTheme()
        for (nav in navStacks) {
            if (nav.parent != null)
                continue
            nav.updateTheme()
        }
    }

    private fun updateSearchBarPosition() {
        val keyboard = window?.imeInsets?.bottom ?: 0
        val systemBottom = window?.systemBars?.bottom ?: 0
        val bottomInset = maxOf(systemBottom, keyboard)
        searchBar.translationY = -(SEARCH_BOTTOM_MARGIN.dp + bottomInset).toFloat()
        val leadingGutter = ViewConstants.ADDITIONAL_TABLET_PADDING - systemBarEndInset
        val isRtl = view.layoutDirection == View.LAYOUT_DIRECTION_RTL
        searchBar.translationX = (leadingGutter / 2f) * (if (isRtl) -1f else 1f)
        searchBar.updateWidth()
        searchBar.syncShadow()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
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
        contentNav.viewWillDisappear()
    }

    override fun onSizeChanged(w: Int, h: Int, oldW: Int, oldH: Int) {
        super.onSizeChanged(w, h, oldW, oldH)
        if (w != oldW)
            view.doOnPreDraw { applyPanelWidth() }
    }

    private fun applyPillShadowBottom() {
        val gradientNav = WGlobalStorage.isGradientNavigationBarActive()
        pillShadow?.setBottomCornerRadius(if (gradientNav) 0f else ViewConstants.TOOLBAR_RADIUS.dp)
        pillShadow?.setBottomInset(if (gradientNav) 0f else sidePanel.contentBottomInset.toFloat())
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        applyPanelInsets()
        applyPanelWidth()
        sidePanel.updateInsets()
        applyPillShadowBottom()
        contentNav.insetsUpdated()
        // The per-tab nav inside the host needs its insets too when it's the visible content.
        if (!isShowingPushedOverMain)
            activeNavigationController?.insetsUpdated()
        if (!isKeyboardOpen && searchBar.editText.hasFocus()) {
            searchBar.editText.clearFocus()
        }
        if (searchBar.searchMatchedSite != null && !isKeyboardOpen) {
            searchBar.clearSearchAutoComplete()
        }
        updateSearchBarPosition()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                if (!AccountStore.isPushedTemporary && !walletEvent.isSavingTemporaryAccount) {
                    activeNavigationController?.popToRoot(false)
                    mainNavigationController?.popToRoot(false)
                }
                refreshHeader(animated = false)
                sidePanel.refreshAccountSelection()
            }

            is WalletEvent.AccountWillChange -> {
                // Status is handled by HomeStatusController; nothing tablet-specific to do here, but
                // keep the branch so the event isn't routed as a generic wallet event.
            }

            is WalletEvent.AccountChangedInApp -> {
                activeNavigationController?.popToRoot(false)
                if (!AccountStore.isPushedTemporary)
                    mainNavigationController?.popToRoot(false)
                sidePanel.setAccounts(WalletCore.getAllAccounts())
                sidePanel.refreshAccountSelection()
                refreshHeader(animated = false)
            }

            WalletEvent.AddNewWalletCompletion -> {
                if (currentTabId != IBottomNavigationView.ID_HOME)
                    selectTab(IBottomNavigationView.ID_HOME)
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

            WalletEvent.SideGuttersChanged -> {
                applyPanelInsets()
                applyPanelWidth()
            }

            else -> {
                routeWalletEvent(walletEvent)
            }
        }
    }

    override fun onBackPressed(): Boolean {
        // Pop full-screen VCs pushed over the main nav first, then fall back to the active tab stack.
        if ((contentNav.viewControllers.size) > 1)
            return contentNav.onBackPressed()
        return activeNavigationController?.onBackPressed() ?: true
    }

    private val isShowingPushedOverMain: Boolean
        get() = contentNav.viewControllers.size > 1

    // ITabsVC /////////////////////////////////////////////////////////////////////////////////////
    override val mainNavigationController: WNavigationController?
        get() = contentNav

    // Full-screen pushes on tablet live in the content-panel nav, above the host root.
    override fun exportPushedOverMain(): List<WViewController> {
        return contentNav.detachAboveRoot()
    }

    override fun adoptPushedOverMain(pushed: List<WViewController>) {
        contentNav.adoptAboveRoot(pushed)
    }

    override val activeNavigationController: WNavigationController?
        get() = navForOrNull(currentTabId)

    override val bottomNavigationView: FrameLayout? = null

    override fun getBottomNavigationHeight(): Int {
        val systemBottom = window?.systemBars?.bottom ?: 0
        val keyboard = window?.imeInsets?.bottom ?: 0
        val searchExtra = if (isExploreTab)
            (SEARCH_BOTTOM_MARGIN + ExploreSearchBar.SEARCH_HEIGHT).dp
        else 0
        return maxOf(systemBottom, keyboard) + searchExtra
    }

    override fun minimize(
        nav: WNavigationController,
        onProgress: (progress: Float) -> Unit,
        onMaximizeProgress: (progress: Float) -> Unit
    ) {
        // Minimized browser nav not supported on tablet (v1). Keep nav fully presented.
        onMaximizeProgress(1f)
    }

    override fun maximize() {}
    override fun dismissMinimized(animated: Boolean) {}
    override fun scrollingUp() {}
    override fun scrollingDown() {}
    override val pausedBlurViews: Boolean get() = sidePanel.pausedBlurViews
    override fun pauseBlurring() {}
    override fun resumeBlurring() {}

    override fun setSearchText(text: String) {
        selectTab(IBottomNavigationView.ID_EXPLORE)
        searchBar.setSearchText(text)
    }

    override fun switchToFirstTab(): Boolean {
        if (currentTabId != IBottomNavigationView.ID_HOME) {
            selectTab(IBottomNavigationView.ID_HOME)
            return true
        }
        return false
    }

    // Tab-container navigation surface ////////////////////////////////////////////////////////////
    override val isOnHomeScreen: Boolean
        get() = currentTabId == IBottomNavigationView.ID_HOME &&
            window?.topViewController == this &&
            (activeNavigationController?.viewControllers?.size ?: 0) == 1

    override fun switchToExplore(targetUri: Uri?) {
        selectTab(IBottomNavigationView.ID_EXPLORE)
        window?.dismissToRoot()
        targetUri?.let { cachedExploreVC?.findSiteAndOpenTargetUri(it) }
    }

    override fun switchToAgent() {
        selectTab(IBottomNavigationView.ID_AGENT)
        window?.dismissToRoot()
    }

    override fun switchToSettings(pushVC: WViewController?) {
        selectTab(IBottomNavigationView.ID_SETTINGS)
        window?.dismissToRoot()
        pushVC?.let { activeNavigationController?.push(it) }
    }

    override fun hideTabBar() {}
    override fun showTabBar() {}

    override fun onDestroy() {
        super.onDestroy()
        panelStartAnimator?.cancel()
        panelStartAnimator = null
        HomeStatusController.removeListener(statusListener)
        WalletCore.unregisterObserver(this)
        contentHostVC.detachContent()
        contentNav.onDestroy()
        sidePanel.onDestroy()
    }
}
