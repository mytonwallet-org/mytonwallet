package org.mytonwallet.uihome.tabs

import android.animation.ValueAnimator
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Rect
import android.net.Uri
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import androidx.core.animation.doOnEnd
import androidx.core.net.toUri
import androidx.core.view.children
import androidx.core.view.get
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.widget.doOnTextChanged
import org.mytonwallet.uihome.tabs.views.FloatingBottomNavigationView
import org.mytonwallet.uihome.tabs.views.IBottomNavigationView
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import me.vkryl.android.animatorx.FloatAnimator
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC.CollectionMode
import org.mytonwallet.app_air.uiassets.viewControllers.token.TokenVC
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WMinimizableBlurHost
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WNavigationController.PresentationConfig
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.AccountItemView
import org.mytonwallet.app_air.uicomponents.drawable.StickyBottomGradientDrawable
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.IPopup
import org.mytonwallet.app_air.uicomponents.widgets.PillShadowView
import org.mytonwallet.app_air.uicomponents.widgets.SwapSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uireceive.ReceiveBackgroundCache
import org.mytonwallet.app_air.uisettings.viewControllers.settings.SettingsVC
import org.mytonwallet.app_air.uitransaction.viewControllers.transaction.TransactionVC
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import org.mytonwallet.app_air.walletbasecontext.utils.toUriOrNull
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.helpers.SubprojectHelpers
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.models.MScreenMode
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.EnvironmentStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.uihome.home.HomeVC
import org.mytonwallet.uihome.home.promotion.PromotionVC
import kotlin.math.roundToInt

class TabsVC(context: Context) : WViewController(context), WThemedView, WProtectedView,
    WalletCore.EventObserver,
    WNavigationController.ITabBarController {
    override val TAG = "Tabs"

    companion object {
        const val SEARCH_HEIGHT = 48
        const val SEARCH_TOP_MARGIN = 4
        const val SEARCH_BOTTOM_MARGIN = 10

        const val BOTTOM_TABS_LAYOUT_HEIGHT = 75
        const val BOTTOM_TABS_BOTTOM_MARGIN = -7
        const val BOTTOM_TABS_BOTTOM_TO_NAV_DIFF = 2

        private val UPDATE_BUTTON_AVAILABLE_TABS = setOf(
            IBottomNavigationView.ID_HOME,
            IBottomNavigationView.ID_SETTINGS
        )

        private const val GRADIENT_ALPHA = 229
        private const val COLLAPSED_GRADIENT_STOP_POINT = 1 - (GRADIENT_ALPHA / 255f)
    }

    override val isSwipeBackAllowed = false
    override val shouldDisplayBottomBar: Boolean
        get() {
            return !WGlobalStorage.isGradientNavigationBarActive()
        }
    override var ignoreSideGuttering = false

    private var stackNavigationControllers = HashMap<Int, WNavigationController>()
    private val contentView = WView(context)

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

    private var isSwitchingTabs = false

    private val tabListener = object : IBottomNavigationView.Listener {
        override fun onTabSelected(itemId: Int, isReselect: Boolean): Boolean {
            if (isReselect) {
                stackNavigationControllers[itemId]?.apply {
                    if (viewControllers.size == 1) scrollToTop() else popToRoot()
                }
                return true
            }
            if (isSwitchingTabs) return false

            checkForUpdate(itemId)
            val isAgent = itemId == IBottomNavigationView.ID_AGENT
            ignoreSideGuttering = isAgent
            val wasAgent = bottomNavigationView.selectedItemId == IBottomNavigationView.ID_AGENT
            if (wasAgent != isAgent)
                updateBottomNavigationBackground(itemId)
            bottomReversedCornerView?.setHorizontalPadding(
                if (ignoreSideGuttering)
                    0f
                else
                    ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat()
            )

            val newNav = getNavigationStack(itemId)
            if (newNav.parent != null)
                return true // switching navigation bottom bar view type

            val oldNav = contentView[0] as? WNavigationController
            oldNav?.viewWillDisappear()

            val searchVisible = itemId == IBottomNavigationView.ID_EXPLORE
            if (searchView.hasFocus() && !searchVisible)
                searchView.clearFocus()

            val animationsEnabled = WGlobalStorage.getAreAnimationsActive()

            if (animationsEnabled) {
                if (searchVisible) {
                    searchView.visibility = View.VISIBLE
                    searchShadow?.sync()
                }
                searchView.animate()
                    .alpha(if (searchVisible) 1f else 0f)
                    .setDuration(AnimationConstants.VERY_VERY_QUICK_ANIMATION)
                    .setInterpolator(CubicBezierInterpolator.EASE_OUT)
                    .setUpdateListener { searchShadow?.sync() }
                    .withEndAction {
                        if (!searchVisible) {
                            searchView.visibility = View.INVISIBLE
                        }
                        searchShadow?.sync()
                    }
                    .start()

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
                        newNav.viewDidAppear()
                        bottomNavigationView.post { onUpdateAdditionalHeight() }
                    }
                    .start()
            } else {
                searchView.alpha = if (searchVisible) 1f else 0f
                searchView.visibility = if (searchVisible) View.VISIBLE else View.INVISIBLE
                searchShadow?.sync()

                oldNav?.let { contentView.removeView(it) }
                contentView.addView(
                    newNav,
                    ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                )
                newNav.viewWillAppear()
                newNav.viewDidAppear()
                view.post { onUpdateAdditionalHeight() }
            }
            return true
        }
    }

    override val bottomNavigationView: IBottomNavigationView =
        FloatingBottomNavigationView(context, contentView).also { it.listener = tabListener }

    var isProcessingSearchKeyword = false
    private val searchBlurryBackgroundView = WBlurryBackgroundView(context, fadeSide = null).apply {
        setOverlayColor(WColor.SearchFieldBackground, 204)
    }
    private val searchEditText by lazy {
        object : SwapSearchEditText(context) {
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
                if (isProcessingSearchKeyword || searchMatchedSite == null)
                    return

                isProcessingSearchKeyword = true
                setTextKeepCursor(searchKeyword)
                searchMatchedSite = null
                isProcessingSearchKeyword = false
            }
        }.apply {
            hint =
                LocaleController.getString("Search app or enter address")
            doOnTextChanged { text, start, _, count ->
                if (text != null && text == searchKeyword)
                    return@doOnTextChanged
                if (isProcessingSearchKeyword)
                    return@doOnTextChanged
                isProcessingSearchKeyword = true
                if ((text?.length ?: 0) > searchKeyword.length)
                    checkForMatchingUrl(text?.toString() ?: "")
                else {
                    searchKeyword = text?.toString() ?: ""
                    searchMatchedSite = null
                }
                if (searchMatchedSite == null) {
                    val cursorPosition = start + count
                    setText(searchKeyword)
                    setSelection(cursorPosition.coerceAtMost(searchKeyword.length))
                }
                cachedExploreVC?.search(searchKeyword, hasFocus())
                post {
                    isProcessingSearchKeyword = false
                }
            }
            onFocusChangeListener = View.OnFocusChangeListener { _, hasFocus ->
                if (isProcessingSearchKeyword)
                    return@OnFocusChangeListener
                isProcessingSearchKeyword = true
                val query = if (hasFocus) text?.toString() else null
                cachedExploreVC?.search(query, hasFocus)
                checkForMatchingUrl(query ?: "")
                post {
                    isProcessingSearchKeyword = false
                }
            }
            setOnEditorActionListener { _, actionId, event ->
                if (actionId == EditorInfo.IME_ACTION_DONE ||
                    event?.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_ENTER
                ) {
                    val config = searchMatchedSite?.let { searchMatchedSite ->
                        InAppBrowserConfig(
                            url = searchMatchedSite.url,
                            injectDappConnect = true,
                            saveInVisitedHistory = true
                        )
                    } ?: run {
                        val (isValidUrl, uri) = InAppBrowserVC.convertToUri(text.toString())
                        if (!isValidUrl)
                            ExploreHistoryStore.saveSearchHistory(text.toString())
                        InAppBrowserConfig(
                            url = uri.toString(),
                            injectDappConnect = true,
                            saveInVisitedHistory = isValidUrl
                        )
                    }
                    val inAppBrowserVC = InAppBrowserVC(
                        context,
                        this@TabsVC,
                        config
                    )
                    val nav = WNavigationController(window!!)
                    nav.setRoot(inAppBrowserVC)
                    window!!.present(nav, onCompletion = {
                        setText("")
                    })
                    clearFocus()
                    hideKeyboard()
                }
                false
            }
        }
    }
    private var searchShadow: PillShadowView? = null
    private val searchView by lazy {
        object : WFrameLayout(context) {
            override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
                super.onLayout(changed, left, top, right, bottom)
                if (changed)
                    searchShadow?.sync()
            }
        }.apply {
            alpha = 0f
            visibility = View.INVISIBLE
            translationY = -SEARCH_BOTTOM_MARGIN.dp.toFloat()
            addView(
                searchBlurryBackgroundView,
                FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            )
            setBackgroundColor(Color.TRANSPARENT, 24f.dp, clipToBounds = true)
            addView(searchEditText, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    val searchWidth by lazy {
        val hintWidth = searchEditText.paint.measureText(
            LocaleController.getString("Search app or enter address")
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
        }

    private fun render() {
        val keyboardHeight = keyboardVisible.value.coerceAtLeast(0f)
        val minimizedNavHeightPx = minimizedNavHeight ?: 0f

        val tabsHeight =
            BOTTOM_TABS_LAYOUT_HEIGHT.dp +
                BOTTOM_TABS_BOTTOM_MARGIN.dp

        val contentHeight = tabsHeight + keyboardHeight + minimizedNavHeightPx

        val hiddenTranslationY = (1f - visibilityFraction) * contentHeight

        // Alpha
        bottomNavigationView.alpha = visibilityFraction
        minimizedNav?.alpha = visibilityFraction

        // Bottom navigation height
        bottomNavigationView.layoutParams?.let { params ->
            val newHeight =
                bottomBarHeight +
                    (visibilityFraction * contentHeight).roundToInt() +
                    ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()

            if (params.height != newHeight) {
                params.height = newHeight
                bottomNavigationView.layoutParams = params
            }
        }

        // Bottom navigation translation
        bottomNavigationView.translationY =
            (contentHeight -
                (BOTTOM_TABS_LAYOUT_HEIGHT.dp +
                    BOTTOM_TABS_BOTTOM_MARGIN.dp +
                    minimizedNavHeightPx) +
                BOTTOM_TABS_BOTTOM_TO_NAV_DIFF.dp * visibilityFraction)

        stickyBottomGradientDrawable?.setStops(computeGradientStops(visibilityFraction))

        // Minimized nav animation
        if (activeVisibilityValueAnimator?.isRunning == true) {
            minimizedNav?.let { nav ->
                nav.y = minimizedNavY!! + hiddenTranslationY
                minimizedNavShadow?.let {
                    applyMinimizedShadowProgress(
                        nav, it.alpha, nav.width, nav.height, 24.dp.toFloat()
                    )
                }
            }
        }
        onUpdateAdditionalHeight()
    }

    private fun onUpdateAdditionalHeight() {
        activeNavigationController?.insetsUpdated()
    }

    private fun updateSearchWidth() {
        if (searchView.layoutParams != null)
            searchView.layoutParams = searchView.layoutParams.apply {
                width = lerp(
                    searchWidth.toFloat(),
                    view.width - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp - 20f.dp,
                    searchFocused.floatValue
                ).roundToInt()
            }
        searchEditText.setPaddingDp(
            lerp(21f, 16f, searchFocused.floatValue).ceilToInt(),
            0,
            lerp(0f, 48f, searchFocused.floatValue).ceilToInt(),
            0
        )
    }

    override fun setupViews() {
        super.setupViews()

        setTopBlur(visible = false, animated = false)

        WalletCore.registerObserver(this)

        bottomNavigationView.clipChildren = false
        bottomNavigationView.clipToPadding = false

        view.addView(contentView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(bottomNavigationView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            searchView,
            FrameLayout.LayoutParams(searchWidth, SEARCH_HEIGHT.dp, Gravity.BOTTOM)
        )
        searchShadow = PillShadowView.attachTo(searchView, 24f.dp)
        ensureStickyBottomGradientView()
        view.setConstraints {
            toCenterX(searchView)
            bottomToTop(searchView, bottomNavigationView)
            toBottom(bottomNavigationView)
            toCenterX(bottomNavigationView)
            stickyBottomGradientView?.let {
                toBottom(it)
            }
        }

        contentView.addView(
            getNavigationStack(IBottomNavigationView.ID_HOME),
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        view.post {
            activeNavigationController?.insetsUpdated()
            // preload other tabs
            getNavigationStack(IBottomNavigationView.ID_EXPLORE)
            getNavigationStack(IBottomNavigationView.ID_SETTINGS)
        }

        bottomNavigationView.post {
            setupWalletSwitcherPopup()
        }
        checkForUpdate()
        updateTheme()
        WalletCore.doOnBridgeReady {
            val prioritized = AccountStore.activeAccount?.sortedChains()?.mapNotNull { entry ->
                MBlockchain.supportedChains.find { it.name == entry.key }
            } ?: emptyList()
            ReceiveBackgroundCache.precache(window?.systemBars?.top ?: 0, prioritized)
        }
    }

    private fun setupWalletSwitcherPopup() {
        val settingsItemView = bottomNavigationView.getSettingsItemView() ?: return
        settingsItemView.setOnLongClickListener { settingsItemView ->
            val accounts = WalletCore.getAllAccounts()
            val addAccountItem = WMenuPopup.Item(
                config = WMenuPopup.Item.Config.Item(
                    icon = WMenuPopup.Item.Config.Icon(
                        icon = org.mytonwallet.app_air.uisettings.R.drawable.ic_add,
                        tintColor = WColor.SubtitleText,
                        iconSize = 28.dp,
                        iconMargin = 17.dp
                    ),
                    title = LocaleController.getString("Add Wallet")
                ),
                hasSeparator = true,
                onTap = {
                    val nav = WNavigationController(
                        window!!,
                        PresentationConfig(
                            overFullScreen = false,
                            isBottomSheet = true,
                            aboveKeyboard = true
                        )
                    )
                    nav.setRoot(
                        WalletContextManager.delegate?.getAddAccountVC(MBlockchainNetwork.MAINNET) as WViewController
                    )
                    window?.present(nav)
                }
            )
            val freeSpaceToShowAccounts = view.height -
                (navigationController?.getSystemBars()?.top ?: 0) -
                WNavigationBar.DEFAULT_HEIGHT.dp -
                bottomNavigationView.height -
                55.dp

            val numberOfAccountsCapacity = freeSpaceToShowAccounts / 56.dp

            val numberOfAccountsToShow = when {
                numberOfAccountsCapacity < 1 -> return@setOnLongClickListener false
                accounts.size <= numberOfAccountsCapacity -> accounts.size.coerceAtMost(10)
                else -> (numberOfAccountsCapacity - 1).coerceAtMost(10)
            }

            val allAccountsShown = accounts.size <= numberOfAccountsToShow

            val showAllItem = if (allAccountsShown) null else WMenuPopup.Item(
                config = WMenuPopup.Item.Config.Item(
                    icon = WMenuPopup.Item.Config.Icon(
                        icon = org.mytonwallet.app_air.uisettings.R.drawable.ic_show_all,
                        tintColor = WColor.SubtitleText,
                        iconSize = 28.dp,
                        iconMargin = 17.dp
                    ),
                    title = LocaleController.getString("Show All Wallets")
                ),
                hasSeparator = false,
                onTap = {
                    val navVC = WNavigationController(
                        window!!, PresentationConfig(
                            overFullScreen = false,
                            isBottomSheet = true
                        )
                    )
                    navVC.setRoot(
                        WalletContextManager.delegate?.getWalletsTabsVC(
                            MWalletSettingsViewMode.LIST
                        ) as WViewController
                    )
                    window?.present(navVC)
                }
            )

            lateinit var popup: IPopup
            val menuItems =
                listOf(addAccountItem) +
                    accounts.take(numberOfAccountsToShow).mapIndexed { i, account ->
                        val hasSeparator = !allAccountsShown && i == numberOfAccountsToShow - 1
                        WMenuPopup.Item(
                            config = WMenuPopup.Item.Config.CustomView(
                                AccountItemView(
                                    context = context,
                                    accountData = AccountItemView.AccountData(
                                        accountId = account.accountId,
                                        title = account.name,
                                        network = account.network,
                                        byChain = account.byChain,
                                        accountType = account.accountType,
                                    ),
                                    showArrow = false,
                                    isTrusted = true,
                                    hasSeparator = hasSeparator,
                                    onSelect = {
                                        popup.dismiss()
                                        val isActive =
                                            account.accountId == AccountStore.activeAccountId
                                        if (isActive)
                                            return@AccountItemView
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
                                    })
                            ),
                            hasSeparator = hasSeparator
                        )
                    } +
                    listOfNotNull(showAllItem)

            popup = WMenuPopup.present(
                view = settingsItemView,
                items = menuItems,
                yOffset = 3.dp,
                positioning = WMenuPopup.Positioning.ABOVE,
                centerHorizontally = true,
                windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                    settingsItemView,
                    roundRadius = 100f.dp,
                    horizontalOffset = 0,
                    verticalOffset = (-4).dp
                )
            )
            true
        }
    }

    override fun notifyThemeChanged() {
        super.notifyThemeChanged()
        if (isDisappeared) {
            stackNavigationControllers.values.forEach {
                it.viewControllers.lastOrNull()?.pendingThemeChange = true
            }
            return
        }
    }

    override val isTinted = true
    override fun updateTheme() {
        super.updateTheme()

        val tintColor = WColor.Tint.color

        for (navView in stackNavigationControllers.values) {
            if (navView.parent != null)
                continue
            navView.updateTheme()
        }

        updateFloatingButtonBackground?.apply {
            backgroundColor = tintColor
        }
        updateBottomNavigationBackground()

        searchEditText.highlightColor = tintColor.colorWithAlpha(51)
        checkForMatchingUrl(searchKeyword)

        render()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        activeNavigationController?.viewWillAppear()
        resumeBlurring()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        activeNavigationController?.viewDidAppear()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        activeNavigationController?.viewWillDisappear()
        clearSearchAutoComplete()
    }

    override fun updateProtectedView() {
        for (navView in stackNavigationControllers.values) {
            fun updateProtectedViewForChildren(parentView: ViewGroup) {
                for (child in parentView.children) {
                    if (child is WProtectedView)
                        child.updateProtectedView()
                    if (child is ViewGroup)
                        updateProtectedViewForChildren(child)
                }
            }
            updateProtectedViewForChildren(navView)
        }
    }

    private val keyboardHeight: Float
        get() {
            return maxOf(
                (
                    (window?.imeInsets?.bottom ?: 0) -
                        (window?.systemBars?.bottom ?: 0) -
                        BOTTOM_TABS_LAYOUT_HEIGHT.dp -
                        BOTTOM_TABS_BOTTOM_MARGIN.dp -
                        (if (minimizedNav != null) 56.dp else 0)
                    ).toFloat(), 0f
            )
        }

    override fun insetsUpdated() {
        super.insetsUpdated()

        keyboardVisible.animatedValue = keyboardHeight
        onUpdateAdditionalHeight()
        bottomNavigationView.insetsUpdated(bottomBarHeight)
        searchView.translationY = ViewConstants.TOOLBAR_RADIUS.dp - SEARCH_BOTTOM_MARGIN.dp

        if (!isKeyboardOpen && searchEditText.hasFocus()) {
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

    private fun ensureStickyBottomGradientView() {
        if (stickyBottomGradientView != null)
            return
        stickyBottomGradientView = View(context).apply {
            id = View.generateViewId()
        }
        view.addView(
            stickyBottomGradientView, ViewGroup.LayoutParams(
                MATCH_PARENT, stickyGradientFullHeight()
            )
        )
        bottomNavigationView.bringToFront()
        searchShadow?.bringToFront()
        searchView.bringToFront()
    }

    private fun stickyGradientFullHeight(): Int {
        return BOTTOM_TABS_LAYOUT_HEIGHT.dp +
            BOTTOM_TABS_BOTTOM_MARGIN.dp +
            bottomBarHeight +
            (minimizedNavHeight ?: 0f).roundToInt()
    }

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

    private val expandedGradientStops = floatArrayOf(0f, 0.333f, 0.666f, 1f)

    private fun computeGradientStops(vis: Float): FloatArray {
        val full = stickyGradientFullHeight()
        val minHeight =
            ViewConstants.ADDITIONAL_GRADIENT_HEIGHT.dp + (window?.systemBars?.bottom ?: 0)
        val minRatio = if (full > 0) (minHeight / full).coerceIn(0f, 1f) else 0f
        val collapsed = floatArrayOf(
            1f - minRatio,
            1f - minRatio * COLLAPSED_GRADIENT_STOP_POINT,
            1f - minRatio * COLLAPSED_GRADIENT_STOP_POINT,
            1f
        )
        return floatArrayOf(
            lerp(collapsed[0], expandedGradientStops[0], vis),
            lerp(collapsed[1], expandedGradientStops[1], vis),
            lerp(collapsed[2], expandedGradientStops[2], vis),
            lerp(collapsed[3], expandedGradientStops[3], vis)
        )
    }

    private fun updateBottomNavigationBackground(selectedItemId: Int = bottomNavigationView.selectedItemId) {
        if (shouldShowStickyBottomGradientView) {
            if (stickyBottomGradientView == null) {
                ensureStickyBottomGradientView()
                view.setConstraints {
                    toBottom(stickyBottomGradientView!!)
                }
            }
            stickyBackgroundColor =
                if (ThemeManager.isDark && selectedItemId != IBottomNavigationView.ID_AGENT)
                    WColor.SecondaryBackground.color
                else
                    WColor.Background.color
            val drawable = StickyBottomGradientDrawable(
                intArrayOf(
                    stickyBackgroundColor.colorWithAlpha(0),
                    stickyBackgroundColor.colorWithAlpha(GRADIENT_ALPHA),
                    stickyBackgroundColor.colorWithAlpha(GRADIENT_ALPHA),
                    stickyBackgroundColor
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

    fun switchToExplore(targetUri: Uri? = null) {
        navigationController?.popToRoot(false)
        bottomNavigationView.selectedItemId = IBottomNavigationView.ID_EXPLORE
        window?.dismissToRoot()
        targetUri?.let { cachedExploreVC?.findSiteAndOpenTargetUri(it) }
    }

    fun switchToAgent() {
        navigationController?.popToRoot(false)
        bottomNavigationView.selectedItemId = IBottomNavigationView.ID_AGENT
        window?.dismissToRoot()
    }

    fun switchToSettings(pushVC: WViewController? = null) {
        navigationController?.popToRoot(false)
        bottomNavigationView.selectedItemId = IBottomNavigationView.ID_SETTINGS
        window?.dismissToRoot()
        pushVC?.let {
            navigationController?.push(it)
        }
    }

    private var cachedExploreVC: ExploreVC? = null
        set(value) {
            field = value
            value?.view?.let {
                searchBlurryBackgroundView.setupWith(it)
            }
        }

    private fun getNavigationStack(id: Int): WNavigationController {
        if (stackNavigationControllers.containsKey(id))
            return stackNavigationControllers[id]!!

        val navigationController = WNavigationController(window!!)
        navigationController.tabBarController = this
        navigationController.setRoot(
            when (id) {
                IBottomNavigationView.ID_HOME -> {
                    HomeVC(context, MScreenMode.Default)
                }

                IBottomNavigationView.ID_AGENT -> {
                    AgentVC(context)
                }

                IBottomNavigationView.ID_EXPLORE -> {
                    val b = ExploreVC(context)
                    cachedExploreVC = b
                    b
                }

                IBottomNavigationView.ID_SETTINGS -> {
                    SettingsVC(context)
                }

                else -> {
                    throw Error()
                }
            }
        )
        stackNavigationControllers[id] = navigationController
        return navigationController
    }

    override val activeNavigationController: WNavigationController?
        get() {
            return stackNavigationControllers[bottomNavigationView.selectedItemId]
        }

    private fun createUpdateButtonIfNeeded() {
        if (updateFloatingButton == null) {
            updateFloatingButton = WLabel(context).apply {
                setStyle(adaptiveFontSize(), WFont.SemiBold)
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
                    if (url.isNotEmpty())
                        window?.startActivityCatching(Intent(Intent.ACTION_VIEW, url.toUri()))
                }
            }

            view.addView(
                updateFloatingButton, ViewGroup.LayoutParams(
                    WRAP_CONTENT,
                    WRAP_CONTENT
                )
            )
            view.setConstraints {
                bottomToTop(
                    updateFloatingButton!!,
                    bottomNavigationView,
                    ViewConstants.GAP.toFloat()
                )
                toCenterX(updateFloatingButton!!)
            }
        }
    }

    private var isShowingUpdateButton = false
    private fun showUpdateButton() {
        if (isShowingUpdateButton)
            return
        isShowingUpdateButton = true
        createUpdateButtonIfNeeded()
        updateFloatingButton?.isGone = false
        updateFloatingButton?.fadeIn()
    }

    private fun hideUpdateButton() {
        if (!isShowingUpdateButton)
            return
        isShowingUpdateButton = false
        updateFloatingButton?.let { button ->
            if (button.isVisible) {
                button.fadeOut {
                    if (!isShowingUpdateButton)
                        button.isGone = true
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
        if (keyword.isEmpty())
            return
        searchMatchedSite =
            if (keyword.isEmpty() || !isKeyboardOpen)
                null
            else
                ExploreHistoryStore.exploreHistory?.visitedSites?.firstOrNull {
                    it.url.toUri().host?.startsWith(keyword) == true ||
                        it.url.startsWith(keyword)
                }
        searchMatchedSite?.let { matchedSite ->
            val urlPart = matchedSite.url.toUri().let { uri ->
                if (uri.host?.startsWith(keyword) == true) {
                    uri.host
                } else {
                    "${uri.scheme}://${uri.host}"
                }
            }
            val txt = "$urlPart — ${matchedSite.title}"
            val spannable = SpannableString(txt)
            spannable.setSpan(
                ForegroundColorSpan(WColor.Tint.color),
                (urlPart?.length ?: 0),
                txt.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            searchEditText.setText(spannable)
            val length = searchEditText.length()
            searchEditText.setSelection(
                keyword.length.coerceAtMost(length),
                txt.length.coerceAtMost(length)
            )
            searchView.post {
                searchView.scrollTo(0, 0)
            }
        }
    }

    private fun clearSearchAutoComplete() {
        searchEditText.setText(searchKeyword)
        checkForMatchingUrl(searchKeyword)
    }

    private fun canOpenExternally(url: String): Boolean {
        val scheme = url.toUriOrNull()?.scheme?.lowercase() ?: return false
        return scheme in setOf("geo", "mailto", "market", "tg")
    }

    private fun openUrl(config: InAppBrowserConfig) {
        val browserVC =
            InAppBrowserVC(
                context,
                window?.navigationControllers?.last()?.viewControllers?.last() as? TabsVC,
                config
            )
        val nav = WNavigationController(window!!)
        nav.setRoot(browserVC)
        window?.present(nav)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountChanged -> {
                if (!AccountStore.isPushedTemporary && !walletEvent.isSavingTemporaryAccount)
                    navigationController?.popToRoot(false)
            }

            is WalletEvent.TemporaryAccountSaved -> {
                navigationController?.popToRoot(false)
            }

            is WalletEvent.AccountChangedInApp, WalletEvent.AddNewWalletCompletion -> {
                if (bottomNavigationView.selectedItemId != IBottomNavigationView.ID_HOME)
                    bottomNavigationView.selectedItemId = IBottomNavigationView.ID_HOME
                dismissMinimized(false)
            }

            is WalletEvent.OpenUrl -> {
                val url = walletEvent.url
                if (walletEvent.isExternal) {
                    context.startActivityCatching(
                        Intent(Intent.ACTION_VIEW, url.toUri())
                    )
                } else if (WalletContextManager.delegate?.handleDeeplink(url) != true) {
                    if (canOpenExternally(url)) {
                        context.startActivityCatching(
                            Intent(Intent.ACTION_VIEW, url.toUri())
                        )
                    } else if (url.lowercase().startsWith("https://")) {
                        val resolved = if (SubprojectHelpers.isSubproject(url))
                            SubprojectHelpers.appendSubprojectContext(url)
                        else url
                        openUrl(InAppBrowserConfig(resolved, injectDappConnect = true))
                    } else {
                        Logger.w(Logger.LogTag.AIR_APPLICATION, "OpenUrl: unsupported link = $url")
                    }
                }
            }

            is WalletEvent.OpenUrlWithConfig -> {
                walletEvent.config?.let { config ->
                    openUrl(config)
                }
            }

            is WalletEvent.ShowPromotion -> {
                val nav = WNavigationController(
                    window!!, PresentationConfig(
                        overFullScreen = false,
                        isBottomSheet = true
                    )
                )
                nav.setRoot(PromotionVC(context, walletEvent.promotion))
                window?.present(nav)
            }

            is WalletEvent.OpenActivity -> {
                walletEvent.activity.let { activity ->
                    val nav = WNavigationController(
                        window!!, PresentationConfig(
                            overFullScreen = false,
                            isBottomSheet = true
                        )
                    )
                    val transactionVC = TransactionVC(context, walletEvent.accountId, activity)
                    nav.setRoot(transactionVC)
                    window?.present(nav)
                }
            }

            is WalletEvent.OpenToken -> {
                val account = AccountStore.activeAccount ?: return
                val token = TokenStore.getToken(walletEvent.slug) ?: return
                val tokenVC = TokenVC(context, account, token)
                getNavigationStack(IBottomNavigationView.ID_HOME).push(tokenVC)
            }

            is WalletEvent.OpenNftList -> {
                if (walletEvent.nfts.isEmpty()) {
                    return
                }
                val assetsVC = AssetsVC(
                    context,
                    walletEvent.accountId,
                    AssetsVC.ViewMode.COMPLETE,
                    collectionMode = CollectionMode.ReadOnly(
                        name = walletEvent.name,
                        walletEvent.nfts
                    ),
                    isShowingSingleCollection = true
                )
                (window?.navigationControllers?.lastOrNull()
                    ?: getNavigationStack(IBottomNavigationView.ID_HOME))
                    .push(assetsVC)
            }

            is WalletEvent.ConfigReceived -> {
                checkForUpdate()
            }

            else -> {}
        }
    }

    private var visibilityFraction = 1f
    private var visibilityTarget = 1f
    private var activeVisibilityValueAnimator: ValueAnimator? = null
    override fun scrollingUp() {
        if (visibilityTarget == 1f)
            return
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
        if (visibilityTarget == 0f)
            return
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
        return activeNavigationController?.onBackPressed() ?: true
    }

    override fun getBottomNavigationHeight(): Int {
        val keyboard = keyboardHeight
        val minimizedNavHeight = minimizedNavHeight ?: 0f
        val additionalHeight =
            ((if (bottomNavigationView.selectedItemId == IBottomNavigationView.ID_EXPLORE) (SEARCH_BOTTOM_MARGIN + SEARCH_HEIGHT + SEARCH_TOP_MARGIN).dp else 0) + keyboard + minimizedNavHeight).roundToInt()
        return BOTTOM_TABS_LAYOUT_HEIGHT.dp + additionalHeight + bottomBarHeight
    }

    private var minimizedNav: WNavigationController? = null
    private var minimizedNavHeight: Float? = null
    private var minimizedNavY: Float? = null
    private var minimizedNavShadow: PillShadowView? = null

    private fun attachMinimizedShadow(nav: WNavigationController) {
        nav.elevation = 0f
        if (minimizedNavShadow == null) {
            minimizedNavShadow = PillShadowView(context).also {
                it.alpha = 0f
                view.addView(it)
                minimizedNav?.bringToFront()
            }
        }
    }

    private fun detachMinimizedShadow(nav: WNavigationController?) {
        minimizedNavShadow?.let { view.removeView(it) }
        minimizedNavShadow = null
        nav?.elevation = 0f
    }

    private fun applyMinimizedShadowProgress(
        nav: WNavigationController,
        fraction: Float,
        width: Int,
        height: Int,
        radius: Float,
    ) {
        val shadow = minimizedNavShadow
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
        if (minimizedNav != null)
            dismissMinimized(false)
        this.onMaximizeProgress = onMaximizeProgress
        minimizedNav = nav
        nav.window.detachLastNav()
        attachMinimizedShadow(nav)
        view.addView(nav)
        val initialHeight = nav.height
        val finalHeight = 48.dp
        val initialWidth = nav.width
        val customFinalWidth = bottomNavigationView.getMinimizedWidth()
        val finalWidth = customFinalWidth ?: (initialWidth - 20.dp)
        val finalTranslationX =
            if (customFinalWidth != null) (initialWidth - finalWidth) / 2f else 10.dp.toFloat()
        val finalY = view.height -
            bottomBarHeight -
            finalHeight - 4.dp
        minimizedNavHeight = finalHeight + 8f.dp
        updateStickyGradientHeight()
        bottomNavigationView.translationY =
            -(BOTTOM_TABS_BOTTOM_MARGIN.dp + bottomBarHeight + minimizedNavHeight!!) + BOTTOM_TABS_BOTTOM_TO_NAV_DIFF.dp
        render()

        fun onUpdate(animatedFraction: Float) {
            minimizedNavY = animatedFraction * finalY
            nav.translationY = minimizedNavY!!
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
            pauseBlurring()
            ValueAnimator.ofInt(0, 1)
                .apply {
                    duration = AnimationConstants.VERY_VERY_QUICK_ANIMATION
                    interpolator = AccelerateDecelerateInterpolator()

                    addUpdateListener {
                        onUpdate(animatedFraction)
                    }
                    doOnEnd {
                        resumeBlurring()
                    }

                    start()
                }
        } else
            onUpdate(1f)
    }

    override fun maximize() {
        val nav = minimizedNav ?: return
        this.minimizedNav = null
        val initialHeight = nav.height
        val finalHeight = view.height
        val initialWidth = nav.width
        val finalWidth = view.width
        val initialY = nav.y
        val minimizedNavTranslationX = nav.translationX

        fun onUpdate(animatedFraction: Float) {
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
                nav, 1f - animatedFraction, animatedWidth, animatedHeight, radius
            )
        }

        fun onEnd() {
            minimizedNavHeight = 0f
            updateStickyGradientHeight()
            bottomNavigationView.translationY =
                -(BOTTOM_TABS_BOTTOM_MARGIN.dp + bottomBarHeight + minimizedNavHeight!!)
            render()
            detachMinimizedShadow(nav)
            view.removeView(nav)
            window?.attachNavigationController(nav)
        }

        if (WGlobalStorage.getAreAnimationsActive()) {
            pauseBlurring()
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
                        resumeBlurring()
                    }

                    start()
                }
        } else {
            onUpdate(1f)
            onEnd()
        }
    }

    override fun dismissMinimized(animated: Boolean) {
        if (minimizedNav == null)
            return
        val nav = minimizedNav
        fun onUpdate(animatedFraction: Float) {
            minimizedNavHeight = (1 - animatedFraction) * 48.dp
            updateStickyGradientHeight()
            bottomNavigationView.translationY =
                -(BOTTOM_TABS_BOTTOM_MARGIN.dp + bottomBarHeight + minimizedNavHeight!!) + BOTTOM_TABS_BOTTOM_TO_NAV_DIFF.dp * (1 - animatedFraction)
            render()
            val fadedAlpha = visibilityFraction * (1 - animatedFraction)
            nav?.alpha = fadedAlpha
            minimizedNavShadow?.alpha = fadedAlpha
        }
        if (!animated) {
            onUpdate(1f)
            detachMinimizedShadow(nav)
            view.removeView(minimizedNav)
            minimizedNav = null
            minimizedNavY = null
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
                    detachMinimizedShadow(nav)
                    view.removeView(nav)
                    minimizedNav = null
                }

                start()
            }
    }

    override val pausedBlurViews: Boolean
        get() = bottomNavigationView.pausedBlurViews

    override fun pauseBlurring() {
        searchBlurryBackgroundView.pauseBlurring()
        bottomNavigationView.pauseBlurring()
        bottomReversedCornerView?.pauseBlurring()
        (minimizedNav?.viewControllers?.lastOrNull() as? WMinimizableBlurHost)
            ?.pauseMinimizedBlur()
    }

    override fun resumeBlurring() {
        searchBlurryBackgroundView.resumeBlurring()
        bottomNavigationView.resumeBlurring()
        bottomReversedCornerView?.resumeBlurring()
        (minimizedNav?.viewControllers?.lastOrNull() as? WMinimizableBlurHost)
            ?.resumeMinimizedBlur()
    }

    override fun setSearchText(text: String) {
        searchView.requestFocus()
        searchEditText.setText(text)
    }

    override fun switchToFirstTab(): Boolean {
        if (bottomNavigationView.selectedItemId != IBottomNavigationView.ID_HOME) {
            bottomNavigationView.selectedItemId = IBottomNavigationView.ID_HOME
            return true
        }
        return false
    }

    override fun hideTabBar() {
        bottomNavigationView.fadeOut()
    }

    override fun showTabBar() {
        bottomNavigationView.fadeIn()
    }

    override fun onDestroy() {
        super.onDestroy()
        stackNavigationControllers.values.forEach {
            it.onDestroy()
        }
        bottomNavigationView.listener = null
    }
}
