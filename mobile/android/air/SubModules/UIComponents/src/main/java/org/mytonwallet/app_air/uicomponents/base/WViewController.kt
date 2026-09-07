@file:Suppress("ktlint:standard:backing-property-naming")

package org.mytonwallet.app_air.uicomponents.base

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
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
import android.widget.ImageView
import android.widget.ScrollView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintSet
import androidx.coordinatorlayout.widget.CoordinatorLayout.LayoutParams
import androidx.core.graphics.createBitmap
import androidx.core.view.children
import androidx.core.view.updateLayoutParams
import androidx.core.widget.NestedScrollView
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.ScreenRecordProtectionView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialogButton
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
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
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.stores.AccountStore

abstract class WViewController(val context: Context) :
    WThemedView,
    WProtectedView {
    companion object {

        // How long a scrollable must rest before paused blur views resume after an over-scroll.
        private const val OVER_SCROLL_SETTLE_DELAY = 500L

        // Bottom edge of the top tab bar, measured from the system bars: its top margin plus its
        // centering offset and height. Kept in sync with the tab container's TOP_TABS_TOP_MARGIN
        // and TOP_TABS_BOTTOM_EDGE.
        private const val ROOT_TOP_TABS_HEIGHT = 52

        // Breathing room between the tab bar and the bottom of the blur overlay.
        private const val ROOT_TOP_BLUR_BOTTOM_MARGIN = 4
    }

    @Suppress("PropertyName")
    abstract val TAG: String

    // Available configurations //////////////////////
    open var title: String? = null
    open var subtitle: String? = null

    open val isLockedScreen = false
    open val isBackAllowed = true
    open val isSwipeBackAllowed = true
    open val isEdgeSwipeBackAllowed = false

    open val ignoreSideGuttering = false

    // If the view-controller is presented in the content panel on tablet, returns the `ADDITIONAL_TABLET_PADDING`
    open val additionalTabletPadding: Int
        get() {
            return if (isSplitDetailPanel) {
                ViewConstants.ADDITIONAL_TABLET_PADDING
            } else {
                0
            }
        }

    open val shouldDisplayTopBar = true
    open val topBlurViewGuideline: View? = null
    open val topBarConfiguration: ReversedCornerView.Config by lazy {
        ReversedCornerView.Config(
            blurRootView = view,
            additionalTabletPadding = isSplitDetailPanel
        )
    }

    val isInCenteredWindow: Boolean
        get() = navigationController?.isCenteredWindow == true

    open val shouldDisplayBottomBar: Boolean
        get() {
            return window?.isWideLayout == true && !isInCenteredWindow
        }

    private val systemBarBottomInset: Int
        get() = if (isInCenteredWindow) 0 else window?.systemBars?.bottom ?: 0

    private val bottomCornerInset: Int
        get() = if (bottomReversedCornerView?.isGradientMode == true) {
            navigationController?.getSystemBars()?.bottom ?: 0
        } else {
            systemBarBottomInset
        }

    private val shouldShowBottomCornerRadius: Boolean
        get() = shouldDisplayBottomBar &&
            !isInCenteredWindow &&
            systemBarBottomInset > 0

    open val forceBlurBottomView = false
    open val bottomBlurRootView: ViewGroup? by lazy {
        topBarConfiguration.blurRootView
    }

    open val protectFromScreenRecord = false
    open val shouldHideKeyboardOnDisappear = true

    // App will switch to displayed account id whenever screen is appeared
    data class DisplayedAccount(val accountId: String?, val isPushedTemporary: Boolean) {
        val network: MBlockchainNetwork
            get() {
                return accountId?.let { MBlockchainNetwork.ofAccountId(it) }
                    ?: MBlockchainNetwork.MAINNET
            }
    }

    open val displayedAccount: DisplayedAccount? = null
    // ////////////////////////////////////////////////

    // ContainerView /////////////////////////////////
    open val view: ContainerView by lazy {
        ContainerView(WeakReference(this)).apply {
        }
    }
    var navigationBar: WNavigationBar? = null

    var isKeyboardOpen = false
        private set

    open val isContentWidthCapped = false

    protected fun updateBlurPaddings() {
        if (topReversedCornerView == null && bottomReversedCornerView == null) return
        val basePadding =
            if (ignoreSideGuttering) 0f else ViewConstants.HORIZONTAL_PADDINGS.dp.toFloat()
        val maxContentWidth =
            if (isContentWidthCapped) WWindow.WIDE_LAYOUT_INNER_WIDTH_DP.dp.toFloat() else 0f
        val tabletContentStartPadding =
            if (ignoreSideGuttering && isSplitDetailPanel &&
                !isInCenteredWindow
            ) {
                -ViewConstants.TABLET_CONTENT_START_PADDING.dp
            } else {
                0f
            }
        topReversedCornerView?.apply {
            setHorizontalPadding(basePadding)
            setSideInsets(
                tabletContentStartPadding +
                    if (ignoreSideGuttering) 0f else systemBarStartInset.toFloat(),
                if (ignoreSideGuttering) 0f else systemBarEndInset.toFloat()
            )
            setMaxContentWidth(maxContentWidth)
        }
        bottomReversedCornerView?.apply {
            setHorizontalPadding(basePadding)
            setSideInsets(
                tabletContentStartPadding +
                    if (ignoreSideGuttering) 0f else systemBarStartInset.toFloat(),
                if (ignoreSideGuttering) 0f else systemBarEndInset.toFloat()
            )
            setMaxContentWidth(maxContentWidth)
        }
    }

    open fun onSizeChanged(w: Int, h: Int, oldW: Int, oldH: Int) {
        if (isContentWidthCapped && w != oldW) updateBlurPaddings()
    }

    val isSplitDetailPanel: Boolean
        get() = navigationController?.tabBarController != null
    val systemBarStartInset: Int
        get() {
            if (isSplitDetailPanel) return 0
            val bars = navigationController?.getSystemBars() ?: return 0
            return if (LocaleController.isRTL) bars.right else bars.left
        }
    val systemBarEndInset: Int
        get() {
            val bars = navigationController?.getSystemBars() ?: return 0
            return if (LocaleController.isRTL) bars.left else bars.right
        }

    private var centeredWindowCloseButtonAdded = false
    open fun insetsUpdated() {
        if (!isViewConfigured) return
        isKeyboardOpen = (window?.imeInsets?.bottom ?: 0) > 0
        navigationBar?.insetsUpdated()
        topReversedCornerView?.let { layoutTopOverlay(it) }
        activeDialogs.forEach { it.insetsUpdated() }
        if (isInCenteredWindow && !centeredWindowCloseButtonAdded) {
            if (navigationBar?.addCloseButton() == true) centeredWindowCloseButtonAdded = true
        } else if (!isInCenteredWindow && centeredWindowCloseButtonAdded) {
            centeredWindowCloseButtonAdded = false
            navigationBar?.removeCloseButton()
        }
        syncBottomCornerRadius()
        updateBlurPaddings()
        refreshBottomCornerRadiusHeight()
    }

    // Called from NavigationController, whenever the vc layout changes during keyboard animation.
    open fun keyboardAnimationFrameRendered() {}

    var isViewConfigured = false
        private set
    private var isViewAppearanceAnimationInProgress = false

    @SuppressLint("ViewConstructor")
    open class ContainerView(val viewController: WeakReference<WViewController>) :
        WView(viewController.get()!!.context),
        WProtectedView {
        override fun setupViews() {
            super.setupViews()
            viewController.get()?.setupViews()
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            viewController.get()?.onSizeChanged(w, h, oldw, oldh)
        }

        override fun updateProtectedView() {
            viewController.get()?.updateProtectedView()
        }

        override fun didSetupViews() {
            super.didSetupViews()
            viewController.get()?.let {
                it.didSetupViews()
                it.onViewSetupCompleted()
            }
        }

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            viewController.get()?.onViewAttachedToWindow()
        }

        private var initialX: Float? = null
        private var initialY: Float? = null
        private var isScrollingVertical: Boolean? = null

        private fun canHandleSwipeBack(ev: MotionEvent?): Boolean =
            viewController.get()?.isViewAppearanceAnimationInProgress != true &&
                (
                    viewController.get()?.isSwipeBackAllowed == true || // is swipe allowed
                        isScrollingVertical == false || // it's already swiping
                        (
                            viewController.get()?.isEdgeSwipeBackAllowed == true &&
                                (
                                    (!LocaleController.isRTL && (ev?.x ?: 60f.dp) < 60f.dp) ||
                                        (LocaleController.isRTL && (ev?.x ?: 0f) > (width - 60f.dp))
                                    )
                            )
                    ) &&
                (viewController.get()?.navigationController?.viewControllers?.size ?: 0) > 1 &&
                isEnabled

        override fun onInterceptTouchEvent(ev: MotionEvent?): Boolean {
            if (!isEnabled) return true
            if (canHandleSwipeBack(ev)) {
                ev?.let {
                    val swipeTouchListener = viewController.get()?.swipeTouchListener
                    when (it.action) {
                        MotionEvent.ACTION_DOWN -> {
                            swipeTouchListener?.onTouch(this, ev)
                            if (isScrollingVertical != null) isScrollingVertical = null
                            initialX = it.x
                            initialY = it.y
                        }

                        MotionEvent.ACTION_MOVE -> {
                            if (initialX == null) return@let
                            if (isScrollingVertical == null) {
                                val diffX = abs(it.x - initialX!!)
                                val diffY = abs(it.y - initialY!!)
                                if (diffX > 20) {
                                    isScrollingVertical = false
                                } else if (diffY > 10) {
                                    isScrollingVertical = true
                                }
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
            if (!isEnabled) {
                isScrollingVertical = null
                initialX = null
                initialY = null
                viewController.get()?.swipeTouchListener?.cancelSwipe()
                return true
            }
            event?.let {
                val swipeTouchListener = viewController.get()?.swipeTouchListener
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        if (canHandleSwipeBack(event)) {
                            swipeTouchListener?.onTouch(this, event)
                            isScrollingVertical = null
                            initialX = it.x
                            initialY = it.y
                            return true
                        }
                    }

                    MotionEvent.ACTION_MOVE -> {
                        if (initialX == null) return@let
                        if (isScrollingVertical == null) {
                            val diffX = abs(it.x - initialX!!)
                            val diffY = abs(it.y - initialY!!)
                            if (diffX > 20) {
                                isScrollingVertical = false
                            } else if (diffY > 10) {
                                isScrollingVertical = true
                            }
                            if (isScrollingVertical != null) {
                                initialX = it.x
                                initialY = it.y
                            }
                        }
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
    // ////////////////////////////////////////////////

    // Performance Tracker ///////////////////////////
    open val shouldMonitorFrames = false
    private val frameMonitor: WFramePerformanceMonitor? by lazy {
        if (window == null) return@lazy null
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
                            "onPerformanceSummary: Poor performance dropRate=$frameDropRate%"
                        )
                    }
                }
            })
        }
    }

    private fun getPerformanceContext(): String = "$this"

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

    private val _activeDialogs = mutableListOf<WDialog>()
    val activeDialogs: List<WDialog> get() = _activeDialogs
    val topActiveDialog: WDialog? get() = _activeDialogs.lastOrNull()

    fun addActiveDialog(dialog: WDialog) {
        _activeDialogs.add(dialog)
    }

    fun removeActiveDialog(dialog: WDialog) {
        _activeDialogs.remove(dialog)
    }

    fun dismissActiveDialogs() {
        _activeDialogs.toList().forEach { it.dismiss() }
    }

    // Return FALSE if consumed the back event.
    open fun onBackPressed(): Boolean {
        topActiveDialog?.let {
            it.dismiss()
            return false
        }
        return true
    }
    // ////////////////////////////////////////////////

    // Lifecycle callbacks ///////////////////////////
    open fun setupViews() {
        if (protectFromScreenRecord && window?.isScreenRecordInProgress == true) {
            presentScreenRecordProtectionView()
        }
    }

    open fun onViewAttachedToWindow() {}

    private fun onViewSetupCompleted() {
        isViewConfigured = true
        navigationBar?.bringToFront()
        topBlurViewGuideline?.bringToFront()
        // A not-yet-appeared bottom-sheet controller gets its insets from `viewWillAppear`. Applying
        // them here would resize the sheet while the presenting transition is still measuring it.
        val deferInsetsToAppearance = isDisappeared && navigationController?.isBottomSheet == true
        if (!deferInsetsToAppearance) insetsUpdated()
    }

    open fun didSetupViews() {
        if (overrideShowTopBlurView ?: shouldDisplayTopBar) addTopCornerRadius()
        if (isRootTopGradientEnabled) topReversedCornerView?.bringToFront()
        if (shouldShowBottomCornerRadius) addBottomCornerRadius()
        updateBlurPaddings()
    }

    open fun viewWillAppear() {
        Logger.d(Logger.LogTag.SCREEN, "VCWillAppear: $TAG hash=${hashCode()}")
        if (!isDisappeared) return
        isDisappeared = false
        if (pendingThemeChange) notifyThemeChanged()
        if (isViewConfigured) insetsUpdated()
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
    //  - Navigation-controller will pop the view-controller
    //  - Another navigation-controller is completely presented over it.
    //  - Window will replace it with another navigation controller
    open fun viewWillDisappear() {
        Logger.i(Logger.LogTag.SCREEN, "VCWillDisappear: $TAG ${hashCode()}")
        if (isDisappeared) return
        if (shouldHideKeyboardOnDisappear) view.hideKeyboard()
        isDisappeared = true
        frameMonitor?.stopMonitoring()
    }

    // Called when view is detached totally
    open fun onViewDetachedFromWindow() {}

    open fun onDestroy() {
        isDisappeared = true
        isDestroyed = true
        frameMonitor?.stopMonitoring()
        dismissActiveDialogs()
        view.removeAllViews()
    }
    // ////////////////////////////////////////////////

    // Protect screen record
    var screenRecordProtectionView: ScreenRecordProtectionView? = null
    fun onScreenRecordStateChanged(isRecording: Boolean) {
        if (!protectFromScreenRecord) return
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
        if (screenRecordProtectionView?.parent != null) {
            screenRecordProtectionView?.fadeOut {
                // Double check if it's not recording yet
                if (proceed || window?.isScreenRecordInProgress != true) {
                    view.removeView(screenRecordProtectionView)
                }
                screenRecordProtectionView = null
            }
        }
    }
    // ////////////////////////////////////////////////

    var pendingThemeChange = false
    private var _isDarkThemeApplied: Boolean? = null
    open fun notifyThemeChanged() {
        if (isDisappeared) {
            pendingThemeChange = true
            return
        }
        applyThemeChanges()
    }

    fun applyThemeChanges() {
        val themeChanged = ThemeManager.isDark != _isDarkThemeApplied || pendingThemeChange
        _isDarkThemeApplied = ThemeManager.isDark
        pendingThemeChange = false
        if (themeChanged || isTinted) updateTheme()
        updateThemeForChildren(view, onlyTintedViews = !themeChanged)
        syncBottomCornerRadius()
        if (isRootTopGradientEnabled) refreshRootTopOverlayMode()
        if (themeChanged) {
            topReversedCornerView?.let { layoutTopOverlay(it, force = true) }
            bottomReversedCornerView?.refreshModeFromSettings()
            refreshBottomCornerRadiusHeight()
        }
    }

    override fun updateTheme() {
    }

    override fun updateProtectedView() {}

    fun setupNavBar(shouldShow: Boolean, defaultHeight: Int = WNavigationBar.DEFAULT_HEIGHT) {
        if (navigationController == null) throw Exception()
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
            navigationBar!!.setTitleContentVisible(
                navigationController?.usesRootTopGradient(this) != true
            )
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
            (error ?: MBridgeError.Type.UNKNOWN).toLocalized
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
            updateBlurPaddings()
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

    open val topBlurView: View?
        get() = topReversedCornerView ?: navigationBar

    private var rootTopModeApplied: Pair<Boolean, Boolean>? = null

    internal fun refreshRootTopOverlayMode() {
        val isRootTop = isRootTopGradientEnabled
        val useGradient = isRootTop && WGlobalStorage.isGradientNavigationBarActive()
        topReversedCornerView?.let { overlayView ->
            overlayView.setGradientMode(useGradient)
            layoutTopOverlay(overlayView)
        }
        navigationBar?.setTitleContentVisible(!isRootTop)
        val style = isRootTop to useGradient
        if (rootTopModeApplied == style) return
        rootTopModeApplied = style
        onRootTopGradientModeChanged(isRootTop)
    }

    private fun layoutTopOverlay(overlayView: ReversedCornerView, force: Boolean = false) {
        val isRootTop = isRootTopGradientEnabled
        overlayView.gradientFadeStartY =
            (
                (navigationController?.getSystemBars()?.top ?: 0) -
                    (navigationController?.additionalRootTopInset ?: 0)
                ).toFloat()
        val targetHeight = if (isRootTop) rootTopOverlayHeight(overlayView.isGradientMode) else 0
        if (!force && overlayView.layoutParams?.height == targetHeight) return
        overlayView.layoutParams?.let { params ->
            params.height = targetHeight
            overlayView.layoutParams = params
        }
        view.setConstraints {
            toTop(overlayView)
            if (isRootTop) {
                clear(overlayView.id, ConstraintSet.BOTTOM)
                return@setConstraints
            }
            (topBlurViewGuideline ?: navigationBar)?.let {
                bottomToBottom(overlayView, it, -ViewConstants.TOOLBAR_RADIUS)
            }
        }
        if (isRootTop) overlayView.bringToFront()
    }

    protected open fun onRootTopGradientModeChanged(enabled: Boolean) {}

    protected val isRootTopGradientEnabled: Boolean
        get() = navigationController?.usesRootTopGradient(this) == true

    private fun addTopCornerRadius() {
        if (topReversedCornerView != null) return
        val overlayView = ReversedCornerView(context, topBarConfiguration)
        topReversedCornerView = overlayView
        overlayView.setGradientMode(
            isRootTopGradientEnabled && WGlobalStorage.isGradientNavigationBarActive()
        )
        if (ignoreSideGuttering) overlayView.setHorizontalPadding(0f)
        view.addView(overlayView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        layoutTopOverlay(overlayView, force = true)
    }

    private fun rootTopGradientHeight(): Int {
        val systemBarsTop = navigationController?.getSystemBars()?.top ?: 0
        val rootTopInset = navigationController?.additionalRootTopInset ?: 0
        return systemBarsTop - rootTopInset + ROOT_TOP_TABS_HEIGHT.dp
    }

    private fun rootTopBlurHeight(): Int {
        val systemBarsTop = navigationController?.getSystemBars()?.top ?: 0
        val rootTopInset = navigationController?.additionalRootTopInset ?: 0
        return systemBarsTop - rootTopInset +
            (ROOT_TOP_TABS_HEIGHT + ROOT_TOP_BLUR_BOTTOM_MARGIN).dp +
            ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()
    }

    private fun rootTopOverlayHeight(isGradient: Boolean): Int =
        if (isGradient) rootTopGradientHeight() else rootTopBlurHeight()

    var bottomReversedCornerView: ReversedCornerViewUpsideDown? = null

    open val additionalBottomGradientHeight: Int
        get() = 0

    private val bottomGradientFadeEndY: Float
        get() {
            val inset = bottomCornerInset.toFloat()
            return if (navigationController?.tabBarController == null) inset / 2f else inset
        }

    protected fun syncBottomCornerRadius(shouldShow: Boolean = shouldShowBottomCornerRadius) {
        val existing = bottomReversedCornerView
        if (shouldShow && existing == null) {
            addBottomCornerRadius()
        } else if (!shouldShow && existing != null) {
            removeBottomCornerRadius()
        }
    }

    private fun removeBottomCornerRadius() {
        val bottomView = bottomReversedCornerView ?: return
        (bottomView.parent as? ViewGroup)?.removeView(bottomView)
        bottomReversedCornerView = null
    }

    // Add bottom corner radius to the view controller
    private fun WViewController.addBottomCornerRadius() {
        val bottomView = ReversedCornerViewUpsideDown(
            context = context,
            blurRootView = bottomBlurRootView,
            forceBlurView = forceBlurBottomView,
            additionalTabletPadding = isSplitDetailPanel
        )
        bottomReversedCornerView = bottomView
        if (ignoreSideGuttering) bottomView.setHorizontalPadding(0f)
        bottomView.gradientFadeEndY = bottomGradientFadeEndY
        view.addView(
            bottomView,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                bottomReversedCornerViewHeight()
            )
        )
        view.setConstraints {
            toBottom(bottomView)
        }
    }

    private fun bottomReversedCornerViewHeight(): Int {
        val bottomView = bottomReversedCornerView
        return (bottomView?.cornerHeight ?: 0) +
            bottomCornerInset +
            (bottomView?.extraTopHeight ?: 0) +
            if (bottomView?.isGradientMode == true) additionalBottomGradientHeight else 0
    }

    protected fun refreshBottomCornerRadiusHeight() {
        val bottomView = bottomReversedCornerView ?: return
        if (bottomView.parent == null) return
        bottomView.gradientFadeEndY = bottomGradientFadeEndY
        val targetHeight = bottomReversedCornerViewHeight()
        if (bottomView.layoutParams?.height != targetHeight) {
            bottomView.updateLayoutParams { height = targetHeight }
        }
        view.setConstraints {
            toBottom(bottomView)
        }
    }

    open fun updateBlurViews(recyclerView: RecyclerView) {
        updateBlurViews(recyclerView, recyclerView.computeVerticalScrollOffset())
    }

    fun updateBlurViews(scrollView: WScrollView) {
        updateBlurViews(scrollView, scrollView.scrollY)
    }

    fun updateBlurViews(scrollView: ScrollView) {
        updateBlurViews(scrollView = scrollView, computedOffset = scrollView.scrollY)
    }

    private fun updateBlurViews(scrollView: ViewGroup, computedOffset: Int) {
        val topOffset =
            if (computedOffset >= 0) computedOffset else computedOffset + scrollView.paddingTop
        topReversedCornerView?.setBlurAlpha((topOffset / 20f.dp).coerceIn(0f, 1f))
    }

    // Modal methods
    open val isExpandable: Boolean
        get() {
            return getModalHalfExpandedHeight() != null
        }

    open fun getModalHalfExpandedHeight(): Int? = null

    protected var modalExpandOffset: Int? = null
    protected var modalExpandProgress: Float? = null

    val isModalFullyExpanded: Boolean
        get() = modalExpandProgress == 1f

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
        val behavior = (view.layoutParams as? LayoutParams)?.behavior
            as? BottomSheetBehavior<*> ?: return

        if (behavior.state == BottomSheetBehavior.STATE_HALF_EXPANDED) {
            behavior.state = BottomSheetBehavior.STATE_EXPANDED
        } else {
            behavior.state = BottomSheetBehavior.STATE_HALF_EXPANDED
        }
    }

    private var isHeavyAnimationIsProgress = false
    fun heavyAnimationInProgress() {
        if (isHeavyAnimationIsProgress) return
        isHeavyAnimationIsProgress = true
        WGlobalStorage.incDoNotSynchronize()
    }

    fun heavyAnimationDone() {
        if (!isHeavyAnimationIsProgress) return
        isHeavyAnimationIsProgress = false
        WGlobalStorage.decDoNotSynchronize()
    }

    // Snapshots the current content, applies `update` (e.g. replacing the nav root), then
    // cross-fades: the snapshot fades out on top of the new content while `fadeInView`
    // (resolved after `update`, since it may not exist before) optionally fades in under it.
    @SuppressLint("ClickableViewAccessibility")
    fun updateWithCrossFade(
        duration: Long = AnimationConstants.QUICK_ANIMATION,
        fadeInView: (() -> View?)? = null,
        update: () -> Unit
    ) {
        val container = navigationController
        if (container == null ||
            view.width <= 0 || view.height <= 0 ||
            !WGlobalStorage.getAreAnimationsActive()
        ) {
            update()
            return
        }

        val bitmap = createBitmap(view.width, view.height)
        view.draw(Canvas(bitmap))
        val snapshotView = ImageView(context).apply {
            setImageBitmap(bitmap)
            scaleType = ImageView.ScaleType.FIT_XY
            setOnTouchListener { _, _ -> true }
        }

        update()

        container.addView(
            snapshotView,
            ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        fadeInView?.invoke()?.let {
            it.alpha = 0f
            it.fadeIn(duration)
        }
        snapshotView.fadeOut(duration) {
            container.removeView(snapshotView)
            bitmap.recycle()
        }
    }

    private fun switchToDisplayedAccountId() {
        val displayedAccount = this@WViewController.displayedAccount ?: return
        val displayedAccountId = displayedAccount.accountId ?: return
        // Check if displayed account will be activated
        if (WalletCore.nextAccountId == displayedAccountId) return
        // Check if displayed account is already activated
        if (WalletCore.nextAccountId == null &&
            AccountStore.activeAccountId == displayedAccountId
        ) {
            return
        }
        if (!WGlobalStorage.accountExists(displayedAccountId)) {
            if (WGlobalStorage.accountIds().isEmpty()) {
                // Resetting accounts is in progress; should not pop.
                return
            }
            // Account doesn't exist anymore, pop to the previous screen.
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
                if (err?.type == MBridgeError.Type.BRIDGE_INTERRUPTED) return@activateAccount
                Logger.e(
                    Logger.LogTag.ACCOUNT,
                    "switchToDisplayedAccountId: Failed account=$displayedAccountId err=$err"
                )
                WalletContextManager.delegate?.get()?.restartApp()
                return@activateAccount
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
    allowLinkInText: Boolean = false
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
            addView(
                messageLabel,
                FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    marginStart = 24.dp
                    marginEnd = 24.dp
                }
            )
        },
        WDialog.Config(
            title,
            actionButton = WDialogButton.Config(
                title = button,
                onTap = buttonPressed,
                style = when {
                    primaryIsDanger -> WDialogButton.Config.Style.DANGER
                    preferPrimary -> WDialogButton.Config.Style.PREFERRED
                    else -> WDialogButton.Config.Style.NORMAL
                }
            ),
            secondaryButton = if (secondaryButton != null) {
                WDialogButton.Config(
                    title = secondaryButton,
                    onTap = secondaryButtonPressed,
                    style = WDialogButton.Config.Style.NORMAL
                )
            } else {
                null
            }
        )
    )
    dialog.presentOn(this)
    return dialog
}

fun WViewController.executeWithLowPriority(block: () -> Unit) {
    Handler(Looper.getMainLooper()).postDelayed({
        Looper.myQueue().addIdleHandler(
            IdleHandler {
                block()
                false
            }
        )
    }, 100)
}
