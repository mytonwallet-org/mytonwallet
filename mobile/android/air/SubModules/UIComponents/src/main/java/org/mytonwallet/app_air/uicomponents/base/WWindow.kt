@file:Suppress("ktlint:standard:backing-property-naming")

package org.mytonwallet.app_air.uicomponents.base

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.RectF
import android.os.Build
import android.os.Bundle
import android.os.Parcelable
import android.os.SystemClock
import android.util.SparseArray
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewOutlineProvider
import android.view.WindowManager
import androidx.activity.OnBackPressedCallback
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.animation.doOnCancel
import androidx.core.animation.doOnEnd
import androidx.core.graphics.Insets
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.children
import androidx.core.view.doOnLayout
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import com.facebook.drawee.backends.pipeline.Fresco
import java.util.function.Consumer
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.TiltSensorManager
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.menu.WPopupHost
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

abstract class WWindow :
    AppCompatActivity(),
    WThemedView,
    WProtectedView {

    companion object {
        const val PROTECT_PAUSED_APP_VIEW = false
        const val WIDE_LAYOUT_MIN_WIDTH_DP = 700
        const val WIDE_LAYOUT_INNER_WIDTH_DP = 600
        const val CENTERED_WINDOW_MIN_HEIGHT_DP = 500
        const val MIN_BOTTOM_INSET_DP = 12
    }

    private val touchBlockerView: View by lazy {
        View(this).apply {
            id = View.generateViewId()
            isClickable = true
            isFocusable = true
            setOnTouchListener { _, _ -> true }
            isGone = true
            translationZ = Float.MAX_VALUE
        }
    }

    private val popupHost: WPopupHost by lazy {
        WPopupHost(this).apply {
            attachWindow(this@WWindow)
        }
    }

    // Window view is the host for all our navigation controllers and fragments
    val windowView: WView by lazy {
        object : WView(this, LayoutParams(MATCH_PARENT, MATCH_PARENT)) {
            override fun dispatchSaveInstanceState(container: SparseArray<Parcelable>) {
                // Our navigation stack is rebuilt manually in onCreate, so restoring descendant
                // state by transient runtime IDs can bind saved state to the wrong view class.
                dispatchFreezeSelfOnly(container)
            }

            override fun dispatchRestoreInstanceState(container: SparseArray<Parcelable>) {
                dispatchThawSelfOnly(container)
            }

            override fun onViewAdded(view: View?) {
                super.onViewAdded(view)
                restackMinimizedBrowser()
                bringChildToFront(popupHost)
            }
        }.apply {
            addView(touchBlockerView, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            addView(popupHost, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            fitsSystemWindows = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                requestedFrameRate = View.REQUESTED_FRAME_RATE_CATEGORY_HIGH
            }
        }
    }

    var lastInputAt = 0L
        private set

    override fun dispatchTouchEvent(event: MotionEvent?): Boolean {
        lastInputAt = SystemClock.elapsedRealtime()
        if (event != null && PopupHelpers.dispatchDragSelectionTouch(event)) return true
        return super.dispatchTouchEvent(event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        lastInputAt = SystemClock.elapsedRealtime()
        return super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        lastInputAt = SystemClock.elapsedRealtime()
        return super.dispatchGenericMotionEvent(event)
    }

    abstract fun getKeyNavigationController(): WNavigationController

    private var minimizedBrowserPresenter: MinimizedBrowserPresenter? = null

    // Hosts one minimized nav above every presented nav, resting on the top screen's bottom chrome.
    val minimizedBrowser: MinimizedBrowserPresenter
        get() = minimizedBrowserPresenter ?: MinimizedBrowserPresenter(
            object : MinimizedBrowserPresenter.Host {
                override val container get() = windowView
                override val availableHeight get() = windowView.height
                override val bottomInset
                    get() = minimizedBrowserAnchor?.let {
                        it.minimizedBrowserBottomInset
                            ?: it.navigationController?.viewControllers?.firstOrNull()
                                ?.minimizedBrowserBottomInset
                    } ?: (systemBars?.bottom ?: 0)
                override val horizontalSpan
                    get() = minimizedBrowserAnchor?.let {
                        it.minimizedBrowserSpan
                            ?: it.navigationController?.viewControllers?.firstOrNull()
                                ?.minimizedBrowserSpan
                    } ?: (0 until windowView.width)
                override val animationsEnabled
                    get() = WGlobalStorage.getAreAnimationsActive() && !isConfiguring
                override fun canMinimize(nav: WNavigationController) =
                    navigationControllers.size > 1 && navigationControllers.last() === nav

                override fun maximizedFrame(nav: WNavigationController, minimizedHeight: Int) =
                    if (nav.isCenteredWindow) {
                        val frame = centeredWindowFrame(nav, minimizedHeight)
                        RectF(
                            frame.x.toFloat(),
                            frame.y.toFloat(),
                            (frame.x + frame.width).toFloat(),
                            (frame.y + frame.height).toFloat()
                        )
                    } else {
                        RectF(0f, 0f, windowView.width.toFloat(), windowView.height.toFloat())
                    }

                override fun detach(nav: WNavigationController) = detachLastNav()
                override fun attach(nav: WNavigationController, animated: Boolean) =
                    attachNavigationController(nav, animated)

                override fun destroy(nav: WNavigationController) {
                    nav.willBeDismissed()
                    windowView.removeView(nav)
                    nav.onDestroy()
                }

                override fun render() {
                    notifyInsetsUpdated()
                    relayoutCenteredWindows()
                }
            }
        ).also { minimizedBrowserPresenter = it }

    val minimizedBrowserHeight: Float
        get() = minimizedBrowserPresenter?.height ?: 0f

    val hasMinimizedBrowser: Boolean
        get() = minimizedBrowserPresenter?.hasNavigation == true

    // Index of the lowest nav presented above the minimized browser, or -1. Every nav from it up
    // stays above the minimized browser.
    private val minimizedBrowserCoverIndex: Int
        get() = navigationControllers.indexOfFirst {
            it.viewControllers.firstOrNull()?.coversMinimizedBrowser == true
        }

    // Top screen the minimized browser rests on: below any covering nav, dismissing navs skipped.
    val minimizedBrowserAnchor: WViewController?
        get() {
            val coverIndex = minimizedBrowserCoverIndex
            val candidates = if (coverIndex < 0) {
                navigationControllers
            } else {
                navigationControllers.take(coverIndex)
            }
            return candidates.lastOrNull { !it.isDismissed }?.viewControllers?.lastOrNull()
        }

    private fun restackMinimizedBrowser() {
        val presenter = minimizedBrowserPresenter ?: return
        presenter.bringToFront()
        val coverIndex = minimizedBrowserCoverIndex
        if (coverIndex < 0) return
        for (i in coverIndex until navigationControllers.size) {
            navigationControllerOverlays.getOrNull(i)
                ?.takeIf { it.parent === windowView }?.bringToFront()
            navigationControllers[i].takeIf { it.parent === windowView }?.bringToFront()
        }
    }

    private fun relayoutCenteredWindows() {
        navigationControllers.forEach(::relayoutCenteredWindow)
    }

    // Re-centres one presented centered window to its content's current height. Leaves it to the present and
    // dismiss animators while a nav animates, and a dismissed window where it is.
    fun relayoutCenteredWindow(nav: WNavigationController) {
        if (navAnimation != NavAnimation.NONE) return
        if (!nav.isCenteredWindow || nav.isDismissed || nav.parent !== windowView) return
        val lp = nav.layoutParams ?: return
        val frame = centeredWindowFrame(nav)
        if (lp.width != frame.width || lp.height != frame.height) {
            applyCenteredWindowLayout(nav)
        }
        nav.y = frame.y.toFloat()
    }

    // Bottom inset a nav reserves so its content stays above the minimized nav.
    fun minimizedBrowserInset(navigationController: WNavigationController): Int {
        val presenter = minimizedBrowserPresenter ?: return 0
        val coverIndex = minimizedBrowserCoverIndex
        val isCovering =
            coverIndex >= 0 && navigationControllers.indexOf(navigationController) >= coverIndex
        if (presenter.hosts(navigationController) ||
            isCovering ||
            navigationController.isCenteredWindow ||
            navigationController.tabBarController != null ||
            navigationController.viewControllers.lastOrNull()?.minimizedBrowserBottomInset != null
        ) {
            return 0
        }
        return (presenter.occupiedHeight - navigationController.floatingSheetBottomGap)
            .coerceAtLeast(0)
    }

    fun navigationStackChanged() {
        minimizedBrowserPresenter?.stackChanged()
    }

    // Array of fragment stacks (navigation controllers), that are being shown right now.
    var navigationControllers = ArrayList<WNavigationController>()
        private set
    private var navigationControllerOverlays = ArrayList<WBaseView?>()

    var systemBars: Insets? = null
        private set
    var imeInsets: Insets? = null
    var isPaused = false
        set(value) {
            field = value
            setAppFocusedState()
        }

    // The minimized browser follows nav animations.
    private var activeAnimator: ValueAnimator? = null
        set(value) {
            field = value
            if (value != null) minimizedBrowserPresenter?.follow(value)
        }

    // The ExpandFrom transition [activeAnimator] is currently presenting, so a dismiss that lands
    // mid-flight can turn it around instead of snapping.
    private var presentingExpandTransition: ExpandFromTransition? = null

    // The animation each nav was presented with, so dismiss can mirror it (only animations that
    // have a mirror are kept). Entries leave with their nav.
    private val presentAnimations = HashMap<WNavigationController, PresentAnimation>()

    // The origin view of an ExpandFrom present stays hidden for as long as the sheet is up.
    private fun forgetNav(navigationController: WNavigationController?) {
        val animation = presentAnimations.remove(navigationController ?: return)
        (animation as? PresentAnimation.ExpandFrom)?.originView?.alpha = 1f
        updateWindowClipping(except = navigationController)
    }

    // A nav is clipped to its own bounds only while the window clips its children. A floating
    // bottom sheet dragged down must keep drawing below the nav's resting bottom edge, so the
    // window stops clipping for as long as one is up.
    private fun updateWindowClipping(except: WNavigationController? = null) {
        windowView.clipChildren =
            navigationControllers.none { it !== except && it.floatingSheetInset > 0 }
    }

    // Y a bottom sheet rests at once presented (sheets taller than the safe area stop 20dp below
    // the top inset).
    private fun bottomSheetRestingY(navigationController: WNavigationController): Int =
        windowView.bottom - navigationController.floatingSheetBottomGap - min(
            navigationController.height,
            windowView.height - (systemBars?.top ?: 0) - 20.dp
        )

    // One-shot callbacks run when the next present() finishes, its animation included.
    private val pendingPresentCompletions = ArrayList<() -> Unit>()

    fun doOnNextPresentCompleted(action: () -> Unit) {
        pendingPresentCompletions.add(action)
    }

    fun removeOnNextPresentCompleted(action: () -> Unit) {
        pendingPresentCompletions.remove(action)
    }

    private fun notifyPresentCompleted() {
        if (pendingPresentCompletions.isEmpty()) return
        val actions = ArrayList(pendingPresentCompletions)
        pendingPresentCompletions.clear()
        actions.forEach { it() }
    }

    var isWideLayout: Boolean = false
        protected set

    fun calcWideLayout(): Boolean {
        val widthPx = windowView.width.takeIf { it > 0 }
            ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                windowManager.currentWindowMetrics.bounds.width()
            } else {
                @Suppress("DEPRECATION")
                resources.displayMetrics.widthPixels
            }
        val widthDp = widthPx / resources.displayMetrics.density
        return widthDp > WIDE_LAYOUT_MIN_WIDTH_DP
    }

    var isConfiguring: Boolean = false
        protected set

    // Centered floating-window frame on wide layout (BottomSheet / PreferredFullScreen on tablet):
    // width = min(85% of width, WIDE_LAYOUT_MIN_WIDTH_DP), height = min(80% of height, safe height),
    // centered within the safe area so it stays below the status bar and above the bottom system bar.
    data class WindowFrame(val x: Int, val y: Int, val width: Int, val height: Int)

    // Ignores the minimized browser, so it changes only with the window size.
    val centeredWindowHeight: Int
        get() = centeredWindowFrame(minimizedBrowserHeight = 0).height

    private fun centeredWindowFrame(
        navigationController: WNavigationController? = null,
        minimizedBrowserHeight: Int = minimizedBrowserPresenter?.occupiedHeight ?: 0
    ): WindowFrame {
        val w = windowView.width
        val h = windowView.height
        val topInset = systemBars?.top ?: 0
        val bottomInset = max(systemBars?.bottom ?: 0, minimizedBrowserHeight)
        val safeHeight = (h - topInset - bottomInset).coerceAtLeast(0)
        val defaultWidth = min((w * 0.85f).roundToInt(), WIDE_LAYOUT_MIN_WIDTH_DP.dp)
        val width = (navigationController?.centeredWindowWidth ?: defaultWidth).coerceAtMost(w)
        val maxHeight = min((h * 0.8f).roundToInt(), safeHeight)
        val height =
            navigationController?.centeredWindowHeight(width)?.coerceAtMost(maxHeight) ?: maxHeight
        return WindowFrame(
            x = ((w - width) / 2).coerceAtLeast(0),
            y = (topInset + (safeHeight - height) / 2).coerceAtLeast(topInset),
            width = width,
            height = height
        )
    }

    // Apply the resting (non-animated) layout for a centered window: size, x, rounded corners.
    // Y is driven by the present/dismiss animators (so it can slide), so it's set by the caller.
    private fun applyCenteredWindowLayout(navigationController: WNavigationController) {
        val frame = centeredWindowFrame(navigationController)
        navigationController.updateLayoutParams {
            width = frame.width
            height = frame.height
        }
        navigationController.x = frame.x.toFloat()
        navigationController.clipToOutline = true
        navigationController.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: android.graphics.Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, ViewConstants.BLOCK_RADIUS.dp)
            }
        }
    }

    // Re-apply the resting presentation layout of every PRESENTED nav after a layout (rotation /
    // wide<->narrow) change, so a bottom sheet becomes a centered window on tablet (and back), a
    // PreferredFullScreen toggles between full screen and centered window, dim overlays appear /
    // disappear, and the screen behind is mounted/detached to match the new style.
    fun reapplyPresentedNavsLayout() {
        updateWindowClipping()
        for (i in 1 until navigationControllers.size) {
            val nav = navigationControllers[i]
            nav.scaleX = 1f
            nav.scaleY = 1f
            nav.alpha = 1f
            val needsDim = nav.isBottomSheet || nav.isCenteredWindow

            // Dim overlay: ensure presence matches the new style.
            var overlay = navigationControllerOverlays.getOrNull(i)
            if (needsDim && overlay == null) {
                overlay = WBaseView(this).apply {
                    setBackgroundColor(Color.BLACK.colorWithAlpha(76))
                    alpha = 1f
                }
                // Insert directly beneath this nav.
                val navIndexInWindow = windowView.indexOfChild(nav).coerceAtLeast(0)
                windowView.addView(overlay, navIndexInWindow)
                navigationControllerOverlays[i] = overlay
            } else if (!needsDim && overlay != null) {
                windowView.removeView(overlay)
                navigationControllerOverlays[i] = null
                overlay = null
            }
            // Only the topmost overlay dismisses on tap.
            overlay?.setOnClickListener(
                if (i == navigationControllers.size - 1) {
                    { dismissLastNav() }
                } else {
                    null
                }
            )

            // Frame.
            if (nav.isCenteredWindow) {
                nav.clearBottomSheetBehaviour()
                applyCenteredWindowLayout(nav)
                nav.y = centeredWindowFrame(nav).y.toFloat()
                nav.insetsUpdated()
            } else if (nav.isBottomSheet) {
                nav.clipToOutline = false
                nav.outlineProvider = ViewOutlineProvider.BACKGROUND
                nav.clearBottomSheetBehaviour()
                nav.x = 0f
                nav.translationX = 0f
                nav.updateLayoutParams {
                    width = MATCH_PARENT
                    height = MATCH_PARENT
                }
                nav.insetsUpdated()
                nav.post { nav.applyBottomSheetLayout() }
            } else {
                nav.clipToOutline = false
                nav.outlineProvider = ViewOutlineProvider.BACKGROUND
                nav.clearBottomSheetBehaviour()
                nav.x = 0f
                nav.updateLayoutParams {
                    width = MATCH_PARENT
                    height = MATCH_PARENT
                }
                nav.y = 0f
                nav.insetsUpdated()
            }

            // The screen behind must be detached when this nav fully covers it, mounted otherwise.
            val prev = navigationControllers.getOrNull(i - 1)
            if (prev != null) {
                if (nav.overFullScreen) {
                    if (prev.parent != null) {
                        prev.viewWillDisappear()
                        prev.visibility = View.GONE
                        windowView.removeView(prev)
                    }
                } else {
                    if (prev.parent == null) {
                        windowView.addView(prev, 0)
                        prev.viewWillAppear()
                    }
                    prev.visibility = View.VISIBLE
                }
            }
        }
        minimizedBrowserPresenter?.containerResized()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        setContentView(windowView)
        windowView.setFilterTouchesWhenObscured(true)

        if (!WGlobalStorage.isInitialized) {
            restartApp()
            return
        }

        if (savedInstanceState == null) {
            replace(getKeyNavigationController(), true)
        } else {
            // TODO:: Restore state??
            replace(getKeyNavigationController(), true)
        }

        // Handle back press
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    if (PopupHelpers.onBackPressed()) return
                    topViewController?.topActiveDialog?.let { dialog ->
                        dialog.dismiss()
                        return
                    }
                    navigationControllers.lastOrNull()?.onBackPressed()
                }
            }
        )

        // Set padding for navigation controllers
        ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { v, insets ->
            // Hidden bars still count, so hiding the status bar moves nothing underneath
            val bars = Insets.max(
                insets.getInsetsIgnoringVisibility(WindowInsetsCompat.Type.systemBars()),
                insets.getInsets(WindowInsetsCompat.Type.displayCutout())
            )
            systemBars = Insets.of(
                bars.left,
                bars.top,
                bars.right,
                max(bars.bottom, MIN_BOTTOM_INSET_DP.dp)
            )
            imeInsets = insets.getInsets(WindowInsetsCompat.Type.ime())
            notifyInsetsUpdated()
            WindowInsetsCompat.CONSUMED
        }

        updateTheme()
        updateLayoutDirection()
    }

    protected fun notifyInsetsUpdated() {
        for (navigationController in navigationControllers) {
            navigationController.insetsUpdated()
        }
        minimizedBrowserPresenter?.relayout()
    }

    override fun onStart() {
        super.onStart()
        startScreenRecordListener()
    }

    override fun onStop() {
        super.onStop()
        stopScreenRecordListener()
        Logger.forceSynchronize()
    }

    public override fun onPause() {
        if (PROTECT_PAUSED_APP_VIEW) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        TiltSensorManager.onAppPause()
        super.onPause()
        isPaused = true
        WalletCore.notifyEvent(WalletEvent.AppBackground)
    }

    public override fun onResume() {
        super.onResume()
        if (PROTECT_PAUSED_APP_VIEW) window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        TiltSensorManager.onAppResume()
        if (isPaused) {
            isPaused = false
            navigationControllers.lastOrNull()?.viewWillAppear()
            navigationControllers.lastOrNull()?.viewDidAppear()
            WViewController.checkInactivityOfAll()
            WalletCore.notifyEvent(WalletEvent.AppForeground)
        }
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)

        if (level >= TRIM_MEMORY_BACKGROUND) {
            Fresco.getImagePipeline().clearMemoryCaches()
        }
    }

    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        navigationControllers.forEach {
            it.updateTheme()
        }
        minimizedBrowserPresenter?.updateTheme()
        popupHost.updateTheme()

        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!darkModeChanged) return
        _isDarkThemeApplied = ThemeManager.isDark
        updateStatusBarColors()
        updateBottomBarColors()
    }

    override fun attachBaseContext(newBase: Context?) {
        val newOverride = Configuration(newBase?.resources?.configuration)
        newOverride.fontScale = 1.0f
        applyOverrideConfiguration(newOverride)

        super.attachBaseContext(newBase)
    }

    override fun updateProtectedView() {
        fun updateProtectedViewForChildren(parentView: ViewGroup) {
            for (child in parentView.children) {
                if (child is WProtectedView) child.updateProtectedView()
                if (child is ViewGroup) updateProtectedViewForChildren(child)
                if (child is WSegmentedController) {
                    child.items.forEach {
                        updateProtectedViewForChildren(it.viewController.view)
                    }
                }
            }
        }
        updateProtectedViewForChildren(windowView)
    }

    var forceStatusBarLight: Boolean? = null
        set(value) {
            field = value
            updateStatusBarColors()
        }

    var forceBottomBarLight: Boolean? = null
        set(value) {
            field = value
            updateBottomBarColors()
        }

    private fun updateStatusBarColors() {
        WindowInsetsControllerCompat(window, window.decorView).isAppearanceLightStatusBars =
            !(forceStatusBarLight ?: ThemeManager.isDark)
    }

    private fun updateBottomBarColors() {
        WindowInsetsControllerCompat(window, window.decorView).isAppearanceLightNavigationBars =
            !(forceBottomBarLight ?: ThemeManager.isDark)
    }

    fun updateLayoutDirection() {
        windowView.layoutDirection =
            if (LocaleController.isRTL) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
    }

    protected fun setAppFocusedState() {
        if (WalletCore.isBridgeReady) {
            WalletCore.call(ApiMethod.Other.SetIsAppFocused(!isPaused), callback = { _, _ -> })
        }
    }

    // Navigation Methods //////////////////////////////////////////////////////////////////////////
    val activeOverlay: WBaseView?
        get() {
            return navigationControllerOverlays.lastOrNull()
        }

    enum class NavAnimation {
        NONE,
        PRESENT_WAITING_FOR_LAYOUT,
        PRESENTING,
        DISMISSING
    }

    var navAnimation: NavAnimation = NavAnimation.NONE
        private set(value) {
            field = value
            if (value == NavAnimation.NONE) unblockTouches() else blockTouches()
        }
    val isAnimating: Boolean
        get() = navAnimation != NavAnimation.NONE

    val topViewController: WViewController?
        get() {
            return navigationControllers.lastOrNull()?.viewControllers?.lastOrNull()
        }

    val topNavigationController: WNavigationController?
        get() {
            return navigationControllers.lastOrNull()
        }

    // Called to replace all the showing fragment stacks (navigation controllers) with a clean new one!
    fun replace(
        navigationController: WNavigationController,
        animated: Boolean,
        onCompletion: (() -> Unit)? = null
    ) {
        Logger.d(
            Logger.LogTag.SCREEN,
            "replaceNav: rootVC=${navigationController.viewControllers.firstOrNull()?.TAG} navHash=${navigationController.hashCode()}"
        )
        window.decorView.setBackgroundColor(WColor.Background.color)
        val navigationControllersExist = navigationControllers.isNotEmpty()
        detachAllNavigationControllers(animated = animated, onCompletion = {
            present(navigationController, animated = false)
            if (navigationControllersExist) {
                windowView.fadeIn(onCompletion = {
                    window.decorView.background = null
                })
            } else {
                window.decorView.background = null
            }
            onCompletion?.invoke()
        })
    }

    var pendingPresentationNav: WNavigationController? = null
        private set

    fun presentOnWalletReady(navigationController: WNavigationController): Boolean {
        if (WalletContextManager.delegate?.get()?.isWalletReady() != true ||
            WalletContextManager.delegate?.get()?.isAppUnlocked() != true
        ) {
            // Should not present anything over lock screen
            pendingPresentationNav = navigationController
            return false
        }
        present(navigationController, animated = true)
        return true
    }

    private var pendingTasks: MutableList<() -> Unit>? = null
    fun doOnWalletReady(task: () -> Unit) {
        if (WalletContextManager.delegate?.get()?.isWalletReady() != true ||
            WalletContextManager.delegate?.get()?.isAppUnlocked() != true
        ) {
            if (pendingTasks == null) pendingTasks = mutableListOf()
            pendingTasks?.add(task)
            return
        }
        task()
    }

    // Drops the screen waiting for unlock without showing it; returns whether it was the one waiting
    fun discardPendingPresentationNav(navigationController: WNavigationController): Boolean {
        if (pendingPresentationNav !== navigationController) return false
        pendingPresentationNav = null
        navigationController.onDestroy()
        return true
    }

    fun presentPendingPresentationNav(): Boolean {
        val pendingPresentationNav = pendingPresentationNav ?: return false
        if (presentOnWalletReady(pendingPresentationNav)) {
            this.pendingPresentationNav = null
            return true
        }
        return false
    }

    fun doPendingTasks() {
        if (WalletContextManager.delegate?.get()?.isWalletReady() != true ||
            WalletContextManager.delegate?.get()?.isAppUnlocked() != true
        ) {
            return
        }
        pendingTasks?.forEach {
            it()
        }
        pendingTasks = null
    }

    sealed class PresentAnimation {
        object Default : PresentAnimation()
        object ScaleIn : PresentAnimation()

        /**
         * Grows a bottom sheet out of [originView]: the sheet starts as a copy of the view (same
         * frame, corner radius and look), then expands into its resting frame; dismiss plays it
         * in reverse. Falls back to DEFAULT when the nav is not presented as a bottom sheet
         * (tablet centered window, short wide window) or the view is not on screen.
         *
         * [cornerRadius] defaults to half the view's shorter side (circle / pill). [fillColor] is
         * what the growing shape is painted with while it is larger than the view's snapshot;
         * it defaults to the snapshot's dominant color.
         */
        class ExpandFrom(
            val originView: View,
            val cornerRadius: Float? = null,
            val fillColor: Int? = null
        ) : PresentAnimation()
    }

    // Called to present a new stack on top of previous ones
    fun present(
        navigationController: WNavigationController,
        presentAnimation: PresentAnimation = PresentAnimation.Default,
        animated: Boolean = true,
        onCompletion: (() -> Unit)? = null
    ) {
        if (navAnimation == NavAnimation.PRESENT_WAITING_FOR_LAYOUT) {
            windowView.doOnLayout {
                if (navAnimation == NavAnimation.PRESENT_WAITING_FOR_LAYOUT) {
                    windowView.post {
                        present(
                            navigationController,
                            presentAnimation,
                            animated,
                            onCompletion
                        )
                    }
                } else {
                    present(
                        navigationController,
                        presentAnimation,
                        animated,
                        onCompletion
                    )
                }
            }
            return
        }
        if (navAnimation != NavAnimation.NONE) activeAnimator?.end()
        Logger.d(
            Logger.LogTag.SCREEN,
            "presentNav: rootVC=${navigationController.viewControllers.firstOrNull()?.TAG} navHash=${navigationController.hashCode()}"
        )
        PopupHelpers.dismissAllPopups()
        // A bottom sheet and a tablet centered window both dim the screens behind them.
        val hasDimOverlay =
            navigationController.isBottomSheet || navigationController.isCenteredWindow
        // Overlay for previous views
        val overlayView: WBaseView?
        if (hasDimOverlay) {
            overlayView = WBaseView(this)
            overlayView.setBackgroundColor(Color.BLACK.colorWithAlpha(76))
            overlayView.setOnClickListener {}
            overlayView.alpha = 0f
            windowView.addView(overlayView)
        } else {
            overlayView = null
        }
        navigationControllerOverlays.add(overlayView)

        // Add new navigation controller to window
        navigationControllers.add(navigationController)
        navigationStackChanged()
        navigationController.viewWillAppear()
        windowView.addView(
            navigationController,
            ViewGroup.LayoutParams(
                if (navigationController.isBottomSheet) {
                    navigationController.floatingSheetWidth(windowView.width)
                } else {
                    MATCH_PARENT
                },
                if (navigationController.isBottomSheet) 0 else MATCH_PARENT
            )
        )
        navigationController.x = navigationController.floatingSheetInset.toFloat()
        updateWindowClipping()
        navigationController.alpha = 0f
        navigationController.y = windowView.bottom.toFloat()
        val wasAnimating = isAnimating
        navAnimation = NavAnimation.PRESENT_WAITING_FOR_LAYOUT
        windowView.doOnLayout {
            navAnimation = NavAnimation.PRESENTING
            if (navigationController.isCenteredWindow) {
                applyCenteredWindowLayout(navigationController)
            }
            val shouldPresentFullScreen = !navigationController.isBottomSheet ||
                navigationController.viewControllers.firstOrNull()?.isExpandable == true
            val finalY =
                if (navigationController.isCenteredWindow) {
                    centeredWindowFrame(navigationController).y
                } else if (shouldPresentFullScreen) {
                    0
                } else {
                    bottomSheetRestingY(navigationController)
                }
            if (!animated || !WGlobalStorage.getAreAnimationsActive() || wasAnimating) {
                overlayView?.alpha = 1f
                navigationController.alpha = 1f
                navigationController.y = finalY.toFloat()
                navigationController.viewDidAppear()
                removePrevNavigationControllersFromHierarchy()
                navAnimation = NavAnimation.NONE
                onCompletion?.invoke()
                notifyPresentCompleted()
                return@doOnLayout
            }
            activeAnimator?.cancel()
            // The transition captures the nav's resting frame, so the nav must already be there.
            val expandTransition = (presentAnimation as? PresentAnimation.ExpandFrom)
                ?.takeIf { navigationController.isBottomSheet }
                ?.let {
                    navigationController.y = finalY.toFloat()
                    ExpandFromTransition.create(this, navigationController, it)
                }
            val effectiveAnimation =
                if (presentAnimation is PresentAnimation.ExpandFrom && expandTransition == null) {
                    PresentAnimation.Default
                } else {
                    presentAnimation
                }
            when {
                effectiveAnimation is PresentAnimation.ExpandFrom && expandTransition != null -> {
                    navigationController.alpha = 1f
                    presentAnimations[navigationController] = effectiveAnimation
                    // Tapping outside already dismisses while the sheet is still growing.
                    overlayView?.setOnClickListener {
                        dismissLastNav()
                    }
                    presentingExpandTransition = expandTransition
                    // Only the incoming nav is shielded, so the tap can reach the dim overlay.
                    unblockTouches()
                    navigationController.blockTouches()
                    activeAnimator = expandTransition.run(
                        from = 0f,
                        to = 1f,
                        onFrame = { expansion ->
                            overlayView?.alpha = expansion.coerceIn(0f, 1f)
                        },
                        onCancel = {
                            presentingExpandTransition = null
                            navigationController.unblockTouches()
                            if (!navigationController.isDismissed) {
                                navigationController.viewDidAppear()
                            }
                            activeAnimator = null
                            navAnimation = NavAnimation.NONE
                        },
                        onEnd = {
                            presentingExpandTransition = null
                            navigationController.unblockTouches()
                            overlayView?.alpha = 1f
                            navigationController.viewDidAppear()
                            removePrevNavigationControllersFromHierarchy()
                            activeAnimator = null
                            navAnimation = NavAnimation.NONE
                            onCompletion?.invoke()
                            notifyPresentCompleted()
                        }
                    )
                }

                effectiveAnimation is PresentAnimation.Default -> {
                    activeAnimator = ValueAnimator.ofInt(
                        finalY + 48.dp,
                        finalY
                    )
                        .apply {
                            duration = AnimationConstants.NAV_PRESENT
                            interpolator = WInterpolator.emphasizedDecelerate

                            addUpdateListener { updatedAnimation ->
                                overlayView?.alpha = updatedAnimation.animatedFraction
                                val updatedValue = updatedAnimation.animatedValue as Int
                                navigationController.y = updatedValue.toFloat()
                                navigationController.alpha = animatedFraction
                            }
                            doOnCancel {
                                removeAllListeners()
                                WGlobalStorage.decDoNotSynchronize()
                                if (!navigationController.isDismissed) {
                                    navigationController.viewDidAppear()
                                }
                                activeAnimator = null
                                navAnimation = NavAnimation.NONE
                            }
                            doOnEnd {
                                WGlobalStorage.decDoNotSynchronize()
                                navigationController.viewDidAppear()
                                overlayView?.setOnClickListener {
                                    dismissLastNav()
                                }
                                removePrevNavigationControllersFromHierarchy()
                                activeAnimator = null
                                navAnimation = NavAnimation.NONE
                                onCompletion?.invoke()
                                notifyPresentCompleted()
                            }

                            WGlobalStorage.incDoNotSynchronize()
                            start()
                        }
                }

                effectiveAnimation is PresentAnimation.ScaleIn -> {
                    navigationController.y = finalY.toFloat()
                    activeAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                        duration = AnimationConstants.QUICK_ANIMATION

                        addUpdateListener {
                            val fraction = animatedFraction
                            navigationController.let {
                                it.alpha = fraction
                                val scale = 1.05f - 0.05f * fraction
                                it.scaleX = scale
                                it.scaleY = scale
                            }
                        }
                        doOnCancel {
                            removeAllListeners()
                            WGlobalStorage.decDoNotSynchronize()
                            if (!navigationController.isDismissed) {
                                navigationController.viewDidAppear()
                            }
                            activeAnimator = null
                            navAnimation = NavAnimation.NONE
                        }
                        doOnEnd {
                            overlayView?.alpha = 1f
                            WGlobalStorage.decDoNotSynchronize()
                            navigationController.viewDidAppear()
                            overlayView?.setOnClickListener {
                                dismissLastNav()
                            }
                            removePrevNavigationControllersFromHierarchy()
                            activeAnimator = null
                            navAnimation = NavAnimation.NONE
                            onCompletion?.invoke()
                            notifyPresentCompleted()
                        }

                        WGlobalStorage.incDoNotSynchronize()
                        start()
                    }
                }
            }
        }
    }

    // Dismiss a specific nav from the memory and hierarchy
    // [animated] only applies to the topmost nav; a nav underneath is removed outright.
    fun dismissNav(navigationController: WNavigationController?, animated: Boolean = true) {
        navigationControllers.indexOf(navigationController).let { it ->
            if (it == -1) return@let
            dismissNav(it, animated)
        }
    }

    fun dismissNav(index: Int, animated: Boolean = true) {
        if (index == navigationControllers.size - 1) {
            dismissLastNav(animated = animated)
            return
        }
        val overlay = navigationControllerOverlays[index]
        val navigationController = navigationControllers[index]
        navigationController.apply {
            willBeDismissed()
            onDestroy()
        }
        forgetNav(navigationController)
        navigationControllers.removeAt(index)
        navigationControllerOverlays.removeAt(index)
        windowView.removeView(overlay)
        windowView.removeView(navigationController)
        navigationStackChanged()
    }

    enum class DismissAnimation {
        DEFAULT,
        SCALE_OUT
    }

    fun dismissLastNav(
        animation: DismissAnimation = DismissAnimation.DEFAULT,
        animated: Boolean = true,
        onCompletion: (() -> Unit)? = null
    ): Boolean {
        if (navAnimation == NavAnimation.PRESENT_WAITING_FOR_LAYOUT) {
            windowView.doOnLayout {
                if (navAnimation == NavAnimation.PRESENT_WAITING_FOR_LAYOUT) {
                    windowView.post { dismissLastNav(animation, animated, onCompletion) }
                } else {
                    dismissLastNav(animation, animated, onCompletion)
                }
            }
            return true
        }
        if (navigationControllers.size < 2) {
            moveTaskToBack(true)
            return false
        }
        val navigationController = navigationControllers.lastOrNull()
        if (navigationController?.isDismissed == true) return true
        navigationController?.willBeDismissed()
        navigationStackChanged()
        val prevNavigationController =
            navigationControllers.getOrNull(navigationControllers.size - 2)
        val skipPrevNavAnimation =
            navAnimation == NavAnimation.PRESENTING && prevNavigationController?.parent != null
        // An ExpandFrom present caught mid-flight is turned around from where it is.
        val interruptedTransition = presentingExpandTransition?.takeIf {
            navAnimation == NavAnimation.PRESENTING &&
                animation == DismissAnimation.DEFAULT &&
                animated && WGlobalStorage.getAreAnimationsActive()
        }
        when (navAnimation) {
            NavAnimation.PRESENTING -> {
                if (interruptedTransition == null) activeAnimator?.cancel()
            }

            NavAnimation.DISMISSING -> {
                activeAnimator?.end()
            }

            NavAnimation.NONE -> {}

            NavAnimation.PRESENT_WAITING_FOR_LAYOUT -> {}
        }
        addPrevNavigationControllersToHierarchy()
        val lastOverlay = navigationControllerOverlays.lastOrNull()
        val startOverlayAlpha = lastOverlay?.alpha ?: 0f

        fun animationEnded() {
            // A replaced stack has already torn this nav down.
            if (navigationController !in navigationControllers) {
                activeAnimator = null
                navAnimation = NavAnimation.NONE
                return
            }
            navigationController?.visibility = View.GONE
            navigationController?.onDestroy()
            forgetNav(navigationController)
            navigationControllers.removeAt(navigationControllers.lastIndex)
            if (navigationControllerOverlays.isNotEmpty()) {
                navigationControllerOverlays.removeAt(navigationControllerOverlays.lastIndex)
            }
            windowView.removeView(lastOverlay)
            windowView.removeView(navigationController)
            activeAnimator = null
            navAnimation = NavAnimation.NONE
            onCompletion?.invoke()
            val nextNavigationController =
                navigationControllers.lastOrNull()?.takeIf { !it.isDismissed }
            if (navigationController?.overFullScreen == true) {
                nextNavigationController?.viewDidAppear()
            } else {
                nextNavigationController?.viewDidEnterForeground()
            }
        }

        if (!animated || !WGlobalStorage.getAreAnimationsActive()) {
            lastOverlay?.alpha = 0f
            navigationController?.y = windowView.bottom.toFloat()
            animationEnded()
            return true
        }
        val wasPresenting = navAnimation == NavAnimation.PRESENTING
        navAnimation = NavAnimation.DISMISSING
        val startAlpha = navigationController?.alpha ?: 1f
        // A sheet that grew out of a button springs back into it, unless it was dragged away from
        // its resting frame (the behavior moves the top VC's view inside the nav), is still
        // mid-presentation, or the button is gone.
        val collapseTransition =
            (presentAnimations[navigationController] as? PresentAnimation.ExpandFrom)
                ?.takeIf {
                    animation == DismissAnimation.DEFAULT && !wasPresenting &&
                        navigationController?.isBottomSheet == true &&
                        abs(
                            navigationController.y - bottomSheetRestingY(navigationController)
                        ) < 1f &&
                        (navigationController.viewControllers.lastOrNull()?.view?.top ?: 0) == 0
                }
                ?.let { transition ->
                    navigationController?.let { ExpandFromTransition.create(this, it, transition) }
                }
        // Unless the sheet springs back into it, the origin view of an ExpandFrom present fades
        // in alongside the dismiss.
        val expandOriginView =
            (presentAnimations[navigationController] as? PresentAnimation.ExpandFrom)?.originView
        val runningAnimator = activeAnimator
        when {
            interruptedTransition != null && runningAnimator != null -> {
                presentingExpandTransition = null
                activeAnimator = interruptedTransition.reverse(
                    runningAnimator,
                    onFrame = { expansion ->
                        lastOverlay?.alpha = expansion.coerceIn(0f, 1f)
                    },
                    onCancel = { animationEnded() },
                    onEnd = { animationEnded() }
                )
            }

            collapseTransition != null -> {
                activeAnimator?.cancel()
                activeAnimator = collapseTransition.run(
                    from = 1f,
                    to = 0f,
                    onFrame = { expansion ->
                        lastOverlay?.alpha = expansion.coerceIn(0f, 1f) * startOverlayAlpha
                    },
                    onCancel = { animationEnded() },
                    onEnd = { animationEnded() }
                )
            }

            animation == DismissAnimation.DEFAULT -> {
                activeAnimator?.cancel()
                expandOriginView?.fadeIn(AnimationConstants.NAV_DISMISS)
                val startY = navigationController?.y?.toInt() ?: 0
                val floating =
                    navigationController != null && navigationController.floatingSheetInset > 0
                val slide = if (floating) {
                    val sheetTop =
                        navigationController.viewControllers.lastOrNull()?.view?.top ?: 0
                    (windowView.bottom - startY - sheetTop).coerceAtLeast(48.dp)
                } else {
                    48.dp
                }
                activeAnimator = ValueAnimator.ofInt(startY, startY + slide)
                    .apply {
                        duration = AnimationConstants.NAV_DISMISS
                        interpolator = if (floating) {
                            WInterpolator.emphasizedDecelerate
                        } else {
                            WInterpolator.emphasizedAccelerate
                        }

                        addUpdateListener { updatedAnimation ->
                            val fraction = updatedAnimation.animatedFraction
                            val updatedValue = updatedAnimation.animatedValue as Int
                            lastOverlay?.alpha = (1 - fraction) * startOverlayAlpha
                            navigationController?.y = updatedValue.toFloat()
                            if (!floating) {
                                navigationController?.alpha = startAlpha * (1 - fraction)
                            }
                        }
                        addListener(object : AnimatorListenerAdapter() {
                            override fun onAnimationEnd(animation: Animator) {
                                super.onAnimationEnd(animation)
                                WGlobalStorage.decDoNotSynchronize()
                                animationEnded()
                            }
                        })

                        WGlobalStorage.incDoNotSynchronize()
                        start()
                    }
            }

            else -> {
                val prevNavigationController = navigationControllers[navigationControllers.size - 2]
                if (!skipPrevNavAnimation) {
                    prevNavigationController.scaleX = 0.95f
                    prevNavigationController.scaleY = 0.95f
                }
                lastOverlay?.alpha = 0f
                activeAnimator?.cancel()
                expandOriginView?.fadeIn(AnimationConstants.QUICK_ANIMATION)
                val layeredViews = listOfNotNull(
                    navigationController,
                    prevNavigationController.takeIf { !skipPrevNavAnimation }
                ).filter { it.layerType == View.LAYER_TYPE_NONE }
                layeredViews.forEach { it.setLayerType(View.LAYER_TYPE_HARDWARE, null) }
                activeAnimator = ValueAnimator.ofInt(0, 1).apply {
                    duration = AnimationConstants.QUICK_ANIMATION

                    addUpdateListener {
                        if (!skipPrevNavAnimation) {
                            val scale = 0.95f + 0.05f * animatedFraction
                            prevNavigationController.scaleX = scale
                            prevNavigationController.scaleY = scale
                        }
                        navigationController?.let {
                            it.alpha = startAlpha * (1 - animatedFraction)
                            it.scaleX = 1f + 0.05f * (1 - it.alpha)
                            it.scaleY = it.scaleX
                        }
                    }
                    addListener(object : AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animation: Animator) {
                            super.onAnimationEnd(animation)
                            layeredViews.forEach { it.setLayerType(View.LAYER_TYPE_NONE, null) }
                            WGlobalStorage.decDoNotSynchronize()
                            animationEnded()
                        }
                    })

                    WGlobalStorage.incDoNotSynchronize()
                    // The layers are rendered once, behind the still opaque screen, before the
                    // first animated frame.
                    if (layeredViews.isNotEmpty() &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                    ) {
                        val animator = this
                        var started = false
                        val startOnce = Runnable {
                            // Another navigation may have ended this dismiss before it started.
                            if (!started && activeAnimator === animator) {
                                started = true
                                start()
                            }
                        }
                        windowView.viewTreeObserver.registerFrameCommitCallback(startOnce)
                        // A window that draws no frame must not keep the screen from leaving.
                        windowView.postDelayed(startOnce, AnimationConstants.QUICK_ANIMATION)
                        windowView.invalidate()
                    } else {
                        windowView.post { start() }
                    }
                }
            }
        }
        return true
    }

    fun dismissToRoot(onCompletion: (() -> Unit)? = null) {
        PopupHelpers.dismissAllPopups()
        val prevNavigationControllers = ArrayList(navigationControllers)
        for (i in 1 until prevNavigationControllers.size - 1) {
            val nav = prevNavigationControllers[i]
            if (nav.parent == null) dismissNav(nav) else break
        }
        if (navigationControllers.size > 1) {
            dismissLastNav {
                dismissToRoot(onCompletion)
            }
        } else {
            onCompletion?.invoke()
        }
    }

    // Detach a navigation controller from the window, to use somewhere else!
    fun detachLastNav() {
        val overlay = navigationControllerOverlays.lastOrNull()
        addPrevNavigationControllersToHierarchy()
        windowView.removeView(navigationControllers.lastOrNull())
        forgetNav(navigationControllers.lastOrNull())
        navigationControllers.removeAt(navigationControllers.lastIndex)
        navigationControllerOverlays.removeAt(navigationControllerOverlays.lastIndex)
        if (overlay != null && overlay.alpha > 0f && WGlobalStorage.getAreAnimationsActive()) {
            overlay.setOnClickListener(null)
            overlay.isClickable = false
            overlay.animate().alpha(0f).setDuration(AnimationConstants.QUICK_ANIMATION)
                .withEndAction { windowView.removeView(overlay) }
        } else {
            windowView.removeView(overlay)
        }
        navigationControllers.lastOrNull()?.viewDidAppear()
    }

    // Attach a navigation controller to the window, to animate and present it freely!
    fun attachNavigationController(
        navigationController: WNavigationController,
        animated: Boolean = true
    ) {
        val overlayView = WBaseView(this)
        overlayView.setBackgroundColor(Color.BLACK.colorWithAlpha(76))
        overlayView.setOnClickListener {
            dismissLastNav()
        }
        overlayView.alpha = 0f
        navigationControllerOverlays.add(overlayView)
        windowView.addView(overlayView)

        navigationControllers.add(navigationController)
        if (!navigationController.overFullScreen) {
            navigationControllers[navigationControllers.size - 2].viewControllers.lastOrNull()
                ?.viewWillDisappear()
        }
        windowView.addView(
            navigationController,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                if (navigationController.overFullScreen) MATCH_PARENT else 0
            )
        )
        if (navigationController.overFullScreen) {
            navigationControllerOverlays.lastOrNull()?.let {
                it.visibility = View.GONE
                windowView.removeView(it)
            }
            removePrevNavigationControllersFromHierarchy()
        } else if (navigationController.isCenteredWindow) {
            applyCenteredWindowLayout(navigationController)
            navigationController.y =
                centeredWindowFrame(navigationController).y.toFloat()
            if (animated && WGlobalStorage.getAreAnimationsActive()) {
                overlayView.animate().alpha(1f).duration = AnimationConstants.QUICK_ANIMATION
            } else {
                overlayView.alpha = 1f
            }
        }
        navigationController.viewDidAppear()
    }

    // Remove all the navigation controllers and overlays. Make screen clean :)
    private fun detachAllNavigationControllers(animated: Boolean, onCompletion: () -> Unit) {
        fun removeNavViewsAndContinue() {
            minimizedBrowserPresenter?.dismissAll()
            for (nav in navigationControllers) {
                nav.willBeDismissed()
                windowView.removeView(nav)
                nav.onDestroy()
            }
            navigationControllerOverlays.forEach {
                windowView.removeView(it)
            }
            navigationControllers = arrayListOf()
            navigationControllerOverlays = arrayListOf()
            onCompletion()
        }
        if (animated && navigationControllers.isNotEmpty()) {
            windowView.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION, onCompletion = {
                removeNavViewsAndContinue()
            })
        } else {
            removeNavViewsAndContinue()
        }
    }

    // Called after a navigation controller presentation to remove unnecessary views from the hierarchy
    private fun removePrevNavigationControllersFromHierarchy() {
        val navigationController = navigationControllers.lastOrNull() ?: return
        if (navigationController.overFullScreen) {
            if (navigationControllers.size >= 2) {
                fun removePrevNav(i: Int) {
                    if (i < 0) return
                    navigationControllers[i].let {
                        navigationControllers[i].viewWillDisappear()
                        it.visibility = View.GONE
                        windowView.removeView(it)
                        if (!it.overFullScreen) {
                            navigationControllerOverlays[i]?.let { overlay ->
                                overlay.visibility = View.GONE
                                windowView.removeView(overlay)
                            }
                            removePrevNav(i - 1)
                        }
                    }
                }
                removePrevNav(navigationControllers.size - 2)
            }
        }
    }

    // Called before a navigation dismiss, to add necessary views to the hierarchy
    private fun addPrevNavigationControllersToHierarchy() {
        val navigationController = navigationControllers.lastOrNull()
        if (navigationController?.overFullScreen == true) {
            fun presentPrevScreen(i: Int) {
                navigationControllers[i].let {
                    val wasHidden = it.parent == null || it.visibility != View.VISIBLE
                    if (it.parent == null) windowView.addView(it, 0)
                    it.visibility = View.VISIBLE
                    if (wasHidden) it.viewWillAppear()
                    if (!it.overFullScreen) {
                        navigationControllerOverlays[i]?.let { overlay ->
                            if (overlay.parent == null) windowView.addView(overlay, 0)
                            overlay.visibility = View.VISIBLE
                        }
                        presentPrevScreen(i - 1)
                    }
                }
            }
            presentPrevScreen(navigationControllers.size - 2)
        }
    }

    fun preparePreviousNavigationControllerForDisplay() {
        if (navigationControllers.size < 2) return
        when (navAnimation) {
            NavAnimation.PRESENT_WAITING_FOR_LAYOUT -> {
                windowView.doOnLayout {
                    windowView.post { preparePreviousNavigationControllerForDisplay() }
                }
                return
            }

            NavAnimation.PRESENTING -> {
                val animator = activeAnimator
                if (animator == null) {
                    windowView.post { preparePreviousNavigationControllerForDisplay() }
                    return
                }
                animator.end()
            }

            NavAnimation.NONE,
            NavAnimation.DISMISSING -> {
            }
        }
        addPrevNavigationControllersToHierarchy()
    }

    private fun blockTouches() {
        touchBlockerView.isGone = false
    }

    private fun unblockTouches() {
        touchBlockerView.isGone = true
    }

    // Activity Results ////////////////////////////////////////////////////////////////////////////
    private var activityResultListener: ((Int, Intent?) -> Unit)? = null
    private val activityResultLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        activityResultListener?.invoke(result.resultCode, result.data)
        activityResultListener = null
    }

    fun startActivityForResult(intent: Intent, listener: (Int, Intent?) -> Unit) {
        activityResultListener?.invoke(RESULT_CANCELED, null)
        activityResultListener = listener
        activityResultLauncher.launch(intent)
    }

    // Permission Requests /////////////////////////////////////////////////////////////////////////
    private var code = 100
    private val listeners = mutableMapOf<Int, (Array<String>, IntArray) -> Unit>()

    fun requestPermissions(
        permissions: Array<String>,
        listener: ((Array<String>, IntArray) -> Unit)
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val code = this.code++
            listeners[code] = listener
            requestPermissions(permissions, code)
        } else {
            val granted = intArrayOf(PackageManager.PERMISSION_GRANTED)
            listener(permissions, granted)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        listeners.remove(requestCode)?.invoke(permissions, grantResults)
    }

    private fun restartApp() {
        startActivity(WalletContextManager.getMainActivityIntent(this))
        finish()
        return
    }

    // Screen Record ///////////////////////////////////////////////////////////////////////////////
    private fun startScreenRecordListener() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            val initialState =
                windowManager.addScreenRecordingCallback(mainExecutor, screenRecordCallback)
            screenRecordCallback.accept(initialState)
        }
    }

    private fun stopScreenRecordListener() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            windowManager.removeScreenRecordingCallback(screenRecordCallback)
        }
    }

    var isScreenRecordInProgress = false
        private set
    private val screenRecordCallback = Consumer<Int> { state ->
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            val newState = state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE &&
                !WGlobalStorage.getIsScreenRecordWarningDisabled()
            if (isScreenRecordInProgress != newState) {
                isScreenRecordInProgress = newState
                navigationControllers.forEach {
                    it.onScreenRecordStateChanged(newState)
                }
            }
        }
    }
}
