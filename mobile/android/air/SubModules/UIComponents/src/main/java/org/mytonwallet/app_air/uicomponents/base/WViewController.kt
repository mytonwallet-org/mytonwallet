package org.mytonwallet.app_air.uicomponents.base

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.os.MessageQueue.IdleHandler
import android.text.method.LinkMovementMethod
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.coordinatorlayout.widget.CoordinatorLayout.LayoutParams
import androidx.core.view.children
import androidx.core.view.updateLayoutParams
import androidx.core.widget.NestedScrollView
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.ScreenRecordProtectionView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialogButton
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.material.bottomSheetBehavior.BottomSheetBehavior
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.updateThemeForChildren
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt


abstract class WViewController(val context: Context) : WThemedView, WProtectedView {
    abstract val TAG: String

    // Available configurations //////////////////////
    open var title: String? = null
    open var subtitle: String? = null

    open val isLockedScreen = false
    open val isBackAllowed = true
    open val isSwipeBackAllowed = true
    open val isEdgeSwipeBackAllowed = false

    open val ignoreSideGuttering = false

    open val shouldDisplayTopBar = true
    open val topBlurViewGuideline: View? = null
    open val topBarConfiguration: ReversedCornerView.Config by lazy {
        ReversedCornerView.Config(
            blurRootView = view
        )
    }

    open val shouldDisplayBottomBar = false
    open val bottomBlurRootView: ViewGroup? by lazy {
        topBarConfiguration.blurRootView
    }

    open val protectFromScreenRecord = false

    // App will switch to displayed account id whenever screen is appeared
    data class DisplayedAccount(val accountId: String?, val isPushedTemporary: Boolean) {
        val network: MBlockchainNetwork
            get() {
                return accountId?.let { MBlockchainNetwork.ofAccountId(it) }
                    ?: MBlockchainNetwork.MAINNET
            }
    }

    open val displayedAccount: DisplayedAccount? = null
    //////////////////////////////////////////////////

    // ContainerView /////////////////////////////////
    open val view: ContainerView by lazy {
        ContainerView(WeakReference(this)).apply {
        }
    }
    var navigationBar: WNavigationBar? = null

    var isKeyboardOpen = false
        private set

    open fun insetsUpdated() {
        isKeyboardOpen = (window?.imeInsets?.bottom ?: 0) > 0
        if (!ignoreSideGuttering) {
            val padding = ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat()
            topReversedCornerView?.setHorizontalPadding(padding)
            bottomReversedCornerView?.setHorizontalPadding(padding)
        }
        activeDialog?.insetsUpdated()
    }

    // Called from NavigationController, whenever the vc layout changes during keyboard animation.
    open fun keyboardAnimationFrameRendered() {}

    private var isViewConfigured = false
    private var isViewAppearanceAnimationInProgress = false

    @SuppressLint("ViewConstructor")
    open class ContainerView(val viewController: WeakReference<WViewController>) :
        WView(viewController.get()!!.context), WProtectedView {
        override fun setupViews() {
            super.setupViews()
            viewController.get()?.setupViews()
        }

        override fun updateProtectedView() {
            viewController.get()?.updateProtectedView()
        }

        override fun didSetupViews() {
            super.didSetupViews()
            viewController.get()?.didSetupViews()
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            viewController.get()?.onViewAttachedToWindow()
        }

        private var initialX: Float? = null
        private var initialY: Float? = null
        private var isScrollingVertical: Boolean? = null
        override fun onInterceptTouchEvent(ev: MotionEvent?): Boolean {
            // Should not let children get touch if view-controller is not enabled
            if (!isEnabled)
                return true
            if (viewController.get()?.isViewAppearanceAnimationInProgress != true &&
                (
                    viewController.get()?.isSwipeBackAllowed == true || // is swipe allowed
                        isScrollingVertical == false || // it's already swiping
                        viewController.get()?.isEdgeSwipeBackAllowed == true &&
                        ((!LocaleController.isRTL && (ev?.x ?: 60f.dp) < 60f.dp) ||
                            (LocaleController.isRTL && (ev?.x ?: 0f) > (width - 60f.dp)))
                    ) &&
                (viewController.get()?.navigationController?.viewControllers?.size ?: 0) > 1
            ) {
                ev?.let {
                    val swipeTouchListener = viewController.get()?.swipeTouchListener
                    when (it.action) {
                        MotionEvent.ACTION_DOWN -> {
                            swipeTouchListener?.onTouch(this, ev)
                            if (isScrollingVertical != null)
                                isScrollingVertical = null
                            initialX = it.x
                            initialY = it.y
                        }

                        MotionEvent.ACTION_MOVE -> {
                            if (initialX == null)
                                return@let
                            if (isScrollingVertical == null) {
                                val diffX = abs(it.x - initialX!!)
                                val diffY = abs(it.y - initialY!!)
                                if (diffX > 20)
                                    isScrollingVertical = false
                                else if (diffY > 10)
                                    isScrollingVertical = true
                                if (isScrollingVertical != null) {
                                    initialX = it.x
                                    initialY = it.y
                                }
                            }
                            when (isScrollingVertical) {
                                false -> {
                                    // Horizontal scroll detected
                                    swipeTouchListener?.onTouch(
                                        this,
                                        ev
                                    )
                                    return true
                                }

                                null -> return false
                                else -> {
                                    // scroll normally :)
                                }
                            }
                        }

                        else -> {
                            isScrollingVertical = null
                            initialX = null
                            initialY = null
                            swipeTouchListener?.onTouch(this, ev)
                        }
                    }
                }
            }
            return super.onInterceptTouchEvent(ev)
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent?): Boolean {
            event?.let {
                val swipeTouchListener = viewController.get()?.swipeTouchListener
                when (event.action) {
                    MotionEvent.ACTION_MOVE -> {
                        if (initialX == null)
                            return@let
                        if (isScrollingVertical == false) {
                            swipeTouchListener?.onTouch(
                                this,
                                event
                            )
                            return true
                        }
                    }

                    else -> {
                        isScrollingVertical = null
                        initialX = null
                        initialY = null
                        swipeTouchListener?.onTouch(this, event)
                    }
                }
            }
            return super.onTouchEvent(event)
        }

        override fun onDetachedFromWindow() {
            super.onDetachedFromWindow()
            viewController.get()?.onViewDetachedFromWindow()
        }
    }
    //////////////////////////////////////////////////

    // Performance Tracker ///////////////////////////
    open val shouldMonitorFrames = false
    private val frameMonitor: WFramePerformanceMonitor? by lazy {
        if (window == null)
            return@lazy null
        WFramePerformanceMonitor(
            activity = window!!,
            isEnabled = shouldMonitorFrames
        ).apply {
            setContextProvider { getPerformanceContext() }
            setCallback(object : WFramePerformanceMonitor.PerformanceCallback {
                override fun onFrameDropDetected(
                    frameDuration: Long,
                    droppedFrames: Int,
                    context: String?
                ) {
                    onFramePerformanceIssue(frameDuration, droppedFrames, false)
                }

                override fun onSevereFrameDrop(
                    frameDuration: Long,
                    droppedFrames: Int,
                    context: String?
                ) {
                    onFramePerformanceIssue(frameDuration, droppedFrames, true)
                }

                override fun onPerformanceSummary(frameDropRate: Float, sessionInfo: String) {
                    if (frameDropRate > 2.0f) {
                        Logger.w(
                            Logger.LogTag.FPS_PERFORMANCE,
                            "onPerformanceSummary: Poor performance dropRate=${frameDropRate}%"
                        )
                    }
                }
            })
        }
    }

    private fun getPerformanceContext(): String {
        return "$this"
    }

    protected open fun onFramePerformanceIssue(
        frameDuration: Long,
        droppedFrames: Int,
        isSevere: Boolean
    ) {
        if (isSevere) {
            Logger.w(
                Logger.LogTag.FPS_PERFORMANCE,
                "onFramePerformanceIssue: Serious performance issue detected!"
            )
        }
    }

    // Presentation //////////////////////////////////

    // Navigation controller will be set from presenter navigationController once pushed
    var navigationController: WNavigationController? = null
    val window: WWindow?
        get() {
            return navigationController?.window
        }
    var swipeTouchListener: SwipeTouchListener? = null

    fun push(viewController: WViewController, onCompletion: (() -> Unit)? = null) {
        navigationController?.push(viewController, true, onCompletion)
    }

    fun pop() {
        navigationController?.pop()
    }

    var activeDialog: WDialog? = null
        private set

    fun setActiveDialog(dialog: WDialog?) {
        activeDialog = dialog
    }

    // Return FALSE if consumed the back event.
    open fun onBackPressed(): Boolean {
        if (activeDialog != null) {
            activeDialog?.dismiss()
            return false
        }
        return true
    }
    //////////////////////////////////////////////////

    // Lifecycle callbacks ///////////////////////////
    open fun setupViews() {
        if (protectFromScreenRecord && window?.isScreenRecordInProgress == true)
            presentScreenRecordProtectionView()
    }

    open fun onViewAttachedToWindow() {
        navigationController?.tabBarController?.let { tabBarController ->
            view.post {
                tabBarController.resumeBlurring()
            }
        }
        if (isViewConfigured) {
            isDisappeared = false
            if (pendingThemeChange)
                notifyThemeChanged()
            return
        }
        isViewConfigured = true
        // setup views is called in the containerView.onAttachedToWindow, already.
        navigationBar?.bringToFront()
        topBlurViewGuideline?.bringToFront()
    }

    // Called after `setupViews` and `onViewAttachedToWindow`
    open fun didSetupViews() {
        if (overrideShowTopBlurView ?: shouldDisplayTopBar)
            addTopCornerRadius()
        if (shouldDisplayBottomBar)
            addBottomCornerRadius()
    }

    open fun viewWillAppear() {
        Logger.d(Logger.LogTag.SCREEN, "VCWillAppear: $TAG hash=${hashCode()}")
        if (!isDisappeared)
            return
        isDisappeared = false
        if (pendingThemeChange)
            notifyThemeChanged()
        insetsUpdated()
        topReversedCornerView?.resumeBlurring()
        bottomReversedCornerView?.resumeBlurring()
        isViewAppearanceAnimationInProgress = true
    }

    // Called when view-controller appears (NOT called when overlay navigation controller dismissed)
    open fun viewDidAppear() {
        Logger.d(Logger.LogTag.SCREEN, "VCDidAppear: $TAG hash=${hashCode()}")
        isViewAppearanceAnimationInProgress = false
        frameMonitor?.startMonitoring()
        viewDidEnterForeground()
    }

    // Called when view-controller becomes top view (Called EVEN WHEN overlay navigation controller dismissed)
    open fun viewDidEnterForeground() {
        WalletCore.doOnBridgeReady {
            switchToDisplayedAccountId()
        }
    }

    // Called when user pushes a new view controller, pops view controller (goes back) or finishes the window (activity)!
    var isDisappeared = true
    var isDestroyed = false
        private set

    // Called when:
    //  - Navigation-controller will push another view-controller over it
    //  - Another navigation-controller is completely presented over it.
    //  - Window will replace it with another navigation controller
    open fun viewWillDisappear() {
        Logger.i(Logger.LogTag.SCREEN, "VCWillDisappear: $TAG ${hashCode()}")
        if (isDisappeared)
            return
        view.hideKeyboard()
        isDisappeared = true
        frameMonitor?.stopMonitoring()
    }

    // Called when view is detached totally
    open fun onViewDetachedFromWindow() {}

    open fun onDestroy() {
        isDestroyed = true
        frameMonitor?.stopMonitoring()
        view.removeAllViews()
    }
    //////////////////////////////////////////////////

    // Protect screen record
    var screenRecordProtectionView: ScreenRecordProtectionView? = null
    fun onScreenRecordStateChanged(isRecording: Boolean) {
        if (!protectFromScreenRecord)
            return
        if (isRecording) {
            presentScreenRecordProtectionView()
        } else {
            dismissScreenRecordProtectionView(proceed = false)
        }
    }

    open fun presentScreenRecordProtectionView() {
        if (screenRecordProtectionView == null) {
            screenRecordProtectionView = ScreenRecordProtectionView(this, {
                dismissScreenRecordProtectionView(proceed = true)
            })
            screenRecordProtectionView?.clearAnimation()
            screenRecordProtectionView?.alpha = 1f
            view.addView(screenRecordProtectionView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    private fun dismissScreenRecordProtectionView(proceed: Boolean) {
        if (screenRecordProtectionView?.parent != null)
            screenRecordProtectionView?.fadeOut {
                // Double check if it's not recording yet
                if (proceed || window?.isScreenRecordInProgress != true)
                    view.removeView(screenRecordProtectionView)
                screenRecordProtectionView = null
            }
    }
    //////////////////////////////////////////////////

    var pendingThemeChange = false
    private var _isDarkThemeApplied: Boolean? = null
    open fun notifyThemeChanged() {
        if (isDisappeared) {
            pendingThemeChange = true
            return
        }
        val themeChanged = ThemeManager.isDark != _isDarkThemeApplied || pendingThemeChange
        _isDarkThemeApplied = ThemeManager.isDark
        pendingThemeChange = false
        if (themeChanged || isTinted)
            updateTheme()
        updateThemeForChildren(view, onlyTintedViews = !themeChanged)
        if (themeChanged) {
            topReversedCornerView?.let { topReversedCornerView ->
                view.setConstraints {
                    toTop(
                        topReversedCornerView,
                    )
                    (topBlurViewGuideline ?: navigationBar)?.let {
                        bottomToBottom(
                            topReversedCornerView,
                            it,
                            -ViewConstants.TOOLBAR_RADIUS
                        )
                        return@setConstraints
                    }
                }
            }
            if (bottomReversedCornerView?.parent != null)
                bottomReversedCornerView?.updateLayoutParams {
                    height = ViewConstants.TOOLBAR_RADIUS.dp.roundToInt() +
                        (navigationController?.getSystemBars()?.bottom ?: 0)
                }
        }
    }

    override fun updateTheme() {
    }

    override fun updateProtectedView() {}

    fun setupNavBar(shouldShow: Boolean, defaultHeight: Int = WNavigationBar.DEFAULT_HEIGHT) {
        if (navigationController == null)
            throw Exception()
        if (shouldShow) {
            if (navigationBar == null) {
                navigationBar =
                    WNavigationBar(
                        this,
                        defaultHeight
                    )
                view.addView(navigationBar, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            }
            navigationBar!!.setTitle(title ?: "", false)
            navigationBar!!.setSubtitle(subtitle, false)
            navigationBar?.visibility = View.VISIBLE
        } else {
            navigationBar?.visibility = View.GONE
        }
    }

    fun setNavTitle(title: String, animated: Boolean = true) {
        this.title = title
        navigationBar?.setTitle(title, animated)
    }

    fun setNavSubtitle(subtitle: String, animated: Boolean = true) {
        this.subtitle = subtitle
        navigationBar?.setSubtitle(subtitle, animated)
    }

    open fun showError(error: MBridgeError?) {
        showAlert(
            LocaleController.getString("Error"),
            (error ?: MBridgeError.UNKNOWN).toLocalized
        )
    }

    // All the view-controllers should implement scrollToTop, if required.
    open fun scrollToTop() {}

    // Top blur view
    fun setTopBlur(visible: Boolean, animated: Boolean) {
        overrideShowTopBlurView = visible
        topReversedCornerView?.let {
            it.setBackgroundVisible(visible, animated)
            return
        }
        if (visible) {
            addTopCornerRadius()
            navigationBar?.bringToFront()
            topBlurViewGuideline?.bringToFront()
        }
    }

    fun setTopBlurSeparator(visible: Boolean) {
        topReversedCornerView?.let {
            it.setShowSeparator(visible)
            return
        }
    }

    fun setBottomBlurSeparator(visible: Boolean) {
        bottomReversedCornerView?.let {
            it.setShowSeparator(visible)
            return
        }
    }

    private var overrideShowTopBlurView: Boolean? = null
    var topReversedCornerView: ReversedCornerView? = null
        private set

    private fun addTopCornerRadius() {
        topReversedCornerView = ReversedCornerView(
            context,
            topBarConfiguration
        )
        if (ignoreSideGuttering)
            topReversedCornerView?.setHorizontalPadding(0f)
        view.addView(
            topReversedCornerView!!,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                0
            )
        )
        view.setConstraints {
            toTop(
                topReversedCornerView!!,
            )
            (topBlurViewGuideline ?: navigationBar)?.let {
                bottomToBottom(
                    topReversedCornerView!!,
                    it,
                    -ViewConstants.TOOLBAR_RADIUS
                )
                return@setConstraints
            }
        }
    }

    var bottomReversedCornerView: ReversedCornerViewUpsideDown? = null

    // Add bottom corner radius to the view controller
    private fun WViewController.addBottomCornerRadius() {
        bottomReversedCornerView = ReversedCornerViewUpsideDown(context, bottomBlurRootView)
        if (ignoreSideGuttering)
            bottomReversedCornerView?.setHorizontalPadding(0f)
        view.addView(
            bottomReversedCornerView,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                ViewConstants.TOOLBAR_RADIUS.dp.roundToInt() +
                    (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        )
        view.setConstraints {
            toBottom(bottomReversedCornerView!!)
        }
    }

    fun updateBlurViews(recyclerView: RecyclerView) {
        updateBlurViews(recyclerView, recyclerView.computeVerticalScrollOffset())
    }

    fun updateBlurViews(scrollView: ViewGroup, computedOffset: Int) {
        val topOffset =
            if (computedOffset >= 0) computedOffset else computedOffset + scrollView.paddingTop
        val isOnTop = topOffset <= 0
        if (!isOnTop) {
            topReversedCornerView?.resumeBlurring()
            topReversedCornerView?.setBlurAlpha((topOffset / 20f.dp).coerceIn(0f, 1f))
            bottomReversedCornerView?.resumeBlurring()
            navigationController?.tabBarController?.resumeBlurring()
        } else {
            topReversedCornerView?.pauseBlurring(false)
            bottomReversedCornerView?.pauseBlurring()
            if (navigationController?.tabBarController?.activeNavigationController == navigationController)
                navigationController?.tabBarController?.pauseBlurring()
        }
    }

    // Modal methods
    open val isExpandable: Boolean
        get() {
            return getModalHalfExpandedHeight() != null
        }

    open fun getModalHalfExpandedHeight(): Int? {
        return null
    }

    protected var modalExpandOffset: Int? = null
    protected var modalExpandProgress: Float? = null
    open fun onModalSlide(expandOffset: Int, expandProgress: Float) {
        modalExpandOffset = expandOffset
        modalExpandProgress = expandProgress
        navigationBar?.expansionValue = expandProgress
        topReversedCornerView?.translationZ = navigationBar?.translationZ ?: 0f
        if (expandProgress < 1) {
            // Use fixed radius when Rounded Corners is off, otherwise use BLOCK_RADIUS
            val halfExpandedRadius =
                if (ViewConstants.BLOCK_RADIUS == 0f) 24f.dp else ViewConstants.BLOCK_RADIUS.dp
            topReversedCornerView?.setBackgroundColor(
                Color.TRANSPARENT,
                min(1f, ((1 - expandProgress) * 5)) * halfExpandedRadius,
                0f,
                true
            )
        } else {
            topReversedCornerView?.background = null
        }
        val contentTranslationY = ((1 - expandProgress) * (navigationBar?.height ?: 0))
        contentTranslationY.let {
            view.apply {
                clipChildren = false
                clipToPadding = false
                translationY = contentTranslationY
            }
            (view.children.firstOrNull() as? NestedScrollView)
                ?.children?.firstOrNull()?.translationY = -contentTranslationY
        }
    }

    fun toggleModalState() {
        val behavior = (view.layoutParams as LayoutParams).behavior as BottomSheetBehavior<*>

        if (behavior.state == BottomSheetBehavior.STATE_HALF_EXPANDED) {
            behavior.state = BottomSheetBehavior.STATE_EXPANDED
        } else {
            behavior.state = BottomSheetBehavior.STATE_HALF_EXPANDED
        }
    }

    private var isHeavyAnimationIsProgress = false
    fun heavyAnimationInProgress() {
        if (isHeavyAnimationIsProgress)
            return
        isHeavyAnimationIsProgress = true
        WGlobalStorage.incDoNotSynchronize()
    }

    fun heavyAnimationDone() {
        if (!isHeavyAnimationIsProgress)
            return
        isHeavyAnimationIsProgress = false
        WGlobalStorage.decDoNotSynchronize()
    }

    private fun switchToDisplayedAccountId() {
        val displayedAccount = this@WViewController.displayedAccount ?: return
        val displayedAccountId = displayedAccount.accountId ?: return
        if (WalletCore.nextAccountId == displayedAccountId)
            return
        if (WalletCore.nextAccountId == null && AccountStore.activeAccountId == displayedAccountId)
            return
        if (!WGlobalStorage.accountExists(displayedAccountId)) {
            pop()
            return
        }
        Logger.d(Logger.LogTag.ACCOUNT, "switchToDisplayedAccountId: account=$displayedAccountId")
        WalletCore.activateAccount(
            displayedAccountId,
            notifySDK = true,
            isPushedTemporary = displayedAccount.isPushedTemporary
        ) { activeAccount, err ->
            if (activeAccount == null || err != null) {
                throw Error()
            }
            WalletCore.notifyEvent(
                WalletEvent.AccountChangedInApp(
                    persistedAccountsModified = false
                )
            )
        }
    }
}

// Present an alert popup
fun WViewController.showAlert(
    title: String?,
    text: CharSequence,
    button: String = LocaleController.getString("OK"),
    buttonPressed: (() -> Unit)? = null,
    secondaryButton: String? = null,
    secondaryButtonPressed: (() -> Unit)? = null,
    preferPrimary: Boolean = true,
    primaryIsDanger: Boolean = false,
    allowLinkInText: Boolean = false,
): WDialog {
    val dialog = WDialog(
        customView = FrameLayout(context).apply {
            val messageLabel = object : WLabel(context), WThemedView {
                init {
                    if (allowLinkInText) {
                        movementMethod = LinkMovementMethod.getInstance()
                    }
                    highlightColor = Color.TRANSPARENT
                }

                override fun updateTheme() {
                    super.updateTheme()
                    setTextColor(WColor.PrimaryText.color)
                }
            }
            messageLabel.apply {
                setStyle(14f)
                this.text = text
                updateTheme()
            }
            addView(messageLabel, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                marginStart = 24.dp
                marginEnd = 24.dp
            })
        }, WDialog.Config(
            title,
            actionButton = WDialogButton.Config(
                title = button,
                onTap = buttonPressed,
                style = if (primaryIsDanger) WDialogButton.Config.Style.DANGER else
                    if (preferPrimary) WDialogButton.Config.Style.PREFERRED else WDialogButton.Config.Style.NORMAL
            ),
            secondaryButton = if (secondaryButton != null) WDialogButton.Config(
                title = secondaryButton,
                onTap = secondaryButtonPressed,
                style = WDialogButton.Config.Style.NORMAL
            ) else null
        )
    )
    dialog.presentOn(this)
    return dialog
}

fun WViewController.executeWithLowPriority(block: () -> Unit) {
    Handler(Looper.getMainLooper()).postDelayed({
        Looper.myQueue().addIdleHandler(IdleHandler {
            block()
            false
        })
    }, 100)
}
