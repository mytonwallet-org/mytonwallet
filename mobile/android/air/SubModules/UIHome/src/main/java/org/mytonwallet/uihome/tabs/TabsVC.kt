package org.mytonwallet.uihome.tabs

import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.ShapeDrawable
import android.os.Build
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.KeyEvent
import android.view.Menu
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import android.widget.TextView
import androidx.appcompat.widget.TooltipCompat
import androidx.core.animation.doOnEnd
import androidx.core.net.toUri
import androidx.core.view.children
import androidx.core.view.forEach
import androidx.core.view.get
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.view.size
import androidx.core.widget.doOnTextChanged
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.google.android.material.navigation.NavigationBarView
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import me.vkryl.android.animatorx.FloatAnimator
import org.mytonwallet.app_air.uiassets.viewControllers.token.TokenVC
import android.net.Uri
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WNavigationController.PresentationConfig
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.AccountItemView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.IPopup
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
import org.mytonwallet.app_air.uisettings.viewControllers.settings.SettingsVC
import org.mytonwallet.app_air.uitransaction.viewControllers.transaction.TransactionVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.SubprojectHelpers
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import org.mytonwallet.app_air.walletcore.models.MScreenMode
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.ExploreHistoryStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import org.mytonwallet.uihome.R
import org.mytonwallet.app_air.uireceive.ReceiveBackgroundCache
import org.mytonwallet.uihome.home.HomeVC
import kotlin.math.roundToInt

class TabsVC(context: Context) : WViewController(context), WThemedView, WProtectedView,
    WalletCore.EventObserver,
    WNavigationController.ITabBarController {
    override val TAG = "Tabs"

    companion object {
        const val ID_HOME = 1
        const val ID_EXPLORE = 2
        const val ID_SETTINGS = 3

        const val SEARCH_HEIGHT = 44
        const val SEARCH_TOP_MARGIN = 4
        const val SEARCH_BOTTOM_MARGIN = 12

        const val BOTTOM_TABS_LAYOUT_HEIGHT = 75
        const val BOTTOM_TABS_PADDING_OFFSET = -2
        const val BOTTOM_TABS_BOTTOM_MARGIN = -5
        const val BOTTOM_TABS_TOP_MARGIN = -6
        const val BOTTOM_TABS_BOTTOM_TO_NAV_DIFF = 2

        const val ELEVATION_COLOR = 0x44000000
    }

    override val isSwipeBackAllowed = false
    private var stackNavigationControllers = HashMap<Int, WNavigationController>()
    private val contentView = WView(context)

    private var updateFloatingButton: WLabel? = null
    private var updateFloatingButtonBackground: WRippleDrawable? = null

    private val bottomCornerView: ReversedCornerViewUpsideDown by lazy {
        ReversedCornerViewUpsideDown(context, contentView).apply {
            setBlurOverlayColor(WColor.SecondaryBackground.color)
        }
    }

    private val bottomNavigationView: BottomNavigationView by lazy {
        val bottomNavigationView = BottomNavigationView(context)
        bottomNavigationView.id = View.generateViewId()
        bottomNavigationView.elevation = 0f
        bottomNavigationView.itemPaddingBottom += BOTTOM_TABS_PADDING_OFFSET.dp
        bottomNavigationView.setPadding(25.dp, 0, 25.dp, 0)

        // Add menu items to BottomNavigationView
        val menu = bottomNavigationView.menu
        menu.add(
            Menu.NONE,
            ID_HOME,
            Menu.NONE,
            LocaleController.getString("Wallet")
        )
            .setIcon(R.drawable.ic_home)
        menu.add(
            Menu.NONE,
            ID_EXPLORE,
            Menu.NONE,
            LocaleController.getString("Explore")
        )
            .setIcon(R.drawable.ic_browser)
        menu.add(
            Menu.NONE,
            ID_SETTINGS,
            Menu.NONE,
            LocaleController.getString("Settings")
        )
            .setIcon(R.drawable.ic_settings)

        // Set label visibility mode
        bottomNavigationView.labelVisibilityMode = NavigationBarView.LABEL_VISIBILITY_LABELED

        // Set the item selected listener
        var isSwitchingTabs = false
        bottomNavigationView.setOnItemSelectedListener { item ->
            if (bottomNavigationView.selectedItemId == item.itemId) {
                stackNavigationControllers[item.itemId]?.apply {
                    if (viewControllers.size == 1) {
                        scrollToTop()
                    } else
                        popToRoot()
                }
                return@setOnItemSelectedListener true
            }
            if (isSwitchingTabs) {
                return@setOnItemSelectedListener false
            }

            bottomNavigationView.post {
                hideTooltips()
            }

            val oldNav = contentView[0] as? WNavigationController
            oldNav?.viewWillDisappear()

            val newNav = getNavigationStack(item.itemId)
            val searchVisible = item.itemId == ID_EXPLORE
            if (searchView.hasFocus() && !searchVisible)
                searchView.clearFocus()

            val animationsEnabled = WGlobalStorage.getAreAnimationsActive()

            if (animationsEnabled) {
                if (searchVisible) {
                    searchView.visibility = View.VISIBLE
                }
                searchView.animate()
                    .alpha(if (searchVisible) 1f else 0f)
                    .setDuration(AnimationConstants.VERY_VERY_QUICK_ANIMATION)
                    .setInterpolator(CubicBezierInterpolator.EASE_OUT)
                    .withEndAction {
                        if (!searchVisible) {
                            searchView.visibility = View.INVISIBLE
                        }
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
                        bottomNavigationView.post {
                            onUpdateAdditionalHeight()
                        }
                    }
                    .start()
            } else {
                searchView.alpha = if (searchVisible) 1f else 0f
                searchView.visibility = if (searchVisible) View.VISIBLE else View.INVISIBLE

                oldNav?.let { contentView.removeView(it) }
                contentView.addView(
                    newNav,
                    ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                )
                newNav.viewWillAppear()
                newNav.viewDidAppear()
                bottomNavigationView.post {
                    onUpdateAdditionalHeight()
                }
            }

            true
        }
        bottomNavigationView.background = null
        bottomNavigationView
    }

    var isProcessingSearchKeyword = false
    private val searchBlurryBackgroundView =
        if (DevicePerformanceClassifier.isHighClass)
            WBlurryBackgroundView(context, fadeSide = null)
        else
            null
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
            doOnTextChanged { text, start, before, count ->
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
            onFocusChangeListener = View.OnFocusChangeListener { v, hasFocus ->
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
    private val searchView by lazy {
        WFrameLayout(context).apply {
            alpha = 0f
            visibility = View.INVISIBLE
            elevation = 2f
            translationY = -SEARCH_BOTTOM_MARGIN.dp.toFloat()
            searchBlurryBackgroundView?.let {
                addView(
                    searchBlurryBackgroundView,
                    FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                )
                setBackgroundColor(Color.TRANSPARENT, 24f.dp, clipToBounds = true)
            } ?: run {
                setBackgroundColor(WColor.SecondaryBackground.color, 24f.dp, clipToBounds = true)
            }
            addView(searchEditText, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    val searchWidth by lazy {
        val hintWidth = searchEditText.paint.measureText(
            LocaleController.getString("Search app or enter address")
        ).ceilToInt()
        (62.dp + hintWidth).coerceAtMost(320.dp)
    }

    private val bottomNavigationFrameLayout = WFrameLayout(context)

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
                BOTTOM_TABS_TOP_MARGIN.dp +
                BOTTOM_TABS_BOTTOM_MARGIN.dp

        val contentHeight = tabsHeight + keyboardHeight + minimizedNavHeightPx

        val hiddenTranslationY = (1f - visibilityFraction) * contentHeight

        // Alpha
        bottomNavigationFrameLayout.alpha = visibilityFraction
        minimizedNav?.alpha = visibilityFraction

        // Bottom navigation height
        bottomNavigationFrameLayout.layoutParams?.let { params ->
            val systemInset = navigationController?.getSystemBars()?.bottom ?: 0
            val newHeight =
                systemInset + (visibilityFraction * contentHeight).roundToInt()

            if (params.height != newHeight) {
                params.height = newHeight
                bottomNavigationFrameLayout.layoutParams = params
            }
            updateBottomBlurHeight()
        }

        // Bottom navigation translation
        bottomNavigationView.y =
            contentHeight -
                (BOTTOM_TABS_LAYOUT_HEIGHT.dp +
                    BOTTOM_TABS_BOTTOM_MARGIN.dp +
                    minimizedNavHeightPx) +
                BOTTOM_TABS_BOTTOM_TO_NAV_DIFF.dp * visibilityFraction

        // Minimized nav animation
        if (activeVisibilityValueAnimator?.isRunning == true) {
            minimizedNav?.y = minimizedNavY!! + hiddenTranslationY
        }
        onUpdateAdditionalHeight()
    }

    private fun updateBottomBlurHeight() {
        val bottomNavigationLayoutLayoutParams = bottomNavigationFrameLayout.layoutParams ?: return
        val newBottomViewHeight =
            bottomNavigationLayoutLayoutParams.height + ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()
        if (bottomCornerView.layoutParams.height != newBottomViewHeight)
            bottomCornerView.layoutParams = bottomCornerView.layoutParams.apply {
                height = newBottomViewHeight
            }
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

    private fun hideTooltips() {
        for (i in 0..<bottomNavigationView.menu.size) {
            val item = bottomNavigationView.menu[i]
            val itemView = bottomNavigationView.findViewById<View?>(item.itemId)
            itemView?.let {
                TooltipCompat.setTooltipText(itemView, null)
            }
        }
    }

    override fun setupViews() {
        super.setupViews()

        setTopBlur(visible = false, animated = false)

        WalletCore.registerObserver(this)

        bottomNavigationFrameLayout.addView(
            bottomNavigationView,
            FrameLayout.LayoutParams(MATCH_PARENT, BOTTOM_TABS_LAYOUT_HEIGHT.dp, Gravity.TOP)
                .apply {
                    topMargin = BOTTOM_TABS_TOP_MARGIN.dp
                }
        )

        view.addView(contentView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            bottomCornerView,
            ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
        view.addView(bottomNavigationFrameLayout, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            searchView,
            FrameLayout.LayoutParams(searchWidth, SEARCH_HEIGHT.dp, Gravity.BOTTOM)
        )
        view.setConstraints {
            toCenterX(searchView)
            bottomToTop(searchView, bottomNavigationFrameLayout)
            toBottom(bottomNavigationFrameLayout)
            toCenterX(bottomNavigationFrameLayout)
            toBottom(bottomCornerView)
        }

        contentView.addView(
            getNavigationStack(ID_HOME),
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        view.post {
            render()
            activeNavigationController?.insetsUpdated()
            // preload other tabs
            getNavigationStack(ID_EXPLORE)
            getNavigationStack(ID_SETTINGS)
        }

        applyFonts(bottomNavigationView)
        bottomNavigationView.post {
            hideTooltips()
            setupWalletSwitcherPopup()
        }
        checkForUpdate()
        updateTheme()
        WalletCore.doOnBridgeReady {
            ReceiveBackgroundCache.precache(window?.systemBars?.top ?: 0)
        }
    }

    private fun setupWalletSwitcherPopup() {
        val settingsItemView = bottomNavigationView.findViewById<View>(ID_SETTINGS) ?: return
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
                bottomNavigationFrameLayout.height -
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
                    horizontalOffset = 6.dp,
                    verticalOffset = (-8).dp
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

    private var cachedTintColor: Int? = null
    override val isTinted = true
    override fun updateTheme() {
        super.updateTheme()

        val tintColor = WColor.Tint.color
        if (cachedTintColor != tintColor) {
            cachedTintColor = tintColor

            val states = arrayOf(
                intArrayOf(android.R.attr.state_checked),
                intArrayOf(-android.R.attr.state_checked)
            )
            val colors = intArrayOf(
                WColor.Tint.color,
                WColor.SecondaryText.color
            )
            val colorStateList = ColorStateList(states, colors)
            val indicator = WColor.Tint.color.colorWithAlpha(38)
            val indicatorColors = intArrayOf(
                Color.TRANSPARENT,
                indicator,
            )
            val indicatorColorStateList = ColorStateList(states, indicatorColors)

            bottomNavigationView.itemIconTintList = colorStateList
            bottomNavigationView.itemTextColor = colorStateList
            bottomNavigationView.itemActiveIndicatorColor = indicatorColorStateList
            bottomNavigationView.itemRippleColor = ColorStateList.valueOf(WColor.Tint.color.colorWithAlpha(38))
        }

        for (navView in stackNavigationControllers.values) {
            if (navView.parent != null)
                continue
            navView.updateTheme()
        }

        updateFloatingButtonBackground?.apply {
            backgroundColor = tintColor
        }
        bottomCornerView.setBlurOverlayColor(WColor.SecondaryBackground.color)
        bottomReversedCornerView?.setBlurOverlayColor(WColor.SecondaryBackground.color)
        searchBlurryBackgroundView?.setOverlayColor(WColor.SecondaryBackground) ?: run {
            (searchView.background as? ShapeDrawable)?.paint?.color =
                WColor.SecondaryBackground.color
        }

        searchEditText.highlightColor = tintColor.colorWithAlpha(51)
        checkForMatchingUrl(searchKeyword)
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        activeNavigationController?.viewWillAppear()
        bottomCornerView.resumeBlurring()
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

    private fun applyFonts(view: View) {
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val child = view.getChildAt(i)
                applyFonts(child)
            }
        } else if (view is TextView) {
            view.letterSpacing = 0f
            view.typeface =
                if (view.id == com.google.android.material.R.id.navigation_bar_item_large_label_view)
                    WFont.SemiBold.typeface
                else
                    WFont.DemiBold.typeface
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
        bottomNavigationFrameLayout.setPadding(
            0,
            0,
            0,
            navigationController?.getSystemBars()?.bottom ?: 0
        )
        bottomNavigationFrameLayout.clipToPadding = false
        onUpdateAdditionalHeight()
        bottomCornerView.setHorizontalPadding(ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat())

        if (!isKeyboardOpen && searchEditText.hasFocus()) {
            searchEditText.clearFocus()
        }
        if (searchMatchedSite != null && !isKeyboardOpen) {
            clearSearchAutoComplete()
        }
        updateBottomBlurHeight()
        updateSearchWidth()
    }

    fun switchToExplore(targetUri: Uri? = null) {
        navigationController?.popToRoot(false)
        bottomNavigationView.selectedItemId = ID_EXPLORE
        window?.dismissToRoot()
        targetUri?.let { cachedExploreVC?.findSiteAndOpenTargetUri(it) }
    }

    private var cachedExploreVC: ExploreVC? = null
        set(value) {
            field = value
            value?.view?.let {
                searchBlurryBackgroundView?.setupWith(it)
            }
        }

    private fun getNavigationStack(id: Int): WNavigationController {
        if (stackNavigationControllers.containsKey(id))
            return stackNavigationControllers[id]!!

        val navigationController = WNavigationController(window!!)
        navigationController.tabBarController = this
        navigationController.setRoot(
            when (id) {
                ID_HOME -> {
                    HomeVC(context, MScreenMode.Default)
                }

                ID_EXPLORE -> {
                    val b = ExploreVC(context)
                    cachedExploreVC = b
                    b
                }

                ID_SETTINGS -> {
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
                setStyle(16f, WFont.SemiBold)
                text = LocaleController.getStringWithKeyValues(
                    "Update %app_name%",
                    listOf(
                        Pair("%app_name%", "MyTonWallet")
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
                    val intent = Intent(Intent.ACTION_VIEW)
                    intent.setData("https://get.mytonwallet.io/android-store".toUri())
                    window?.startActivity(intent)
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
                    bottomNavigationFrameLayout,
                    ViewConstants.GAP.toFloat()
                )
                toCenterX(updateFloatingButton!!)
            }
        }
    }

    private fun showUpdateButton() {
        createUpdateButtonIfNeeded()
        updateFloatingButton?.let { button ->
            if (button.alpha < 1f)
                button.fadeIn()
        }
    }

    private fun hideUpdateButton() {
        updateFloatingButton?.let { button ->
            if (button.isVisible) {
                button.fadeOut {
                    button.isGone = true
                }
            }
        }
    }

    private fun checkForUpdate() {
        if (ConfigStore.isAppUpdateRequired == true) {
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
            searchEditText.setSelection(keyword.length, txt.length)
            searchView.post {
                searchView.scrollTo(0, 0)
            }
        }
    }

    private fun clearSearchAutoComplete() {
        searchEditText.setText(searchKeyword)
        checkForMatchingUrl(searchKeyword)
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
                if (bottomNavigationView.selectedItemId != ID_HOME)
                    bottomNavigationView.selectedItemId = ID_HOME
                dismissMinimized(false)
            }

            is WalletEvent.OpenUrl -> {
                val url = if (SubprojectHelpers.isSubproject(walletEvent.url))
                    SubprojectHelpers.appendSubprojectContext(walletEvent.url)
                else walletEvent.url
                openUrl(InAppBrowserConfig(url, injectDappConnect = true))
            }

            is WalletEvent.OpenUrlWithConfig -> {
                walletEvent.config?.let { config ->
                    openUrl(config)
                }
            }

            is WalletEvent.OpenActivity -> {
                walletEvent.activity.let { activity ->
                    val nav = WNavigationController(
                        window!!, WNavigationController.PresentationConfig(
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
                getNavigationStack(ID_HOME).push(tokenVC)
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
        bottomNavigationView.menu.forEach { it.isEnabled = true }
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
        bottomNavigationView.menu.forEach { it.isEnabled = false }
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
            ((if (bottomNavigationView.selectedItemId == ID_EXPLORE) (SEARCH_BOTTOM_MARGIN + SEARCH_HEIGHT + SEARCH_TOP_MARGIN).dp else 0) + keyboard + minimizedNavHeight).roundToInt()
        return BOTTOM_TABS_LAYOUT_HEIGHT.dp + additionalHeight +
            (navigationController?.getSystemBars()?.bottom ?: 0)
    }

    private var minimizedNav: WNavigationController? = null
    private var minimizedNavHeight: Float? = null
    private var minimizedNavY: Float? = null
    private var onMaximizeProgress: ((progress: Float) -> Unit)? = null
    override fun minimize(
        nav: WNavigationController,
        onProgress: (progress: Float) -> Unit,
        onMaximizeProgress: (progress: Float) -> Unit
    ) {
        if (minimizedNav != null)
            dismissMinimized(false)
        this.onMaximizeProgress = onMaximizeProgress
        minimizedNav = nav
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            minimizedNav?.outlineAmbientShadowColor = ELEVATION_COLOR
            minimizedNav?.outlineSpotShadowColor = ELEVATION_COLOR
        }
        nav.window.detachLastNav()
        view.addView(minimizedNav)
        val initialHeight = nav.height
        val finalHeight = 48.dp
        val initialWidth = nav.width
        val finalWidth = initialWidth - 20.dp
        val finalY = view.height -
            ((navigationController?.getSystemBars()?.bottom ?: 0)) -
            finalHeight - 4.dp
        val bottomBar = window?.systemBars?.bottom ?: 0
        minimizedNavHeight = finalHeight + 8f.dp
        bottomNavigationView.y =
            bottomNavigationFrameLayout.height - (bottomNavigationView.height + BOTTOM_TABS_BOTTOM_MARGIN.dp + bottomBar + minimizedNavHeight!!) + BOTTOM_TABS_BOTTOM_TO_NAV_DIFF.dp
        render()

        fun onUpdate(animatedFraction: Float) {
            minimizedNavY = animatedFraction * finalY
            nav.translationY = minimizedNavY!!
            nav.layoutParams = nav.layoutParams.apply {
                onProgress(animatedFraction)
                height =
                    finalHeight +
                        ((initialHeight - finalHeight) * (1 - animatedFraction)).roundToInt()
                width = finalWidth +
                    ((initialWidth - finalWidth) * (1 - animatedFraction)).roundToInt()
            }
            nav.translationX = animatedFraction * 10.dp
            nav.setBackgroundColor(Color.TRANSPARENT, 24.dp * animatedFraction, true)
            nav.elevation = animatedFraction * 1.5f.dp
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
        val bottomBar = window?.systemBars?.bottom ?: 0

        fun onUpdate(animatedFraction: Float) {
            onMaximizeProgress?.invoke(animatedFraction)
            val topY = (1 - animatedFraction) * initialY
            nav.translationY = topY
            nav.layoutParams = nav.layoutParams.apply {
                height =
                    finalHeight +
                        ((initialHeight - finalHeight) * (1 - animatedFraction)).roundToInt()
                width = finalWidth +
                    ((initialWidth - finalWidth) * (1 - animatedFraction)).roundToInt()
            }
            nav.translationX = (1 - animatedFraction) * 10.dp
            nav.setBackgroundColor(Color.TRANSPARENT, 24.dp * (1 - animatedFraction), true)
            nav.elevation = (1 - animatedFraction) * 1.5f.dp
        }

        fun onEnd() {
            minimizedNavHeight = 0f
            bottomNavigationView.y =
                bottomNavigationFrameLayout.height - (bottomNavigationView.height + BOTTOM_TABS_BOTTOM_MARGIN.dp + bottomBar + minimizedNavHeight!!)
            render()
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
        val bottomBar = window?.systemBars?.bottom ?: 0
        val nav = minimizedNav
        fun onUpdate(animatedFraction: Float) {
            minimizedNavHeight = (1 - animatedFraction) * 48.dp
            bottomNavigationView.y =
                bottomNavigationFrameLayout.height - (bottomNavigationView.height + BOTTOM_TABS_BOTTOM_MARGIN.dp + bottomBar + minimizedNavHeight!!) + BOTTOM_TABS_BOTTOM_TO_NAV_DIFF.dp * (1 - animatedFraction)
            render()
            nav?.alpha = visibilityFraction * (1 - animatedFraction)
        }
        if (!animated) {
            onUpdate(1f)
            view.removeView(minimizedNav)
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
                    view.removeView(nav)
                    minimizedNav = null
                }

                start()
            }
    }

    override val pausedBlurViews: Boolean
        get() {
            return !bottomCornerView.isPlaying
        }

    override fun pauseBlurring() {
        searchBlurryBackgroundView?.pauseBlurring()
        bottomCornerView.pauseBlurring()
    }

    override fun resumeBlurring() {
        searchBlurryBackgroundView?.resumeBlurring()
        bottomCornerView.resumeBlurring()
    }

    override fun setSearchText(text: String) {
        searchView.requestFocus()
        searchEditText.setText(text)
    }

    override fun onDestroy() {
        super.onDestroy()
        stackNavigationControllers.values.forEach {
            it.onDestroy()
        }
        bottomNavigationView.setOnItemSelectedListener(null)
    }
}
