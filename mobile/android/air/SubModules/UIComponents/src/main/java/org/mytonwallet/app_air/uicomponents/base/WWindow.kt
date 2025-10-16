package org.mytonwallet.app_air.uicomponents.base

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.WindowManager
import androidx.activity.OnBackPressedCallback
import androidx.activity.enableEdgeToEdge
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
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.updateThemeForChildren
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.util.function.Consumer
import kotlin.math.min

abstract class WWindow : AppCompatActivity(), WThemedView, WProtectedView {

    companion object {
        const val PROTECT_PAUSED_APP_VIEW = false
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

    // Window view is the host for all our navigation controllers and fragments
    val windowView: WView by lazy {
        WView(
            this, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        ).apply {
            addView(touchBlockerView, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            fitsSystemWindows = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                requestedFrameRate = View.REQUESTED_FRAME_RATE_CATEGORY_HIGH
            }
        }
    }

    abstract fun getKeyNavigationController(): WNavigationController

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

    private var activeAnimator: ValueAnimator? = null

    fun isTablet(): Boolean {
        return (resources.configuration.screenLayout and
            Configuration.SCREENLAYOUT_SIZE_MASK) >= Configuration.SCREENLAYOUT_SIZE_LARGE
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (!isTablet())
            setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT)

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
                    topViewController?.let { topVC ->
                        if (topVC.activeDialog != null) {
                            topVC.activeDialog?.dismiss()
                            return
                        }
                    }
                    navigationControllers.lastOrNull()?.onBackPressed()
                }
            }
        )

        // Set padding for navigation controllers
        ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { v, insets ->
            systemBars =
                insets.getInsets(WindowInsetsCompat.Type.displayCutout() or WindowInsetsCompat.Type.systemBars())
            imeInsets = insets.getInsets(WindowInsetsCompat.Type.ime())
            for (navigationController in navigationControllers) {
                navigationController.insetsUpdated()
            }
            WindowInsetsCompat.CONSUMED
        }

        updateTheme()
        updateLayoutDirection()
    }

    override fun onStart() {
        super.onStart()
        startScreenRecordListener()
    }

    override fun onStop() {
        super.onStop()
        stopScreenRecordListener()
    }

    public override fun onPause() {
        if (PROTECT_PAUSED_APP_VIEW)
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onPause()
        isPaused = true
    }

    public override fun onResume() {
        super.onResume()
        if (PROTECT_PAUSED_APP_VIEW)
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        isPaused = false
        navigationControllers.lastOrNull()?.viewWillAppear()
    }

    override fun updateTheme() {
        forceStatusBarLight = null
        forceBottomBarLight = null
        updateStatusBarColors()
        updateBottomBarColors()

        navigationControllers.forEach {
            it.updateTheme()
            updateThemeForChildren(it)
        }
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
                if (child is WProtectedView)
                    child.updateProtectedView()
                if (child is ViewGroup)
                    updateProtectedViewForChildren(child)
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
    var isAnimating: Boolean = false
        private set(value) {
            field = value
            if (isAnimating)
                blockTouches()
            else
                unblockTouches()
        }
    val topViewController: WViewController?
        get() {
            return navigationControllers.lastOrNull()?.viewControllers?.lastOrNull()
        }

    // Called to replace all the showing fragment stacks (navigation controllers) with a clean new one!
    fun replace(
        navigationController: WNavigationController,
        animated: Boolean,
        onCompletion: (() -> Unit)? = null
    ) {
        window.decorView.setBackgroundColor(WColor.Background.color)
        navigationController.viewWillAppear()
        val navigationControllersExist = navigationControllers.isNotEmpty()
        detachAllNavigationControllers(animated = animated, onCompletion = {
            present(navigationController, animated = false)
            if (navigationControllersExist)
                windowView.fadeIn(onCompletion = {
                    window.decorView.background = null
                })
            else
                window.decorView.background = null
            onCompletion?.invoke()
        })
    }

    var pendingPresentationNav: WNavigationController? = null
        private set

    fun presentOnWalletReady(
        navigationController: WNavigationController
    ): Boolean {
        if (WalletContextManager.delegate?.isWalletReady() != true ||
            (WalletContextManager.delegate?.isAppUnlocked() != true &&
                AccountStore.activeAccount?.accountType != MAccount.AccountType.VIEW)
        ) {
            // Should not present anything over lock screen
            pendingPresentationNav = navigationController
            return false
        }
        present(navigationController, true)
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

    // Called to present a new stack on top of previous ones
    fun present(
        navigationController: WNavigationController,
        animated: Boolean = true,
        onCompletion: (() -> Unit)? = null
    ) {
        // Overlay for previous views
        val overlayView: WBaseView?
        if (navigationController.presentationConfig.isBottomSheet) {
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
        if (navigationController.presentationConfig.overFullScreen &&
            navigationControllers.size >= 2
        )
            navigationControllers[navigationControllers.size - 2].viewControllers.last()
                .viewWillDisappear()
        navigationController.viewWillAppear()
        windowView.addView(
            navigationController,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                if (navigationController.presentationConfig.isBottomSheet) 0 else MATCH_PARENT
            )
        )
        navigationController.y = windowView.bottom.toFloat()
        val wasAnimating = isAnimating
        isAnimating = true
        windowView.doOnLayout {
            val shouldPresentFullScreen = !navigationController.presentationConfig.isBottomSheet ||
                navigationController.viewControllers.firstOrNull()?.isExpandable == true
            val finalY =
                if (shouldPresentFullScreen) 0 else windowView.bottom - min(
                    navigationController.height,
                    windowView.height - (systemBars?.top ?: 0) - 20.dp
                )
            if (!animated || !WGlobalStorage.getAreAnimationsActive() || wasAnimating) {
                overlayView?.alpha = 1f
                navigationController.y = finalY.toFloat()
                navigationController.viewDidAppear()
                removePrevNavigationControllersFromHierarchy()
                isAnimating = false
                onCompletion?.invoke()
                return@doOnLayout
            }
            activeAnimator?.cancel()
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
                        navigationController.viewDidAppear()
                        activeAnimator = null
                        isAnimating = false
                    }
                    doOnEnd {
                        WGlobalStorage.decDoNotSynchronize()
                        overlayView?.setOnClickListener {
                            dismissLastNav()
                        }
                        removePrevNavigationControllersFromHierarchy()
                        activeAnimator = null
                        isAnimating = false
                        onCompletion?.invoke()
                    }

                    WGlobalStorage.incDoNotSynchronize()
                    start()
                }
        }
    }

    // Dismiss a specific nav from the memory and hierarchy
    fun dismissNav(index: Int) {
        if (index == navigationControllers.size - 1) {
            dismissLastNav()
            return
        }
        val overlay = navigationControllerOverlays[index]
        val navigationController = navigationControllers[index]
        navigationController.apply {
            willBeDismissed()
            onDestroy()
        }
        navigationControllers.removeAt(index)
        navigationControllerOverlays.removeAt(index)
        windowView.removeView(overlay)
        windowView.removeView(navigationController)
    }

    enum class DismissAnimation {
        DEFAULT,
        SCALE_IN
    }

    fun dismissLastNav(
        animation: DismissAnimation = DismissAnimation.DEFAULT,
        animated: Boolean = true,
        onCompletion: (() -> Unit)? = null
    ): Boolean {
        if (navigationControllers.size < 2) {
            moveTaskToBack(true)
            return false
        }
        val navigationController = navigationControllers.lastOrNull()
        if (navigationController?.isDismissed == true)
            return true
        navigationController?.willBeDismissed()
        addPrevNavigationControllersToHierarchy()
        val lastOverlay = navigationControllerOverlays.lastOrNull()
        val startOverlayAlpha = lastOverlay?.alpha ?: 0f

        fun animationEnded() {
            navigationController?.visibility = View.GONE
            navigationController?.onDestroy()
            navigationControllers.removeAt(navigationControllers.lastIndex)
            if (navigationControllerOverlays.isNotEmpty())
                navigationControllerOverlays.removeAt(navigationControllerOverlays.lastIndex)
            windowView.removeView(lastOverlay)
            windowView.removeView(navigationController)
            activeAnimator = null
            isAnimating = false
            onCompletion?.invoke()
            if (navigationController?.presentationConfig?.overFullScreen == true) {
                navigationControllers.lastOrNull()?.viewDidAppear()
            }
        }

        if (!animated || !WGlobalStorage.getAreAnimationsActive()) {
            lastOverlay?.alpha = 0f
            navigationController?.y = windowView.bottom.toFloat()
            animationEnded()
            return true
        }
        isAnimating = true
        val startAlpha = navigationController?.alpha ?: 1f
        when (animation) {
            DismissAnimation.DEFAULT -> {
                activeAnimator?.cancel()
                activeAnimator = ValueAnimator.ofInt(
                    navigationController?.y?.toInt() ?: 0,
                    (navigationController?.y?.toInt() ?: 0) + 48.dp
                )
                    .apply {
                        duration = AnimationConstants.NAV_DISMISS
                        interpolator = WInterpolator.emphasizedAccelerate

                        addUpdateListener { updatedAnimation ->
                            val fraction = updatedAnimation.animatedFraction
                            val updatedValue = updatedAnimation.animatedValue as Int
                            lastOverlay?.alpha = (1 - fraction) * startOverlayAlpha
                            navigationController?.y = updatedValue.toFloat()
                            navigationController?.alpha = startAlpha * (1 - fraction)
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

            DismissAnimation.SCALE_IN -> {
                val prevNavigationController = navigationControllers[navigationControllers.size - 2]
                prevNavigationController.scaleX = 1.2f
                prevNavigationController.scaleY = 1.2f
                lastOverlay?.alpha = 0f
                activeAnimator?.cancel()
                activeAnimator = ValueAnimator.ofInt(0, 1).apply {
                    duration = AnimationConstants.QUICK_ANIMATION

                    addUpdateListener {
                        val scale = 1.2f - 0.2f * animatedFraction
                        prevNavigationController.scaleX = scale
                        prevNavigationController.scaleY = scale
                        navigationController?.alpha = startAlpha * (1 - animatedFraction)
                    }
                    addListener(object : AnimatorListenerAdapter() {
                        override fun onAnimationEnd(animation: Animator) {
                            super.onAnimationEnd(animation)
                            WGlobalStorage.decDoNotSynchronize()
                            animationEnded()
                        }
                    })

                    WGlobalStorage.incDoNotSynchronize()
                    prevNavigationController.viewControllers.lastOrNull()?.view?.post {
                        start()
                    }
                }
            }
        }
        return true
    }

    // Detach a navigation controller from the window, to use somewhere else!
    fun detachLastNav() {
        val overlay = navigationControllerOverlays.lastOrNull()
        if (navigationControllers.size >= 2) {
            windowView.addView(navigationControllers[navigationControllers.size - 2], 0)
            navigationControllers[navigationControllers.size - 2].visibility = View.VISIBLE
            navigationControllers[navigationControllers.size - 2].viewWillAppear()
        }
        windowView.removeView(navigationControllers.lastOrNull())
        navigationControllers.removeAt(navigationControllers.lastIndex)
        navigationControllerOverlays.removeAt(navigationControllerOverlays.lastIndex)
        windowView.removeView(overlay)
        navigationControllers.lastOrNull()?.viewDidAppear()
    }

    // Attach a navigation controller to the window, to animate and present it freely!
    fun attachNavigationController(navigationController: WNavigationController) {
        val overlayView = WBaseView(this)
        overlayView.setBackgroundColor(Color.BLACK.colorWithAlpha(76))
        overlayView.setOnClickListener {
            dismissLastNav()
        }
        overlayView.alpha = 0f
        navigationControllerOverlays.add(overlayView)
        windowView.addView(overlayView)

        navigationControllers.add(navigationController)
        navigationControllers[navigationControllers.size - 2].viewControllers.lastOrNull()
            ?.viewWillDisappear()
        windowView.addView(
            navigationController,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                if (navigationController.presentationConfig.overFullScreen) MATCH_PARENT else 0
            )
        )
        if (navigationController.presentationConfig.overFullScreen) {
            navigationControllers[navigationControllers.size - 2].let {
                it.visibility = View.GONE
                windowView.removeView(it)
            }
            navigationControllerOverlays.lastOrNull()?.let {
                it.visibility = View.GONE
                windowView.removeView(it)
            }
        }
        navigationController.viewDidAppear()
    }

    // Remove all the navigation controllers and overlays. Make screen clean :)
    private fun detachAllNavigationControllers(animated: Boolean, onCompletion: () -> Unit) {
        fun removeNavViewsAndContinue() {
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
        val navigationController = navigationControllers.last()
        if (navigationController.presentationConfig.overFullScreen) {
            if (navigationControllers.size >= 2) {
                fun removePrevNav(i: Int) {
                    if (i < 0)
                        return
                    navigationControllers[i].let {
                        it.visibility = View.GONE
                        windowView.removeView(it)
                        if (!it.presentationConfig.overFullScreen) {
                            navigationControllerOverlays[i].let {
                                it?.visibility = View.GONE
                                windowView.removeView(it)
                            }
                            removePrevNav(i - 1)
                        }
                    }
                }
                removePrevNav(navigationControllers.size - 2)
            }
            navigationController.viewDidAppear()
        }
    }

    // Called before a navigation dismiss, to add necessary views to the hierarchy
    private fun addPrevNavigationControllersToHierarchy() {
        val navigationController = navigationControllers.lastOrNull()
        if (navigationController?.presentationConfig?.overFullScreen == true) {
            fun presentPrevScreen(i: Int) {
                navigationControllers[i].let {
                    windowView.addView(it, 0)
                    it.visibility = View.VISIBLE
                    it.viewWillAppear()
                    if (!it.presentationConfig.overFullScreen) {
                        navigationControllerOverlays[i].let {
                            windowView.addView(it, 0)
                            it?.visibility = View.VISIBLE
                        }
                        presentPrevScreen(i - 1)
                    }
                }
            }
            presentPrevScreen(navigationControllers.size - 2)
        }
    }

    private fun blockTouches() {
        touchBlockerView.isGone = false
    }

    private fun unblockTouches() {
        touchBlockerView.isGone = true
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
            val newState = state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE
            if (isScreenRecordInProgress != newState) {
                isScreenRecordInProgress = newState
                navigationControllers.forEach {
                    it.onScreenRecordStateChanged(newState)
                }
            }
        }
    }
}
