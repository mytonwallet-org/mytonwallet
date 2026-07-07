package org.mytonwallet.app_air.uicomponents.base

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.graphics.Color
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.coordinatorlayout.widget.CoordinatorLayout
import androidx.core.animation.doOnEnd
import androidx.core.graphics.Insets
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.drawable.TabletEdgeFadeDrawable
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.material.bottomSheetBehavior.BottomSheetBehavior
import org.mytonwallet.app_air.uicomponents.widgets.material.bottomSheetBehavior.BottomSheetBehavior.BottomSheetCallback
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
open class WNavigationController(
    val window: WWindow,
    val presentationConfig: PresentationConfig = PresentationConfig()
) : CoordinatorLayout(window), WThemedView {
    enum class PresentationStyle {
        // Covers the whole screen; screens beneath are detached while shown.
        ForceFullScreen,

        // Floating window on Tablets
        PreferredFullScreen,

        // Slides up from the bottom over a dimmed backdrop, sized to its content.
        BottomSheet,

        // Partial cover kept above a still-live screen (no dim, not a sheet, doesn't detach below).
        Overlay,
    }

    data class PresentationConfig(
        val style: PresentationStyle = PresentationStyle.ForceFullScreen,
        val aboveKeyboard: Boolean = false,
    ) {
        companion object {
            val PreferredFullScreen = PresentationConfig(PresentationStyle.PreferredFullScreen)
        }
    }

    // On wide (tablet) layout, BottomSheet and PreferredFullScreen are shown as a centered floating
    // window above the previous screens instead of a sheet / full screen. The exception is a window
    // too short for a centered window, where they fall back to full screen (see isShortWideWindow).
    private val isWideLayout: Boolean get() = window.isWideLayout
    val isShortWideWindow: Boolean
        get() {
            if (!isWideLayout)
                return false
            val windowHeight = window.windowView.height
            return windowHeight in 1..<WWindow.CENTERED_WINDOW_MIN_HEIGHT_DP.dp
        }

    open val centeredWindowWidth: Int? = null

    open val isCenteredWindow: Boolean
        get() {
            if (!isWideLayout)
                return false
            if (isShortWideWindow)
                return false
            return presentationConfig.style == PresentationStyle.BottomSheet ||
                presentationConfig.style == PresentationStyle.PreferredFullScreen
        }

    // Effective presentation flags (resolve PresentationStyle against the current layout).
    // A centered window keeps the previous screen mounted behind it (not over-full-screen) and is
    // not a bottom sheet.
    val overFullScreen: Boolean
        get() = !isCenteredWindow && (
            presentationConfig.style == PresentationStyle.ForceFullScreen ||
                presentationConfig.style == PresentationStyle.PreferredFullScreen ||
                (isShortWideWindow && presentationConfig.style == PresentationStyle.BottomSheet)
            )
    val isBottomSheet: Boolean
        get() = !isCenteredWindow && !isShortWideWindow &&
            presentationConfig.style == PresentationStyle.BottomSheet

    init {
        id = generateViewId()
    }

    var tabBarController: ITabsVC? = null
    private var keyboardAnimationInProgress = false

    var viewControllers: ArrayList<WViewController> = arrayListOf()
    private val darkView: WView by lazy {
        val v = WView(context)
        if (tabBarController != null)
            v.background = TabletEdgeFadeDrawable()
        else
            v.setBackgroundColor(Color.BLACK)
        // block touches on dark overlay
        v.setOnTouchListener { _, _ ->
            overFullScreen
        }
        v
    }
    private val touchBlockerView: View = View(context).apply {
        isClickable = true
        isFocusable = true
        setOnTouchListener { _, _ -> true }
        isGone = true
        translationZ = Float.MAX_VALUE
    }

    init {
        addView(touchBlockerView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    private var configured = false
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (configured) {
            isDismissed = false
            return
        }
        configured = true
        setupViews()
    }

    var isDismissed = false
    fun willBeDismissed() {
        viewWillDisappear()
        lockView()
        hideKeyboard()
        isDismissed = true
    }

    fun setupViews() {
        if (viewControllers.isNotEmpty())
            viewControllers.last().view.bringToFront()
        insetsUpdated()
    }

    fun getSystemBars(): Insets {
        if (isCenteredWindow)
            return Insets.of(0, 0, 0, 0)
        return Insets.of(
            window.systemBars?.left ?: 0,
            window.systemBars?.top ?: 0,
            window.systemBars?.right ?: 0,
            tabBarController?.getBottomNavigationHeight() ?: (window.systemBars?.bottom ?: 0),
        )
    }

    val bottomInset: Int
        get() {
            if (isCenteredWindow)
                return 0
            return (if (WGlobalStorage.isGradientNavigationBarActive()) ViewConstants.ADDITIONAL_GRADIENT_HEIGHT.dp.roundToInt() else 0) +
                (tabBarController?.getBottomNavigationHeight() ?: (window.systemBars?.bottom ?: 0))
        }

    val imeInsetBottom: Int
        get() {
            val imeBottom = window.imeInsets?.bottom ?: 0
            if (!isCenteredWindow || imeBottom <= 0) return imeBottom
            val windowHeight = window.windowView.height
            if (windowHeight <= 0) return imeBottom
            val gapBelowWindow = windowHeight - (y.toInt() + height)
            return (window.systemBars?.bottom ?: 0) + max(0, imeBottom - gapBelowWindow)
        }

    fun insetsUpdated() {
        viewControllers.lastOrNull()?.apply {
            insetsUpdated()
            if (isDisappeared && viewControllers.size > 1) {
                viewControllers[viewControllers.size - 2].insetsUpdated()
            }
        }
        handleAboveKeyboardVisibility()
    }

    var prevBottomMargin = 0
    private fun handleAboveKeyboardVisibility() {
        if (!presentationConfig.aboveKeyboard)
            return
        val imeBottom = window.imeInsets?.bottom ?: 0
        val keyboardHeight = if (isCenteredWindow) {
            val windowHeight = window.windowView.height
            if (windowHeight <= 0 || imeBottom <= 0) 0
            else {
                val windowBottom = top + height
                val keyboardTop = windowHeight - imeBottom
                windowBottom - keyboardTop
            }
        } else {
            imeBottom - getSystemBars().bottom
        }
        val newBottomMargin = max(keyboardHeight, 0)
        val diff = newBottomMargin - prevBottomMargin
        if (diff != 0) {
            prevBottomMargin = newBottomMargin
            keyboardAnimationInProgress = true
            val startY = translationY
            val endY = startY - diff.toFloat()
            val animator = ValueAnimator.ofFloat(startY, endY)
            animator.duration = AnimationConstants.VERY_VERY_QUICK_ANIMATION

            animator.addUpdateListener { valueAnimator ->
                val currentY = valueAnimator.animatedValue as Float
                translationY = currentY
                viewControllers.lastOrNull()?.keyboardAnimationFrameRendered()
            }

            animator.doOnEnd {
                keyboardAnimationInProgress = false
            }

            animator.start()
        }
    }

    fun onBottomSheetHeightChanged() {
        if (!isBottomSheet || isBottomSheetHeightAnimating || layoutParams == null) {
            return
        }
        val topVC = viewControllers.lastOrNull() ?: return
        val newNavHeight = topVC.getModalHalfExpandedHeight() ?: return
        val windowHeight = window.windowView.height.takeIf { it > 0 } ?: return
        updateLayoutParams { height = newNavHeight }
        this.y = (windowHeight - newNavHeight).toFloat()
        topVC.view.requestLayout()
    }

    // Re-establish the resting bottom-sheet layout + behaviour. Used when a centered window becomes a
    // bottom sheet on a layout change (rotation tablet->phone): the nav still has the centered
    // window's fixed width / no behaviour, so reset to full width and re-attach BottomSheetBehavior.
    fun applyBottomSheetLayout() {
        val topVC = viewControllers.lastOrNull() ?: return
        val windowHeight = window.windowView.height.takeIf { it > 0 } ?: return
        translationX = 0f
        x = 0f
        val shouldPresentFullScreen = topVC.isExpandable
        val navHeight = if (shouldPresentFullScreen) MATCH_PARENT
        else (topVC.getModalHalfExpandedHeight() ?: layoutParams?.height ?: MATCH_PARENT)
        updateLayoutParams {
            width = MATCH_PARENT
            height = navHeight
        }
        y = if (navHeight == MATCH_PARENT) 0f else (windowHeight - navHeight).toFloat()
        setupBottomSheetBehaviour(topVC, restoreExpanded = true)
    }

    // Set root view controller right after init
    fun setRoot(viewController: WViewController) {
        if (viewControllers.isNotEmpty())
            return
        viewController.navigationController = this
        addViewController(viewController)
        addView(viewController.view, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (isBottomSheet) {
            // Presented as modal. Should setup bottom sheet behaviour.
            if (viewController.isExpandable)
                viewController.view.post {
                    setupBottomSheetBehaviour(viewController)
                }
            else
                setupBottomSheetBehaviour(viewController)
        }
    }

    /**
     * Replace the single root view controller in place, destroying the previous stack. Intended
     * for swapping tab-container view controllers (e.g. phone <-> tablet tabs) that own their own content
     * and don't rely on this nav's back stack.
     */
    fun replaceRoot(viewController: WViewController) {
        viewControllers.forEach {
            it.viewWillDisappear()
            if (it.view.parent == this)
                removeView(it.view)
            it.onDestroy()
        }
        viewControllers.clear()
        setRoot(viewController)
        if (!isDisappeared) {
            viewController.viewWillAppear()
            viewController.viewDidAppear()
        }
    }

    var isDisappeared = true
        private set

    fun viewWillAppear() {
        Logger.d(Logger.LogTag.SCREEN, "NavWillAppear: hash=${hashCode()}")
        if (isDisappeared) {
            isDisappeared = false
            unblockTouches()
        }
        viewControllers.lastOrNull()?.viewWillAppear()
    }

    fun viewWillDisappear() {
        Logger.d(Logger.LogTag.SCREEN, "NavWillDisappear: hash=${hashCode()}")
        isDisappeared = true
        viewControllers.lastOrNull()?.viewWillDisappear()
    }

    fun viewDidAppear() {
        viewControllers.lastOrNull()?.apply {
            if (isDisappeared)
                viewWillAppear()
            viewDidAppear()
        }
    }

    fun viewDidEnterForeground() {
        viewControllers.lastOrNull()?.viewDidEnterForeground()
    }

    override fun updateTheme() {
        viewControllers.forEach {
            it.notifyThemeChanged()
        }
    }

    // Called whenever we want to add a view controller to the stack and present it
    private var isTransitionAnimating = false
    private var isBottomSheetHeightAnimating = false
    fun push(
        viewController: WViewController,
        animated: Boolean = true,
        onCompletion: (() -> Unit)? = null
    ) {
        val hidingVC = viewControllers.lastOrNull() ?: return
        PopupHelpers.dismissAllPopups()
        hidingVC.apply {
            isEnabled = false
        }
        hidingVC.viewWillDisappear()
        viewController.navigationController = this
        addViewController(viewController)
        addView(viewController.view, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        var pendingHeightAnimation: ValueAnimator? = null
        if (isBottomSheet) {
            if (hidingVC.isExpandable) {
                throw Exception("Pushing on an expandable bottom-sheet is not supported.")
            }
            if (viewController.isExpandable) {
                throw Exception("Pushing expandable bottom-sheet is not supported.")
            }
            if (viewController.getModalHalfExpandedHeight() == null) {
                throw Exception("Pushing expandable bottom-sheet is not supported.")
            }
            // Presented as modal. Should setup bottom sheet behaviour.
            viewController.getModalHalfExpandedHeight()?.let { newVCHeight ->
                val hidingVCHeight =
                    hidingVC.getModalHalfExpandedHeight() ?: hidingVC.view.measuredHeight
                val startTranslationY = translationY
                if (!WGlobalStorage.getAreAnimationsActive()) {
                    translationY = startTranslationY + (hidingVCHeight - newVCHeight)
                    updateLayoutParams { height = newVCHeight }
                    setupBottomSheetBehaviour(viewController)
                } else {
                    isBottomSheetHeightAnimating = true
                    pendingHeightAnimation = ValueAnimator.ofFloat(0f, 1f).apply {
                        duration = AnimationConstants.NAV_PUSH
                        interpolator = WInterpolator.emphasized
                        addUpdateListener { animator ->
                            val fraction = animator.animatedValue as Float
                            val currentHeight =
                                (hidingVCHeight + (newVCHeight - hidingVCHeight) * fraction).roundToInt()
                            updateLayoutParams { height = currentHeight }
                            translationY = startTranslationY + (hidingVCHeight - currentHeight)
                        }
                        doOnEnd {
                            isBottomSheetHeightAnimating = false
                            updateLayoutParams { height = newVCHeight }
                            setupBottomSheetBehaviour(viewController)
                            onBottomSheetHeightChanged()
                        }
                    }
                }
            }
        }
        viewController.viewWillAppear()
        fun onEnd() {
            removeView(hidingVC.view)
            hidingVC.view.visibility = GONE
            viewController.view.alpha = 1f
            onCompletion?.invoke()
            viewController.viewDidAppear()
        }
        if (animated && WGlobalStorage.getAreAnimationsActive()) {
            blockTouches()
            viewController.view.visibility = INVISIBLE
            viewController.view.alpha = 0f
            viewController.view.translationX = 48f * LocaleController.rtlMultiplier

            var ended = false
            val animation = viewController.view.animate()
                .alpha(1f)
                .translationX(0f)
                .setDuration(AnimationConstants.NAV_PUSH)
                .setInterpolator(WInterpolator.emphasized)
                .setListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        if (ended)
                            return
                        ended = true
                        isTransitionAnimating = false
                        WGlobalStorage.decDoNotSynchronize()
                        unblockTouches()
                        onEnd()
                    }
                })
            viewController.view.post {
                isTransitionAnimating = true
                WGlobalStorage.incDoNotSynchronize()
                viewController.view.y = 0f
                viewController.view.visibility = VISIBLE
                animation.start()
                pendingHeightAnimation?.start()
            }
        } else {
            onEnd()
        }
    }

    // Called whenever a view controller in going to be presented on the nav controller
    private fun addViewController(viewController: WViewController) {
        viewControllers.add(viewController)
        setupSwipeGestureOn(viewController)
        tabBarController?.navStackUpdated(this)
    }

    /**
     * Detach every view controller above the root WITHOUT destroying them, leaving only the root
     * shown. Returns the detached controllers (root-first order) so they can be re-adopted by
     * another navigation controller — used to keep full-screen pushes alive across a phone<->tablet
     * container swap. The caller is responsible for re-hosting or destroying the returned VCs.
     */
    fun detachAboveRoot(): List<WViewController> {
        if (viewControllers.size <= 1)
            return emptyList()
        val detached = viewControllers.drop(1).toList()
        detached.forEach {
            it.viewWillDisappear()
            if (it.view.parent == this)
                removeView(it.view)
            it.swipeTouchListener = null
        }
        val root = viewControllers.first()
        viewControllers = arrayListOf(root)
        root.view.visibility = VISIBLE
        if (!isDisappeared)
            root.viewWillAppear()
        return detached
    }

    /**
     * Re-host controllers previously obtained from [detachAboveRoot] on top of this nav's root,
     * preserving their order. No appearance animation: the last one ends up visible, the rest stay
     * in the back stack with their views detached (mirroring a settled push stack).
     */
    fun adoptAboveRoot(adopted: List<WViewController>) {
        if (adopted.isEmpty())
            return
        val root = viewControllers.firstOrNull() ?: return
        root.viewWillDisappear()
        if (root.view.parent == this)
            removeView(root.view)
        adopted.forEachIndexed { index, vc ->
            vc.navigationController = this
            addViewController(vc)
            if (index == adopted.lastIndex) {
                addView(vc.view, LayoutParams(MATCH_PARENT, MATCH_PARENT))
                if (!isDisappeared) {
                    vc.viewWillAppear()
                    vc.insetsUpdated()
                    vc.viewDidAppear()
                }
            }
        }
    }

    // Detach any bottom-sheet behaviour (used when a sheet becomes a centered window / full screen).
    fun clearBottomSheetBehaviour() {
        (bottomSheetBehaviorHolder?.view?.layoutParams as? LayoutParams)?.behavior = null
        bottomSheetBehaviorHolder = null
    }

    // Setup bottom sheet behaviour
    private var bottomSheetBehaviorHolder: WViewController? = null
    private fun setupBottomSheetBehaviour(
        viewController: WViewController,
        restoreExpanded: Boolean = false,
    ) {
        val wasFullyExpanded = restoreExpanded && viewController.isModalFullyExpanded
        (bottomSheetBehaviorHolder?.view?.layoutParams as? LayoutParams)?.behavior = null
        bottomSheetBehaviorHolder = viewController
        (viewController.view.layoutParams as LayoutParams).behavior =
            BottomSheetBehavior<View>(context)
        val bottomSheetBehavior = BottomSheetBehavior.from<View>(viewController.view)
        val isExpandable = viewController.isExpandable
        if (isExpandable)
            viewController.getModalHalfExpandedHeight()?.let { calcHalfExpandedHeight ->
                if (height == 0)
                    return@let
                bottomSheetBehavior.isFitToContents = false
                val contentHeight = calcHalfExpandedHeight.toFloat() + getSystemBars().bottom
                bottomSheetBehavior.halfExpandedRatio = min(0.9f, contentHeight / height)
                viewController.onModalSlide(0, 0f)
            }
        bottomSheetBehavior.addBottomSheetCallback(object : BottomSheetCallback() {
            override fun onStateChanged(bottomSheet: View, newState: Int) {
                when (newState) {
                    BottomSheetBehavior.STATE_EXPANDED -> {}
                    BottomSheetBehavior.STATE_COLLAPSED -> {
                        window.dismissLastNav()
                    }

                    BottomSheetBehavior.STATE_DRAGGING -> {}
                    BottomSheetBehavior.STATE_SETTLING -> {}
                    BottomSheetBehavior.STATE_HIDDEN -> {}
                    else -> {}
                }
            }

            override fun onSlide(bottomSheet: View, slideOffset: Float) {
                if (isExpandable) {
                    val halfExpandedRatio = bottomSheetBehavior.halfExpandedRatio
                    window.activeOverlay?.alpha =
                        1 - ((halfExpandedRatio - slideOffset) / (1 - halfExpandedRatio))
                            .coerceIn(0f, 1f)
                    val offset = (slideOffset - halfExpandedRatio) * height
                    val progress = ((slideOffset - halfExpandedRatio) / (1 - halfExpandedRatio))
                        .coerceIn(0f, 1f)
                    viewController.onModalSlide(offset.roundToInt(), progress)
                } else {
                    window.activeOverlay?.alpha = slideOffset
                    viewController.onModalSlide(bottomSheet.top, slideOffset)
                }
            }
        })
        bottomSheetBehavior.setState(
            if (isExpandable && !wasFullyExpanded)
                BottomSheetBehavior.STATE_HALF_EXPANDED
            else BottomSheetBehavior.STATE_EXPANDED
        )
        if (wasFullyExpanded) {
            viewController.onModalSlide(0, 1f)
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun setupSwipeGestureOn(viewController: WViewController) {
        if (viewControllers.size < 2)
            return
        viewController.swipeTouchListener = SwipeTouchListener(
            WeakReference(viewController),
            WeakReference(this),
            WeakReference(viewControllers[viewControllers.size - 2].view),
            WeakReference(darkView)
        ) {
            // Dismissed
            val removingVC = viewControllers.lastOrNull()
            removeView(removingVC?.view)
            viewControllers.remove(removingVC)
            removingVC?.onDestroy()
            viewControllers.lastOrNull()?.view?.apply {
                isEnabled = true
                bringToFront()
                viewDidAppear()
            }
            tabBarController?.navStackUpdated(this)
        }
    }

    private val isKeyboardOpen: Boolean
        get() {
            return (window.imeInsets?.bottom ?: 0) > 0
        }

    fun pop(animated: Boolean = true, onCompletion: (() -> Unit)? = null) {
        if (viewControllers.lastOrNull()?.swipeTouchListener?.isPopInProgress == true) {
            // Pop is already in progress
            return
        }
        if (viewControllers.size == 1) {
            if (window.isAnimating)
                return
            if (tabBarController?.switchToFirstTab() == true)
                return
            window.dismissLastNav(onCompletion = onCompletion)
            return
        }
        if (isBottomSheet && isKeyboardOpen) {
            hideKeyboard()
            return
        }
        if (viewControllers.size >= 2)
            viewControllers[viewControllers.size - 2].apply {
                isEnabled = true
                viewWillAppear()
            }
        if (viewControllers.lastOrNull()?.swipeTouchListener != null) {
            viewControllers.lastOrNull()?.swipeTouchListener?.triggerPop(
                animated,
                onCompletion = onCompletion
            )
            updateHeightOnPop()
        }
        // else ??
    }

    fun updateHeightOnPop() {
        if (isBottomSheet) {
            val topVC = viewControllers.lastOrNull() ?: return
            val prevVC = viewControllers.getOrNull(viewControllers.size - 2) ?: return
            val topVCHeight = topVC.getModalHalfExpandedHeight() ?: topVC.view.measuredHeight
            val prevVCHeight = prevVC.getModalHalfExpandedHeight() ?: prevVC.view.measuredHeight
            val startTranslationY = translationY
            if (!WGlobalStorage.getAreAnimationsActive()) {
                translationY = startTranslationY + (topVCHeight - prevVCHeight)
                updateLayoutParams { height = prevVCHeight }
                setupBottomSheetBehaviour(prevVC)
            } else {
                ValueAnimator.ofFloat(0f, 1f).apply {
                    duration = AnimationConstants.NAV_POP
                    interpolator = WInterpolator.emphasized
                    addUpdateListener { animator ->
                        val fraction = animator.animatedValue as Float
                        val currentHeight =
                            (topVCHeight + (prevVCHeight - topVCHeight) * fraction).roundToInt()
                        updateLayoutParams { height = currentHeight }
                        translationY = startTranslationY + (topVCHeight - currentHeight)
                    }
                    doOnEnd {
                        updateLayoutParams { height = prevVCHeight }
                        setupBottomSheetBehaviour(prevVC)
                    }
                    start()
                }
            }
        }
    }

    fun popToRoot(animated: Boolean = true, onCompletion: (() -> Unit)? = null) {
        if (viewControllers.size <= 1) {
            onCompletion?.invoke()
            return
        }
        removePrevViewControllers(keptFirstViewControllers = 1)
        pop(animated = animated, onCompletion = onCompletion)
    }

    fun removePrevViewControllerOnly() {
        if (viewControllers.size < 2)
            return
        val removingVC = viewControllers[viewControllers.size - 2]
        removingVC.viewWillDisappear()
        removeView(removingVC.view)
        removingVC.onDestroy()
        viewControllers.removeAt(viewControllers.size - 2)
        if (viewControllers.size >= 2) {
            viewControllers.lastOrNull()?.swipeTouchListener?.behindView =
                WeakReference(viewControllers[viewControllers.size - 2].view)
        } else {
            viewControllers.lastOrNull()?.swipeTouchListener = null
        }
    }

    fun removePrevViewControllers(keptFirstViewControllers: Int = 0) {
        for (i in keptFirstViewControllers..<viewControllers.size - 1) {
            val removingVC = viewControllers[i]
            removingVC.viewWillDisappear()
            removeView(removingVC.view)
            removingVC.onDestroy()
        }
        viewControllers =
            ArrayList(viewControllers.take(keptFirstViewControllers) + viewControllers.takeLast(1))
        if (keptFirstViewControllers > 0) {
            viewControllers[keptFirstViewControllers].swipeTouchListener?.behindView =
                WeakReference(viewControllers[keptFirstViewControllers - 1].view)
        }
        tabBarController?.navStackUpdated(this)
    }

    fun removeViewController(removingVC: WViewController) {
        if (viewControllers.lastOrNull() == removingVC) {
            pop()
        } else {
            removingVC.viewWillDisappear()
            if (removingVC.view.parent == this)
                removeView(removingVC.view)
            removingVC.onDestroy()
            val index = viewControllers.indexOf(removingVC)
            if (index > 0) {
                viewControllers.getOrNull(index + 1)?.swipeTouchListener?.behindView =
                    WeakReference(viewControllers[index - 1].view)
            }
            viewControllers.remove(removingVC)
            tabBarController?.navStackUpdated(this)
        }
    }

    // Return FALSE if consumed the back event.
    fun onBackPressed(): Boolean {
        if (isTransitionAnimating || keyboardAnimationInProgress)
            return false
        if (viewControllers.lastOrNull()?.isLockedScreen == true) {
            window.moveTaskToBack(true)
            return false
        }
        if (viewControllers.lastOrNull()?.isBackAllowed == false) {
            if (window.isAnimating)
                return false
            if (tabBarController?.switchToFirstTab() == true)
                return false
            if (window.dismissLastNav()) {
                viewControllers.lastOrNull()?.viewWillDisappear()
                return false
            }
            return true
        }
        if (viewControllers.lastOrNull()?.onBackPressed() == false)
            return false
        pop()
        return false
    }

    // Return true if navigation controller allows back
    fun isBackAllowed(): Boolean {
        return viewControllers.size > 1 && viewControllers.last().isBackAllowed
    }

    fun scrollToTop() {
        viewControllers.last().scrollToTop()
    }

    fun onDestroy() {
        viewControllers.forEach { it.onDestroy() }
        viewControllers.clear()
    }

    fun blockTouches() {
        touchBlockerView.isGone = false
    }

    fun unblockTouches() {
        touchBlockerView.isGone = true
    }

    val isSwipingBack: Boolean
        get() {
            return viewControllers.lastOrNull()?.swipeTouchListener?.isSwiping == true
        }

    fun onScreenRecordStateChanged(isRecording: Boolean) {
        viewControllers.forEach {
            it.onScreenRecordStateChanged(isRecording)
        }
    }
}
