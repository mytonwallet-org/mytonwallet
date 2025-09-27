package org.mytonwallet.uihome.tabs

import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
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
import org.mytonwallet.app_air.uibrowser.viewControllers.explore.ExploreVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.SwapSearchEditText
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uisettings.viewControllers.settings.SettingsVC
import org.mytonwallet.app_air.uitransaction.viewControllers.TransactionVC
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.uihome.R
import org.mytonwallet.uihome.home.HomeVC
import kotlin.math.max
import kotlin.math.roundToInt

class TabsVC(context: Context) : WViewController(context), WThemedView, WProtectedView,
    WalletCore.EventObserver,
    WNavigationController.ITabBarController {

    companion object {
        const val ID_HOME = 1
        const val ID_BROWSER = 2
        const val ID_SETTINGS = 3

        const val SEARCH_HEIGHT = 48
        const val SEARCH_TOP_MARGIN = 8

        const val BOTTOM_TABS_LAYOUT_HEIGHT = 74
        const val BOTTOM_TABS_PADDING_OFFSET = -2
        const val BOTTOM_TABS_BOTTOM_MARGIN = -12
        const val BOTTOM_TABS_TOP_MARGIN = -8
    }

    override val isSwipeBackAllowed = false
    private var stackNavigationControllers = HashMap<Int, WNavigationController>()
    private val contentView = WView(context)

    private var updateFloatingButton: WLabel? = null
    private var updateFloatingButtonBackground: WRippleDrawable? = null

    private val bottomCornerView: ReversedCornerViewUpsideDown by lazy {
        ReversedCornerViewUpsideDown(context, contentView).apply {
            setBlurOverlayColor(WColor.SecondaryBackground)
        }
    }

    private val bottomNavigationView: BottomNavigationView by lazy {
        val bottomNavigationView = BottomNavigationView(context)
        bottomNavigationView.id = View.generateViewId()
        bottomNavigationView.elevation = 0f
        bottomNavigationView.itemPaddingBottom += BOTTOM_TABS_PADDING_OFFSET.dp

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
            ID_BROWSER,
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
        bottomNavigationView.setOnItemSelectedListener { item ->
            if (bottomNavigationView.selectedItemId == item.itemId) {
                stackNavigationControllers[item.itemId]?.apply {
                    if (viewControllers.size == 1)
                        scrollToTop()
                    else
                        popToRoot()
                }
                return@setOnItemSelectedListener true
            }
            bottomNavigationView.post {
                hideTooltips()
            }

            val nav = getNavigationStack(item.itemId)
            searchVisible.animatedValue = item.itemId == ID_BROWSER
            if (searchView.hasFocus() && !searchVisible.animatedValue)
                searchView.clearFocus()

            contentView.removeAllViews()
            contentView.addView(
                nav,
                ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            )
            nav.viewWillAppear()
            nav.viewDidAppear()
            true
        }
        bottomNavigationView.background = null
        bottomNavigationView
    }

    private val searchView by lazy {
        SwapSearchEditText(context).apply {
            hint =
                LocaleController.getString("Search or enter address")
            isVisible = false
            isEnabled = false
            doOnTextChanged { text, _, _, _ ->
                cachedBrowserVC?.search(text.toString())
            }
            onFocusChangeListener = View.OnFocusChangeListener { v, hasFocus ->
                val query = if (hasFocus) text.toString() else null
                cachedBrowserVC?.search(query)
            }
            setOnEditorActionListener { _, actionId, event ->
                if (actionId == EditorInfo.IME_ACTION_DONE ||
                    event?.action == KeyEvent.ACTION_DOWN && event.keyCode == KeyEvent.KEYCODE_ENTER
                ) {
                    val uri = InAppBrowserVC.convertToUri(text.toString())
                    uri?.let {
                        val inAppBrowserVC = InAppBrowserVC(
                            context,
                            this@TabsVC,
                            InAppBrowserConfig(
                                url = it.toString(),
                                injectTonConnectBridge = true
                            )
                        )
                        val nav = WNavigationController(window!!)
                        nav.setRoot(inAppBrowserVC)
                        window!!.present(nav)
                        clearFocus()
                        hideKeyboard()
                        return@setOnEditorActionListener true
                    }
                }
                false
            }
        }
    }

    private val bottomNavigationFrameLayout = FrameLayout(context).apply {
        id = View.generateViewId()
    }

    private val keyboardVisible = FloatAnimator(220L, AnimatorUtils.DECELERATE_INTERPOLATOR, 0f) {
        render()
    }

    private val searchVisible =
        BoolAnimator(220L, AnimatorUtils.DECELERATE_INTERPOLATOR, false) { state, value, _, _ ->
            searchView.isVisible = state != BoolAnimator.State.FALSE
            searchView.isEnabled = state == BoolAnimator.State.TRUE
            searchView.alpha = max(0f, value - 0.5f) * 2
            render()
        }

    private fun render() {
        val keyboard = if (keyboardVisible.value > 0) keyboardVisible.value else 0f
        val minimizedNavHeight = if (minimizedNavHeight != null) minimizedNavHeight!! else 0f
        val additionalHeight =
            (56f.dp * searchVisible.floatValue + keyboard + minimizedNavHeight).roundToInt()
        val contentHeight = BOTTOM_TABS_LAYOUT_HEIGHT.dp +
            BOTTOM_TABS_BOTTOM_MARGIN.dp +
            BOTTOM_TABS_TOP_MARGIN.dp +
            additionalHeight
        bottomNavigationFrameLayout.alpha = visibilityFraction
        minimizedNav?.alpha = visibilityFraction
        val bottomNavigationLayoutLayoutParams = bottomNavigationFrameLayout.layoutParams
        if (bottomNavigationLayoutLayoutParams != null) {
            bottomNavigationLayoutLayoutParams.height =
                ((navigationController?.getSystemBars()?.bottom
                    ?: 0) + (visibilityFraction * contentHeight).roundToInt())
            bottomNavigationFrameLayout.layoutParams = bottomNavigationLayoutLayoutParams
            bottomCornerView.layoutParams = bottomCornerView.layoutParams.apply {
                height =
                    bottomNavigationLayoutLayoutParams.height + ViewConstants.BAR_ROUNDS.dp.roundToInt()
            }
        }
        searchView.translationY =
            (SEARCH_HEIGHT + SEARCH_TOP_MARGIN).dp - BOTTOM_TABS_LAYOUT_HEIGHT.dp - BOTTOM_TABS_BOTTOM_MARGIN.dp - BOTTOM_TABS_TOP_MARGIN.dp / 2 - additionalHeight.toFloat()
        val visibilityTranslationY = (1 - visibilityFraction) * contentHeight
        searchView.translationY += visibilityTranslationY
        bottomNavigationView.y =
            contentHeight - (BOTTOM_TABS_LAYOUT_HEIGHT.dp + BOTTOM_TABS_BOTTOM_MARGIN.dp + minimizedNavHeight)
        if (activeVisibilityValueAnimator?.isRunning == true) {
            minimizedNav?.y = minimizedNavY!! + visibilityTranslationY
        }
        onUpdateAdditionalHeight()
    }

    private fun onUpdateAdditionalHeight() {
        activeNavigationController?.insetsUpdated()
    }

    private var initialBottomSafeArea = 0

    private fun hideTooltips() {
        for (i in 0..<bottomNavigationView.menu.size) {
            val item = bottomNavigationView.menu[i]
            val itemView = bottomNavigationView.findViewById<View?>(item.itemId)
            TooltipCompat.setTooltipText(itemView, null)
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
        bottomNavigationFrameLayout.addView(
            searchView,
            FrameLayout.LayoutParams(MATCH_PARENT, SEARCH_HEIGHT.dp, Gravity.BOTTOM).apply {
                leftMargin = 16.dp
                rightMargin = 16.dp
            })

        view.addView(contentView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            bottomCornerView,
            ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
        view.addView(bottomNavigationFrameLayout, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.setConstraints {
            toBottom(bottomNavigationFrameLayout)
            toCenterX(bottomNavigationFrameLayout)
            toBottom(bottomCornerView)
        }

        contentView.addView(
            getNavigationStack(ID_HOME),
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        initialBottomSafeArea = (navigationController?.getSystemBars()?.bottom ?: 0)
        view.post {
            render()
            activeNavigationController?.insetsUpdated()
            // preload other tabs
            getNavigationStack(ID_BROWSER)
            getNavigationStack(ID_SETTINGS)
        }

        applyFonts(bottomNavigationView)
        bottomNavigationView.post {
            hideTooltips()
        }
        checkForUpdate()
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()

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

        view.alpha = 0f
        view.post {
            view.fadeIn()
        }

        for (navView in stackNavigationControllers.values) {
            if (navView.parent != null)
                continue
            fun updateThemeForChildren(parentView: ViewGroup) {
                for (child in parentView.children) {
                    if (child is WThemedView)
                        child.updateTheme()
                    if (child is ViewGroup)
                        updateThemeForChildren(child)
                }
            }
            updateThemeForChildren(navView)
        }

        updateFloatingButtonBackground?.apply {
            backgroundColor = WColor.Tint.color
        }

        render()
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
            view.typeface =
                if (view.id == com.google.android.material.R.id.navigation_bar_item_large_label_view)
                    WFont.SemiBold.typeface
                else
                    WFont.Medium.typeface
        }
    }

    private val keyboardHeight: Float
        get() {
            return maxOf(
                (
                    (window?.imeInsets?.bottom ?: 0) -
                        (window?.systemBars?.bottom ?: 0) -
                        BOTTOM_TABS_LAYOUT_HEIGHT.dp -
                        BOTTOM_TABS_BOTTOM_MARGIN.dp +
                        (if (bottomNavigationView.selectedItemId == ID_BROWSER) SEARCH_TOP_MARGIN.dp else 0) -
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
    }

    private var cachedBrowserVC: ExploreVC? = null

    private fun getNavigationStack(id: Int): WNavigationController {
        if (stackNavigationControllers.containsKey(id))
            return stackNavigationControllers[id]!!

        val navigationController = WNavigationController(window!!)
        navigationController.tabBarController = this
        navigationController.setRoot(
            when (id) {
                ID_HOME -> {
                    HomeVC(context)
                }

                ID_BROWSER -> {
                    val b = ExploreVC(context)
                    cachedBrowserVC = b
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

    private val activeNavigationController: WNavigationController?
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
                button.fadeIn { }
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

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.AccountChangedInApp, WalletEvent.AddNewWalletCompletion -> {
                bottomNavigationView.selectedItemId = ID_HOME
                dismissMinimized(false)
            }

            is WalletEvent.OpenUrl -> {
                walletEvent.url.let { url ->
                    val browserVC =
                        InAppBrowserVC(
                            context,
                            window?.navigationControllers?.last()?.viewControllers?.last() as? TabsVC,
                            InAppBrowserConfig(
                                url,
                                injectTonConnectBridge = true
                            )
                        )
                    val nav = WNavigationController(window!!)
                    nav.setRoot(browserVC)
                    window?.present(nav)
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
                    val transactionVC = TransactionVC(context, activity)
                    nav.setRoot(transactionVC)
                    window?.present(nav)
                }
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
            ((if (bottomNavigationView.selectedItemId == ID_BROWSER) 56f.dp else 0f) + keyboard + minimizedNavHeight).roundToInt()
        return BOTTOM_TABS_LAYOUT_HEIGHT.dp + BOTTOM_TABS_BOTTOM_MARGIN.dp + BOTTOM_TABS_TOP_MARGIN.dp + additionalHeight +
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
        nav.window.detachLastNav()
        view.addView(minimizedNav)
        val initialHeight = nav.height
        val finalHeight = 48.dp
        val initialWidth = nav.width
        val finalWidth = initialWidth - 8.dp
        val finalY = view.height -
            ((navigationController?.getSystemBars()?.bottom ?: 0)) -
            finalHeight
        val bottomBar = window?.systemBars?.bottom ?: 0
        minimizedNavHeight = finalHeight + 8f.dp
        bottomNavigationView.y =
            bottomNavigationFrameLayout.height - (bottomNavigationView.height + BOTTOM_TABS_BOTTOM_MARGIN.dp + bottomBar + minimizedNavHeight!!)
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
            nav.translationX = animatedFraction * 4.dp
            nav.setBackgroundColor(Color.TRANSPARENT, 10.dp * animatedFraction, true)
            nav.elevation = animatedFraction * 4.dp
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
            nav.translationX = (1 - animatedFraction) * 4.dp
            nav.setBackgroundColor(Color.TRANSPARENT, 10.dp * (1 - animatedFraction), true)
            nav.elevation = (1 - animatedFraction) * 4.dp
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
                bottomNavigationFrameLayout.height - (bottomNavigationView.height + BOTTOM_TABS_BOTTOM_MARGIN.dp + bottomBar + minimizedNavHeight!!)
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

    override fun pauseBlurring() {
        bottomCornerView.pauseBlurring()
    }

    override fun resumeBlurring() {
        bottomCornerView.resumeBlurring()
    }

    override fun onDestroy() {
        super.onDestroy()
        stackNavigationControllers.values.forEach {
            it.onDestroy()
        }
        bottomNavigationView.setOnItemSelectedListener(null)
    }
}
