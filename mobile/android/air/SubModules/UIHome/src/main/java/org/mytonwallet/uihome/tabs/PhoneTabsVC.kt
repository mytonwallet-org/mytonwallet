package org.mytonwallet.uihome.tabs

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
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.net.toUri
import androidx.core.view.children
import androidx.core.view.doOnLayout
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.widget.doAfterTextChanged
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
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
        private const val SEARCH_HINT_KEY = "Search or Ask"

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

        private val PUSHED_TAB_IDS = setOf(
            AppTabsManager.ID_AGENT,
            AppTabsManager.ID_SETTINGS
        )

        private val UPDATE_BUTTON_AVAILABLE_TABS = setOf(
            AppTabsManager.ID_HOME,
            AppTabsManager.ID_SETTINGS
        )

        private const val GRADIENT_ALPHA = 229
    }

    override val isSwipeBackAllowed = false
    override var ignoreSideGuttering = false

    override var currentTabId: Int
        get() = selectedTabId
        set(value) {
            if (value in PUSHED_TAB_IDS) {
                pendingSelectedTab = AppTabsManager.ID_HOME
                pendingTabToPresentOverMain = value
            } else {
                pendingSelectedTab = value
            }
        }
    private var pendingSelectedTab: Int? = null
    private var pendingTabToPresentOverMain: Int? = null

    override fun exportSearchText(): String = if (searchMatchedSite != null) {
        searchKeyword
    } else {
        (searchEditText.text?.toString() ?: "")
    }

    override fun restoreSearchText(text: String) {
        searchEditText.setText(text)
    }

    override fun detachMountedStacks() {
        // The stacks live inside the pager's pages rather than directly in contentView;
        // exportStacks() removes each nav from its own parent.
        contentView.removeAllViews()
    }

    private val contentView = WView(context)

    private inner class TabPageHolder(val page: TabPageView) : RecyclerView.ViewHolder(page)

    private inner class TabPagerAdapter : RecyclerView.Adapter<TabPageHolder>() {
        init {
            setHasStableIds(true)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
            TabPageHolder(TabPageView(context, tabPager))

        override fun onBindViewHolder(holder: TabPageHolder, position: Int) {
            holder.page.bind(getNavigationStack(topTabIds[position]))
        }

        override fun onViewRecycled(holder: TabPageHolder) {
            holder.page.unbind()
        }

        override fun getItemCount(): Int = topTabIds.size

        override fun getItemId(position: Int): Long = topTabIds[position].toLong()
    }

    private var updateFloatingButton: WLabel? = null
    private var updateFloatingButtonBackground: WRippleDrawable? = null
    private var stickyBackgroundColor =
        if (ThemeManager.isDark) WColor.SecondaryBackground.color else WColor.Background.color

    override val minimizedBlurRootView: ViewGroup?
        get() = contentView
    val bottomBarHeight: Int
        get() {
            return (window?.systemBars?.bottom ?: 0) + (-2).dp
        }

    override fun rootTopInsetForTab(id: Int): Int {
        if (id == AppTabsManager.ID_SETTINGS) return 0
        return (WNavigationBar.DEFAULT_HEIGHT + 2).dp
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
        updateTopChromeVisibility(itemId)
        checkForUpdate(itemId)
        val isAgent = itemId == AppTabsManager.ID_AGENT
        ignoreSideGuttering = isAgent
        val wasAgent = selectedTabId == AppTabsManager.ID_AGENT
        if (wasAgent != isAgent) updateStickyBottomGradient(itemId)
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
    }

    private var topTabIds = emptyList<Int>()
    private val tabPagerAdapter = TabPagerAdapter()
    private var pendingTabAppearance: WNavigationController? = null
    private val tabPager by lazy {
        ViewPager2(context).apply {
            id = View.generateViewId()
            adapter = tabPagerAdapter
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
                        selectedTabId != tabId
                    ) {
                        selectTab(tabId)
                    }
                    completePendingTabAppearance()
                }
            })
            (getChildAt(0) as? RecyclerView)?.itemAnimator = null
            setupSpringFling { it }
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
        val animated = WGlobalStorage.getAreAnimationsActive()
        if (animated && previousIndex != index && tabPager.width > 0) {
            tabPager.springToItem(index) {
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
            setOnLongClickListener { presentWalletSwitcherPopup(it) }
        }
    }
    private var topAvatarGlass: WGlassView? = null
    private var isTopChromeHidden = false

    private fun reloadTopTabs(selectedItemId: Int = selectedTabId) {
        val tabs = AppTabsManager.orderedTabs.filter {
            it.intId !in PUSHED_TAB_IDS
        }
        topTabIds = tabs.map { it.intId }
        val requestedIndex = topTabIds.indexOf(selectedItemId)
        val selectedIndex = requestedIndex.coerceAtLeast(0)
        if (requestedIndex < 0) {
            // The requested tab has no page (e.g. Agent/Settings, which are pushed instead), so
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
                    onClick = null
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

    private fun updateTopChromeVisibility(selectedItemId: Int) {
        val shouldShowTabs =
            !isTopChromeHidden && selectedItemId != AppTabsManager.ID_SETTINGS
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
        get() = listOfNotNull(searchGlass, actionsButtonGlass, topTabsGlass, topAvatarGlass)
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
            hint = LocaleController.getString(SEARCH_HINT_KEY)
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
        val fraction = searchFocused.floatValue
        actionsButton.contentDescription = LocaleController.getString(
            if (searchEditText.hasFocus()) "Close" else "More actions"
        )
        actionsButtonIcon.rotation = 45f * fraction
        actionsButtonIcon.setColorFilter(WColor.SecondaryText.color)
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

    private fun showSearchChrome() {
        searchView.alpha = 1f
        searchView.visibility = View.VISIBLE
        actionsButton.alpha = 1f
        actionsButton.visibility = View.VISIBLE
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
            updateSearchPadding()
            updateActionsButtonMorph()
        }

    private fun render() {
        syncToastHostPosition()
        syncUpdateButtonPosition()
        updateSearchPosition()
        updateStickyGradientHeight()
        onUpdateAdditionalHeight()
    }

    private fun updateSearchPosition() {
        searchView.translationY = -(searchTopOffset() - SEARCH_HEIGHT.dp)
        actionsButton.translationY = searchView.translationY
    }

    private fun onUpdateAdditionalHeight() {
        activeNavigationController?.insetsUpdated()
        // The search overlay reserves the same bottom height, so it has to follow the keyboard too.
        searchOverlayNav?.insetsUpdated()
    }

    private fun updateSearchPadding() {
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

        view.addView(contentView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(toastHostView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(searchView, ConstraintLayout.LayoutParams(0, SEARCH_HEIGHT.dp))
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
        HomeStatusController.addListener(topAvatarStatusListener)
        view.setConstraints {
            val searchHorizontalMargin =
                (ViewConstants.HORIZONTAL_PADDINGS + 6).toFloat()
            toStart(searchView, searchHorizontalMargin)
            endToStart(searchView, actionsButton, ACTIONS_BUTTON_GAP.toFloat())
            toBottom(searchView)
            toEnd(actionsButton, searchHorizontalMargin)
            toBottom(actionsButton)
            toCenterX(toastHostView)
            toBottom(toastHostView)
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

        searchEditText.highlightColor = tintColor.colorWithAlpha(51)
        isProcessingSearchKeyword = true
        checkForMatchingUrl(searchKeyword)
        isProcessingSearchKeyword = false

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
        updateToastAvailability()
        // Re-host any full-screen VCs carried over from the tablet container, now that this VC is the
        // root of the window nav (which is the phone's main navigation controller).
        val tabToPresentOverMain = pendingTabToPresentOverMain
        if (tabToPresentOverMain != null) {
            pendingTabToPresentOverMain = null
            val stack = detachNavigationStack(tabToPresentOverMain).ifEmpty {
                listOf(
                    when (tabToPresentOverMain) {
                        AppTabsManager.ID_AGENT -> AgentVC(context)
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
        val pushedRoot = navigationController?.viewControllers?.getOrNull(1)
        return when (pushedRoot) {
            is SettingsVC -> AppTabsManager.ID_SETTINGS
            is AgentVC -> AppTabsManager.ID_AGENT
            else -> selectedItemId
        }
    }

    // Full-screen pushes on phone live in the window nav, above this PhoneTabsVC root.
    override fun exportPushedOverMain(): List<WViewController> {
        val pushed = navigationController?.detachAboveRoot() ?: return emptyList()
        val tabId = when (pushed.firstOrNull()) {
            is SettingsVC -> AppTabsManager.ID_SETTINGS
            is AgentVC -> AppTabsManager.ID_AGENT
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
                (if (minimizedBrowser.hasNavigation) 56.dp else 0)
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
        if (searchMatchedSite != null && !isKeyboardOpen) {
            clearSearchAutoComplete()
        }
        updateSearchPadding()
        updateStickyGradientHeight()
    }

    private val shouldShowStickyBottomGradientView: Boolean
        get() = WGlobalStorage.isGradientNavigationBarActive()

    private val bottomOverlayExtraGap: Int
        get() = if (shouldShowStickyBottomGradientView) 0 else BOTTOM_EXTRA_GAP.dp

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
        if (topTabsControl.parent != null) {
            topAvatarGlass?.bringToFront()
            topAvatarView.bringToFront()
            topTabsGlass?.bringToFront()
            topTabsControl.bringToFront()
        }
        searchOverlayNav?.bringToFront()
        bottomReversedCornerView?.bringToFront()
        stickyBottomGradientView?.bringToFront()
        minimizedBrowser.bringToFront()
        searchGlass?.bringToFront()
        searchView.bringToFront()
        actionsButtonGlass?.bringToFront()
        actionsButton.bringToFront()
        toastHostView.bringToFront()
    }

    private fun stickyGradientFullHeight(): Int = bottomBarHeight +
        minimizedBrowser.height.roundToInt() +
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

    private fun updateStickyBottomGradient(selectedItemId: Int = selectedTabId) {
        if (shouldShowStickyBottomGradientView) {
            if (stickyBottomGradientView == null) {
                val gradientView = ensureStickyBottomGradientView()
                view.setConstraints {
                    toBottom(gradientView)
                }
            }
            stickyBackgroundColor =
                if (ThemeManager.isDark && selectedItemId != AppTabsManager.ID_AGENT) {
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

    override fun switchToAgent(prompt: String?, pinnedMessageId: String?): Boolean {
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
                dismissMinimized(false)
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
        val additionalHeight = (
            (SEARCH_BOTTOM_MARGIN + SEARCH_HEIGHT + SEARCH_TOP_MARGIN).dp +
                keyboardHeight +
                minimizedBrowser.height
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
            tabPager.isUserInputEnabled = true
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
            selectedTabId != AppTabsManager.ID_SETTINGS
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
        if (cachedExploreVC == null) getNavigationStack(AppTabsManager.ID_EXPLORE)
        val exploreVC = cachedExploreVC ?: return
        exploreVC.search(
            query,
            focused,
            targetNavigationController = searchOverlayNavigationController,
            isGlobalSearch = true
        )
    }

    private val minimizedBrowser by lazy {
        MinimizedBrowserPresenter(object : MinimizedBrowserPresenter.Host {
            override val container get() = view
            override val availableHeight get() = view.height.takeIf { it > 0 }
                ?: (window?.windowView?.height ?: 0)
            override val animationsEnabled get() = WGlobalStorage.getAreAnimationsActive()
            override val bottomInset get() = bottomBarHeight + bottomOverlayExtraGap
            override fun canMinimize(nav: WNavigationController) =
                window?.navigationControllers?.lastOrNull() === nav
            override fun detach(nav: WNavigationController) {
                nav.window.detachLastNav()
            }
            override fun attach(nav: WNavigationController) {
                window?.attachNavigationController(nav)
            }
            override fun destroy(nav: WNavigationController) {
                nav.willBeDismissed()
                view.removeView(nav)
                nav.onDestroy()
            }
            override fun render() = this@PhoneTabsVC.render()
            override fun restack() = restackChromeAboveGradient()
        })
    }

    override fun minimize(
        nav: WNavigationController,
        onProgress: (Float) -> Unit,
        onMaximizeProgress: (Float) -> Unit
    ) = minimizedBrowser.minimize(nav, onProgress, onMaximizeProgress)

    override fun maximize() = minimizedBrowser.maximize(WGlobalStorage.getAreAnimationsActive())

    fun maximize(animated: Boolean) = minimizedBrowser.maximize(animated)

    override fun dismissMinimized(animated: Boolean) = minimizedBrowser.dismissMinimized(animated)

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
        tabPager.isUserInputEnabled = true
        topTabsControl.isEnabled = true
        topAvatarView.isEnabled = true
        val shouldShowTabs = selectedTabId != AppTabsManager.ID_SETTINGS
        val shouldShowAvatar = shouldShowTabs && AccountStore.activeAccount != null
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
    private fun searchTopOffset(): Float = bottomBarHeight +
        keyboardVisible.value.coerceAtLeast(0f) +
        minimizedBrowser.height +
        3.dp + bottomOverlayExtraGap +
        SEARCH_HEIGHT.dp

    override fun onDestroy() {
        super.onDestroy()
        HomeStatusController.removeListener(topAvatarStatusListener)
        minimizedBrowser.dispose()
        searchOverlayNav?.let { nav ->
            nav.viewControllers.forEach { it.viewWillDisappear() }
            view.removeView(nav)
            nav.onDestroy()
        }
        searchOverlayNav = null
    }
}
