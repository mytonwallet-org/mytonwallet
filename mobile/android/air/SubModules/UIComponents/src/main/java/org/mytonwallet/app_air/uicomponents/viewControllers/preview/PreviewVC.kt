package org.mytonwallet.app_air.uicomponents.viewControllers.preview

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.animation.doOnEnd
import androidx.core.view.updateLayoutParams
import com.facebook.drawee.drawable.ScalingUtils
import com.facebook.drawee.generic.RoundingParams
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WZoomableImageView
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import kotlin.math.min
import kotlin.math.sqrt

class PreviewVC(
    context: Context,
    val animationView: WAnimationView?, // Pass to make sure animation stays sync
    val content: Content,
    val initialPosition: Rect,
    val initialRounding: Float,
    val onPreviewDismissed: () -> Unit
) : WViewController(context) {
    override val TAG = "Preview"

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = false

    val overlayView = WBaseView(context).apply {
        setBackgroundColor(Color.BLACK)
        alpha = 0f
    }

    enum class DragState {
        NONE,
        DRAG,
        ZOOM;
    }

    private var dragState = DragState.NONE
    private var initialX = 0f
    private var initialY = 0f
    private var touchStartRawX = 0f
    private var touchStartRawY = 0f
    private var centerX = 0f
    private var centerY = 0f
    private val imageView = WZoomableImageView(context).apply {
        set(
            content.copy(
                scaleType = ScalingUtils.ScaleType.FIT_CENTER
            )
        )
        defaultRounding = Content.Rounding.Radius(initialRounding)
        alpha = 0f
        pivotX = 0f
        pivotY = 0f

        val gestureDetector =
            GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
                override fun onDoubleTap(e: MotionEvent): Boolean {
                    doubleTapped(e)
                    return true
                }

                override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                    return true
                }
            })
        @SuppressLint("ClickableViewAccessibility")
        setOnTouchListener { v, event ->
            val doubleTap = gestureDetector.onTouchEvent(event)
            if (doubleTap)
                return@setOnTouchListener true

            // Pass to zoom-controller if not dragging
            val res =
                if (dragState != DragState.DRAG) zoomableController.onTouchEvent(event) else true

            // Set drag-state to zoom if image is scaled
            if (zoomableController.getScaleFactor() != 1f) {
                dragState = DragState.ZOOM
            }

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = v.x
                    initialY = v.y
                    touchStartRawX = event.rawX
                    touchStartRawY = event.rawY
                    centerX = (v.parent as ViewGroup).width / 2f
                    centerY = (v.parent as ViewGroup).height / 2f
                    true
                }

                MotionEvent.ACTION_MOVE -> {
                    if (dragState == DragState.ZOOM) {
                        return@setOnTouchListener res
                    }

                    val dx = event.rawX - touchStartRawX
                    val dy = event.rawY - touchStartRawY
                    if (dragState == DragState.NONE) {
                        // Ignore small changes to allow user zoom!
                        val slop = ViewConfiguration.get(context).scaledTouchSlop
                        if (dx < slop && dy < slop)
                            return@setOnTouchListener true
                    }
                    dragState = DragState.DRAG

                    val newX = initialX + dx
                    val newY = initialY + dy
                    v.x = newX
                    v.y = newY

                    renderAnimatedNft()

                    val distance = sqrt(dx * dx + dy * dy)
                    val maxDistance = centerX
                    val newAlpha = 1f - (distance / maxDistance).coerceIn(0f, 1f)
                    overlayView.alpha = newAlpha
                    true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragState == DragState.ZOOM) {
                        dragState = DragState.NONE
                        if (zoomableController.scaleFactor < 1.1f)
                            resetZoom()
                        return@setOnTouchListener res
                    }
                    dragState = DragState.NONE

                    if (overlayView.alpha < 0.7f) {
                        onBackPressed()
                        return@setOnTouchListener true
                    }
                    overlayView.animate()
                        .alpha(1f)
                        .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                        .setInterpolator(AccelerateDecelerateInterpolator())
                        .start()
                    v.animate()
                        .x(initialX)
                        .y(initialY)
                        .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                        .setInterpolator(AccelerateDecelerateInterpolator())
                        .start()
                    animationView?.animate()
                        ?.x(initialX)
                        ?.y(initialY)
                        ?.setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                        ?.setInterpolator(AccelerateDecelerateInterpolator())?.start()
                    true
                }

                else -> false
            }
        }

        if (animationView != null)
            setZoomingEnabled(false) // For now, lock pinch zoom for animations
    }

    private val viewWidth: Int by lazy {
        (navigationController?.parent as View).width
    }
    private val viewHeight: Int by lazy {
        (navigationController?.parent as View).height
    }

    val imageSize: Int by lazy {
        min(viewWidth, viewHeight)
    }

    val initialScaleX: Float by lazy {
        (initialPosition.right - initialPosition.left) / imageSize.toFloat()
    }
    val initialScaleY: Float by lazy {
        (initialPosition.bottom - initialPosition.top) / imageSize.toFloat()
    }

    override fun setupViews() {
        super.setupViews()

        view.addView(overlayView, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(imageView, ConstraintLayout.LayoutParams(imageSize, imageSize))
    }

    // Animate image in
    fun startTransition() {
        view.lockView()
        if (animationView != null && animationView.parent == null) {
            animationView.pivotX = 0f
            animationView.pivotY = 0f
            view.addView(animationView, ConstraintLayout.LayoutParams(imageSize, imageSize))
        }
        imageView.alpha = 1f
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animation ->
                val animatedFraction = animation.animatedFraction
                overlayView.alpha = animatedFraction
                imageView.apply {
                    translationX =
                        lerp(
                            initialPosition.left.toFloat(),
                            (viewWidth - imageSize).toFloat() / 2,
                            animatedFraction
                        )
                    translationY =
                        lerp(
                            initialPosition.top.toFloat(),
                            (viewHeight - imageSize).toFloat() / 2,
                            animatedFraction
                        )
                    scaleX = lerp(
                        initialScaleX,
                        1f,
                        animatedFraction
                    )
                    scaleY = lerp(
                        initialScaleY,
                        1f,
                        animatedFraction
                    )
                    hierarchy.roundingParams =
                        RoundingParams.fromCornersRadius(initialRounding * (1 - animatedFraction))
                }
                renderAnimatedNft()
            }
            doOnEnd {
                imageView.updateLayoutParams {
                    width = viewWidth
                    height = viewHeight
                    imageView.translationX = 0f
                    imageView.translationY = 0f
                }
                animationView?.updateLayoutParams {
                    width = viewWidth
                    height = viewHeight
                    animationView.translationX = 0f
                    animationView.translationY = 0f
                }
                view.unlockView()
            }
            start()
        }
    }

    override fun onBackPressed(): Boolean {
        view.lockView()
        if (imageView.zoomableController.scaleFactor > 1f)
            imageView.resetZoom()
        val startX = imageView.x + (viewWidth - imageSize).toFloat() / 2
        val startY = imageView.y + (viewHeight - imageSize).toFloat() / 2
        val startAlpha = overlayView.alpha
        imageView.updateLayoutParams {
            width = imageSize
            height = imageSize
        }
        animationView?.updateLayoutParams {
            width = imageSize
            height = imageSize
        }
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animation ->
                val animatedFraction = animation.animatedFraction
                overlayView.alpha = lerp(startAlpha, 0f, animatedFraction)
                imageView.apply {
                    translationX =
                        lerp(
                            startX,
                            initialPosition.left.toFloat(),
                            animatedFraction
                        )
                    translationY =
                        lerp(
                            startY,
                            initialPosition.top.toFloat(),
                            animatedFraction
                        )
                    scaleX = lerp(
                        1f,
                        initialScaleX,
                        animatedFraction
                    )
                    scaleY = lerp(
                        1f,
                        initialScaleY,
                        animatedFraction
                    )
                    hierarchy.roundingParams =
                        RoundingParams.fromCornersRadius(initialRounding * animatedFraction)
                }
                renderAnimatedNft()
            }
            doOnEnd {
                window?.dismissLastNav(animated = false)
                animationView?.resetPivot()
                view.removeView(animationView)
                onPreviewDismissed()
            }
            start()
        }
        return false
    }

    private fun renderAnimatedNft() {
        if (animationView?.parent != view)
            return
        animationView.apply {
            setBackgroundColor(
                Color.TRANSPARENT,
                imageView.hierarchy.roundingParams?.cornersRadii?.get(0) ?: 0f,
                true
            )
            scaleX = imageView.scaleX
            scaleY = imageView.scaleY
            translationX = imageView.translationX
            translationY = imageView.translationY
        }
    }
}
