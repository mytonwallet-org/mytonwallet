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
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.material.bottomSheetBehavior.BottomSheetBehavior
import org.mytonwallet.app_air.uicomponents.widgets.material.bottomSheetBehavior.BottomSheetBehavior.BottomSheetCallback
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
class WNavigationController(
    val window: WWindow,
    val presentationConfig: PresentationConfig = PresentationConfig()
) : CoordinatorLayout(window), WThemedView {
    data class PresentationConfig(
        val overFullScreen: Boolean = true,
        val isBottomSheet: Boolean = false,
        val aboveKeyboard: Boolean = false,
    )

    init {
        id = generateViewId()
    }

    interface ITabBarController {
        val navigationController: WNavigationController?
        val activeNavigationController: WNavigationController?
        val pausedBlurViews: Boolean
        fun getBottomNavigationHeight(): Int
        fun minimize(
            nav: WNavigationController,
            onProgress: (progress: Float) -> Unit,
            onMaximizeProgress: (progress: Float) -> Unit
        )

        fun maximize()
        fun dismissMinimized(animated: Boolean = true)
        fun scrollingUp()
        fun scrollingDown()
        fun pauseBlurring()
        fun resumeBlurring()
        fun setSearchText(text: String)
    }

    var tabBarController: ITabBarController? = null
    private var keyboardAnimationInProgress = false

    var viewControllers: ArrayList<WViewController> = arrayListOf()
    private val darkView: WView by lazy {
        val v = WView(context)
        v.setBackgroundColor(Color.BLACK)
        // block touches on dark overlay
        v.setOnTouchListener { _, _ ->
            presentationConfig.overFullScreen
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
        return Insets.of(
            window.systemBars?.left ?: 0,
            window.systemBars?.top ?: 0,
            window.systemBars?.right ?: 0,
            tabBarController?.getBottomNavigationHeight() ?: (window.systemBars?.bottom ?: 0),
        )
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
        val keyboardHeight = (window.imeInsets?.bottom ?: 0) - (getSystemBars().bottom)
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

    // Set root view controller right after init
    fun setRoot(viewController: WViewController) {
        if (viewControllers.isNotEmpty())
            return
        viewController.navigationController = this
        addViewController(viewController)
        addView(viewController.view, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (presentationConfig.isBottomSheet) {
            // Presented as modal. Should setup bottom sheet behaviour.
            if (viewController.isExpandable)
                viewController.view.post {
                    setupBottomSheetBehaviour(viewController)
                }
            else
                setupBottomSheetBehaviour(viewController)
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
        viewControllers.last().viewWillDisappear()
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
    private var isAnimating = false
    fun push(
        viewController: WViewController,
        animated: Boolean = true,
        onCompletion: (() -> Unit)? = null
    ) {
        val hidingVC = viewControllers.last()
        hidingVC.apply {
            isEnabled = false
        }
        hidingVC.viewWillDisappear()
        viewController.navigationController = this
        addViewController(viewController)
        addView(viewController.view, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (presentationConfig.isBottomSheet) {
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
            viewController.getModalHalfExpandedHeight()?.let { newHeight ->
                updateLayoutParams {
                    height = max(this@WNavigationController.height, newHeight)
                }
                val hidingVCHeight =
                    hidingVC.getModalHalfExpandedHeight() ?: hidingVC.view.measuredHeight
                val newVCHeight = viewController.getModalHalfExpandedHeight()
                    ?: viewController.view.measuredHeight
                val diff = hidingVCHeight - newVCHeight
                animate()
                    .translationYBy(diff.toFloat())
                    .setDuration(if (WGlobalStorage.getAreAnimationsActive()) AnimationConstants.NAV_PUSH else 0)
                    .setInterpolator(WInterpolator.emphasized)
                    .withEndAction {
                        setupBottomSheetBehaviour(viewController)
                    }
                    .start()
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
                        isAnimating = false
                        WGlobalStorage.decDoNotSynchronize()
                        unblockTouches()
                        onEnd()
                    }
                })
            viewController.view.post {
                isAnimating = true
                WGlobalStorage.incDoNotSynchronize()
                viewController.view.y = 0f
                viewController.view.visibility = VISIBLE
                animation.start()
            }
        } else {
            onEnd()
        }
    }

    // Called whenever a view controller in going to be presented on the nav controller
    private fun addViewController(viewController: WViewController) {
        viewControllers.add(viewController)
        setupSwipeGestureOn(viewController)
    }

    // Setup bottom sheet behaviour
    private var bottomSheetBehaviorHolder: WViewController? = null
    private fun setupBottomSheetBehaviour(viewController: WViewController) {
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
                }
            }
        })
        bottomSheetBehavior.setState(if (isExpandable) BottomSheetBehavior.STATE_HALF_EXPANDED else BottomSheetBehavior.STATE_EXPANDED)
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
            window.dismissLastNav(onCompletion = onCompletion)
            return
        }
        if (presentationConfig.isBottomSheet && isKeyboardOpen) {
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
        if (presentationConfig.isBottomSheet) {
            val topVC = viewControllers.lastOrNull() ?: return
            val prevVC = viewControllers.getOrNull(viewControllers.size - 2) ?: return
            val topVCHeight = topVC.getModalHalfExpandedHeight() ?: topVC.view.measuredHeight
            val prevVCHeight = prevVC.getModalHalfExpandedHeight() ?: prevVC.view.measuredHeight
            val diff = topVCHeight - prevVCHeight
            animate()
                .translationYBy(diff.toFloat())
                .setDuration(if (WGlobalStorage.getAreAnimationsActive()) AnimationConstants.NAV_POP else 0)
                .setInterpolator(WInterpolator.emphasized)
                .withEndAction {
                    updateLayoutParams {
                        height = prevVCHeight
                    }
                    setupBottomSheetBehaviour(prevVC)
                }
                .start()
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
        viewControllers.lastOrNull()?.swipeTouchListener?.behindView =
            WeakReference(viewControllers[viewControllers.count() - 2].view)
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
        }
    }

    // Return FALSE if consumed the back event.
    fun onBackPressed(): Boolean {
        if (isAnimating || keyboardAnimationInProgress)
            return false
        if (viewControllers.lastOrNull()?.isLockedScreen == true) {
            window.moveTaskToBack(true)
            return false
        }
        if (viewControllers.lastOrNull()?.isBackAllowed == false) {
            if (window.isAnimating)
                return false
            if (window.dismissLastNav()) {
                viewControllers.last().viewWillDisappear()
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
