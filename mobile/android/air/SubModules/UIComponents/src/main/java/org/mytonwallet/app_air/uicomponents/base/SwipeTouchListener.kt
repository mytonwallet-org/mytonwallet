package org.mytonwallet.app_air.uicomponents.base

import android.animation.Animator
import android.annotation.SuppressLint
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.View.GONE
import android.view.View.OnTouchListener
import android.view.View.VISIBLE
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min


/**
 * An extended OnTouchListener that allows swiping of a View.
 *
 *
 * onClick(), onSwipeLeft() and onSwipeRight() must be overridden
 * in order provide desired functionality after a swipe or touch.
 */
class SwipeTouchListener
/**
 * Public constructor for the class SwipeTouchListener.
 *
 * @param activity   An Activity-pointer.
 * @param viewParent The ViewGroup that contains the View.
 */(
    private val viewController: WeakReference<WViewController>,
    private val mViewParent: WeakReference<WNavigationController>,
    var behindView: WeakReference<WViewController.ContainerView>,
    private var darkView: WeakReference<View>,
    private val onDismiss: () -> Unit
) :
    OnTouchListener {
    private var mView: View? = null

    private var mVelocityTracker: VelocityTracker? = null

    private var mViewPressed = false
    var isSwiping = false
        private set

    private var mDownX = 0f
    private var mSwipeSlop = 0
    private var defaultBehindTranslationX = 0f
    private val scaleBehindView = DevicePerformanceClassifier.isAboveAverage
    private var isRtl = false

    /**
     * Is called when the View has recieved a touch event.
     * Contains a switch() that controls what should happen
     * when the user performs certain actions.
     *
     * @param view  The View that recieved the touch event
     * @param event A MotionEvent-object containing info about
     * the event
     */
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouch(view: View, event: MotionEvent): Boolean {
        val viewController = viewController.get() ?: return false
        mSwipeSlop = ViewConfiguration
            .get(viewController.context).scaledTouchSlop

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                if (mViewPressed) return false
                mViewPressed = true

                actionDown(view, event)
            }

            MotionEvent.ACTION_MOVE -> actionMove(event)
            MotionEvent.ACTION_UP -> {
                mViewPressed = false

                if (isSwiping) onSwipe(event)
                else {
                    return onClick()
                }
            }

            MotionEvent.ACTION_CANCEL -> {
                mViewPressed = false
                mVelocityTracker = null

                view.translationX = 0f
            }
        }
        return true
    }

    /**
     * Is called from 'onTouch()' when the View has recieved its
     * first touch event.
     *
     * @param view  The View that recieved the touch event
     * @param event A MotionEvent-object containing info about
     * the event
     */
    private fun actionDown(view: View, event: MotionEvent) {
        if (mVelocityTracker == null) mVelocityTracker = VelocityTracker.obtain()
        else mVelocityTracker!!.clear()

        mVelocityTracker!!.addMovement(event)

        mView = view
        mDownX = event.x
        defaultBehindTranslationX = (view.width / 5).toFloat()
        behindView.get()?.viewController?.get()?.insetsUpdated()

        // Check if the view is in RTL layout direction
        isRtl = view.layoutDirection == View.LAYOUT_DIRECTION_RTL
    }

    /**
     * Is called from 'onTouch()' when the View has been dragged
     * to a location.
     *
     * @param event A MotionEvent-object containing info about
     * the event
     */
    private fun actionMove(event: MotionEvent) {
        if (mVelocityTracker == null)
            return
        mVelocityTracker!!.addMovement(event)

        val currentX = event.x + mView!!.translationX
        val deltaX = currentX - mDownX

        if (!isSwiping) {
            if (abs(deltaX.toDouble()) > mSwipeSlop) {
                isSwiping = true
                mDownX = event.x
                darkView.get()?.let {
                    viewController.get()?.navigationController?.addView(
                        it, 0,
                        ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                    )
                    it.visibility = VISIBLE
                }
                mViewParent.get()?.requestDisallowInterceptTouchEvent(true)
                behindView.get()?.let {
                    viewController.get()?.navigationController?.addView(
                        it, 0,
                        ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                    )
                    it.visibility = VISIBLE
                    it.alpha = 1f
                    (it.parent as? View)?.setBackgroundColor(WColor.SecondaryBackground.color)
                }
            }
        }

        if (isSwiping) {
            val translation = if (isRtl) {
                min(0f, currentX - mDownX)
            } else {
                max(0f, currentX - mDownX)
            }
            mView!!.translationX = translation

            val progress = abs(translation) / mView!!.width
            if (scaleBehindView) {
                behindView.get()?.scaleX = 0.95f + (progress / 20)
                behindView.get()?.scaleY = behindView.get()!!.scaleX
            }
            behindView.get()?.viewController?.get()?.viewWillAppear()
            darkView.get()?.alpha = 0.5f - (progress / 5)
        }
    }

    /**
     * Is called from 'onTouch()' when the View has been released
     * and a swipe-gesture has been performed on the View.
     *
     * @param event A MotionEvent-object containing info about
     * the event
     */
    private fun onSwipe(event: MotionEvent) {
        val currentX = event.x + mView!!.translationX
        val deltaX = currentX - mDownX
        mVelocityTracker!!.computeCurrentVelocity(100)
        val velocityX =
            abs(mVelocityTracker?.xVelocity?.toDouble() ?: 0.0).toFloat()

        val outOfView: Float
        val endX: Float
        val endAlpha: Float
        var dismiss = false

        /* The user has performed a swipe-gesture at the specified
         * velocity, or over a third of the Views width has been
         * dragged out of its initial position. */
        val shouldDismiss = if (isRtl) {
            deltaX < 0 && (velocityX > SWIPE_VELOCITY_MIN || abs(deltaX.toDouble()) > mView!!.width.toFloat() / 3)
        } else {
            deltaX > 0 && (velocityX > SWIPE_VELOCITY_MIN || abs(deltaX.toDouble()) > mView!!.width.toFloat() / 3)
        }

        if (shouldDismiss) {
            outOfView = (abs(deltaX.toDouble()) / mView!!.width).toFloat()
            endX = mView!!.width.toFloat()
            endAlpha = 1f
            dismiss = true

            /* The user has released the hold on the View before it
             * should be dismissed. */
        } else {
            outOfView = (1 - (abs(deltaX.toDouble()) / mView!!.width)).toFloat()
            endX = 0f
            endAlpha = 1f
        }

        mViewParent.get()?.isEnabled = false

        val duration =
            ((1 - outOfView) * SWIPE_DURATION).toInt().toLong()
        endSwipe(duration, endAlpha, endX, dismiss)
    }

    val interpolator = WInterpolator.emphasizedAccelerate

    var isPopInProgress = false

    /**
     * Is called from 'onSwipe()', and animates the View to the
     * correct alpha- and x levels based on the direction of the swipe.
     *
     * @param duration The duration of the animation.
     * @param endAlpha The final alpha level of the View.
     * @param fEndX    The final x-position of the View.
     * @param fDismiss If the View should be dismissed from the list.
     */
    private fun endSwipe(
        duration: Long,
        endAlpha: Float,
        fEndX: Float,
        fDismiss: Boolean,
        onCompletion: (() -> Unit)? = null
    ) {
        if (fDismiss) {
            mViewParent.get()?.blockTouches()
            viewController.get()?.viewWillDisappear()
            isPopInProgress = true
            behindView.get()?.let {
                it.visibility = VISIBLE
                it.alpha = 1f
                // Adds behind view when user used back button on device
                if (it.parent == null)
                    viewController.get()?.navigationController?.addView(
                        it,
                        0,
                        ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
                    )
            }
        }

        fun animationEnded() {
            mViewParent.get()?.unblockTouches()
            isSwiping = false
            mViewParent.get()?.isEnabled = true
            (behindView.get()?.parent as? View)?.background = null

            val navigationController = viewController.get()?.navigationController
            darkView.get()?.let {
                navigationController?.removeView(it)
                it.visibility = GONE
            }
            if (fDismiss) {
                onDismiss()
                behindView.get()?.isEnabled = true
                behindView.get()?.scaleX = 1f
                behindView.get()?.scaleY = 1f
                behindView.get()?.viewController?.get()?.viewDidAppear()
            } else {
                mView!!.translationX = 0f
                behindView.get()?.let {
                    navigationController?.removeView(it)
                    it.visibility = GONE
                    it.scaleX = 1f
                    it.scaleY = 1f
                }
            }
            onCompletion?.invoke()
        }

        if (!WGlobalStorage.getAreAnimationsActive()) {
            (mView ?: viewController.get()?.view)?.apply {
                alpha = endAlpha
                translationX = fEndX * LocaleController.rtlMultiplier
                animationEnded()
            }
            return
        }

        if (duration == 0.toLong()) {
            (mView ?: viewController.get()?.view)?.apply {
                alpha = endAlpha
                translationX = fEndX * LocaleController.rtlMultiplier
            }
            animationEnded()
        } else {
            WGlobalStorage.incDoNotSynchronize()
            behindView.get()?.let { behindView ->
                if (fDismiss) {
                    behindView.animate()
                        .scaleX(1f)
                        .scaleY(1f)
                        .setDuration(duration)
                        .setInterpolator(interpolator)
                        .start()
                } else {
                    behindView.animate()
                        .scaleX(0.95f)
                        .scaleY(0.95f)
                        .setDuration(duration)
                        .setInterpolator(interpolator)
                        .start()
                }
            }
            if (isSwiping)
                darkView.get()?.animate()?.setDuration(duration)
                    ?.setInterpolator(interpolator)?.alpha(0f)
            (mView ?: viewController.get()?.view)?.animate()?.setDuration(duration)?.alpha(endAlpha)
                ?.translationX(fEndX * LocaleController.rtlMultiplier)
                ?.setListener(object : Animator.AnimatorListener {
                    override fun onAnimationEnd(anim: Animator) {
                        WGlobalStorage.decDoNotSynchronize()
                        animationEnded()
                    }

                    override fun onAnimationCancel(anim: Animator) {
                        WGlobalStorage.decDoNotSynchronize()
                        animationEnded()
                    }

                    override fun onAnimationRepeat(anim: Animator) {
                    }

                    override fun onAnimationStart(anim: Animator) {
                    }
                })
        }
    }

    /**
     * Is called when the user has performed a single click on the View.
     */
    private fun onClick(): Boolean {
        return true
    }

    fun triggerPop(animated: Boolean = true, onCompletion: (() -> Unit)?) {
        endSwipe(
            if (animated) AnimationConstants.NAV_POP else 0,
            0f,
            48f.dp,
            true,
            onCompletion
        )
    }

    companion object {
        private const val SWIPE_DURATION = AnimationConstants.QUICK_ANIMATION
        private const val SWIPE_VELOCITY_MIN = 75
    }
}
