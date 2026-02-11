package org.mytonwallet.app_air.uicomponents.commonViews

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.core.view.isGone
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class ReversedCornerView(
    context: Context,
    private val initialConfig: Config,
) : BaseReversedCornerView(context), WThemedView {

    data class Config(
        val shouldBlur: Boolean = true,
        val blurRootView: ViewGroup? = null,
        val forceSeparator: Boolean = false,
        val showSeparator: Boolean = true,
        val overrideBackgroundColor: WColor? = null
    )

    init {
        id = generateViewId()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            requestedFrameRate = REQUESTED_FRAME_RATE_CATEGORY_LOW
        }
    }

    private val backgroundView = View(context).apply {
        setBackgroundColor(
            initialConfig.overrideBackgroundColor?.color ?: WColor.SecondaryBackground.color
        )
    }

    private val blurryBackgroundView =
        if (DevicePerformanceClassifier.isHighClass && initialConfig.shouldBlur) initialConfig.blurRootView?.let {
            WBlurryBackgroundView(context, WBlurryBackgroundView.Side.BOTTOM).apply {
                setupWith(it)
                setBackgroundVisible(visible = true, animated = false)
            }
        } else null

    private val path = Path()
    private val cornerPath = Path()
    private val rectF = RectF()

    private var lastWidth = -1
    private var lastHeight = -1

    var overrideRadius: Float? = null
    var cornerRadius: Float = ViewConstants.TOOLBAR_RADIUS.dp
        private set

    private var radii: FloatArray =
        floatArrayOf(cornerRadius, cornerRadius, cornerRadius, cornerRadius, 0f, 0f, 0f, 0f)

    private var isBackgroundVisible = true
    private var _desiredShowSeparator: Boolean? = null
    private var showSeparator: Boolean? = null

    var isPlaying = true
        private set
    private var radiusAnimator: ValueAnimator? = null

    private var overlayColor: Int? = null
    fun setBlurOverlayColor(color: Int?) {
        overlayColor = color

        blurryBackgroundView?.setOverlayColor(color ?: Color.TRANSPARENT)
        backgroundView.setBackgroundColor(color ?: WColor.SecondaryBackground.color)
        postInvalidateOnAnimation()
    }

    fun setBackgroundVisible(visible: Boolean, animated: Boolean = true) {
        if (visible == isBackgroundVisible) return
        isBackgroundVisible = visible
        if (animated) {
            if (visible)
                fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
            else
                fadeOut(AnimationConstants.VERY_QUICK_ANIMATION)
        } else {
            alpha = if (visible) 1f else 0f
        }
    }

    fun setShowSeparator(visible: Boolean) {
        if (showSeparator == visible) return
        showSeparator = visible
        _desiredShowSeparator = visible
        postInvalidateOnAnimation()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (backgroundView.parent == null) {
            addView(backgroundView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
            blurryBackgroundView?.let { addView(it, LayoutParams(MATCH_PARENT, MATCH_PARENT)) }
        }
        pauseBlurring(false)
    }

    override fun dispatchDraw(canvas: Canvas) {
        val width = width
        val height = height

        if (width <= 0 || height <= 0 || (alpha == 0f && visibility != VISIBLE)) return

        if (width != lastWidth || height != lastHeight) {
            lastWidth = width
            lastHeight = height
            pathDirty = true
        }

        if (pathDirty) {
            updatePath(width.toFloat(), height.toFloat())
            pathDirty = false
        }

        drawChildren(canvas)
    }

    private fun updatePath(width: Float, height: Float) {
        path.reset()
        cornerPath.reset()
        path.moveTo(0f, 0f)
        path.lineTo(width, 0f)
        path.lineTo(width, height)
        path.lineTo(0f, height)
        path.close()

        rectF.set(
            horizontalPadding,
            height - cornerRadius + 0.5f,
            width - horizontalPadding,
            height
        )
        cornerPath.addRoundRect(rectF, radii, Path.Direction.CCW)

        path.op(cornerPath, Path.Op.DIFFERENCE)
    }

    private fun drawChildren(canvas: Canvas) {
        canvas.save()
        canvas.clipPath(path)
        super.dispatchDraw(canvas)
        canvas.restore()
    }

    fun animateRadius(from: Float, to: Float) {
        if (from == to) return
        radiusAnimator?.cancel()
        radiusAnimator = ValueAnimator.ofFloat(from, to).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()

            addUpdateListener { animator ->
                cornerRadius = animator.animatedValue as Float
                radii = floatArrayOf(
                    cornerRadius, cornerRadius, cornerRadius, cornerRadius,
                    0f, 0f, 0f, 0f
                )
                pathDirty = true
                translationY =
                    (if (to > from) 1f else -1f) * ((animatedFraction - 1) * 24.dp).roundToInt()

                postInvalidateOnAnimation()
            }

            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    radiusAnimator = null
                }
            })

            start()
        }
    }

    override fun updateTheme() {
        updateRadius()

        val bgColor = overlayColor
            ?: initialConfig.overrideBackgroundColor?.color
            ?: WColor.SecondaryBackground.color
        backgroundView.setBackgroundColor(bgColor)

        blurryBackgroundView?.updateTheme()

        if (!isPlaying) {
            resumeBlurring()
            post { pauseBlurring(showSeparator == true) }
        } else {
            postInvalidateOnAnimation()
        }
    }

    fun setRadius(radius: Float?) {
        overrideRadius = radius
        updateRadius()
    }

    private fun updateRadius() {
        if (cornerRadius == (overrideRadius ?: ViewConstants.TOOLBAR_RADIUS.dp))
            return
        cornerRadius = overrideRadius ?: ViewConstants.TOOLBAR_RADIUS.dp
        radii = floatArrayOf(cornerRadius, cornerRadius, cornerRadius, cornerRadius, 0f, 0f, 0f, 0f)
        pathDirty = true
    }

    fun pauseBlurring(keepBlurAsImage: Boolean) {
        if (!isPlaying) return
        isPlaying = false
        blurryBackgroundView?.apply {
            blurryBackgroundView.pauseBlurring()
            isGone = !keepBlurAsImage
            alpha = if (keepBlurAsImage) 1f else 0f
            backgroundView.isVisible = true
            backgroundView.alpha = 1f
        }
        showSeparator = keepBlurAsImage
        postInvalidateOnAnimation()
    }

    fun resumeBlurring() {
        if (isPlaying) return
        isPlaying = true
        blurryBackgroundView?.apply {
            alpha = 1f
            visibility = VISIBLE
            blurryBackgroundView.resumeBlurring()
            backgroundView.isGone = true
        } ?: {
            // No blurs available, show background
            backgroundView.apply {
                alpha = 1f
                visibility = VISIBLE
            }
        }
        showSeparator = _desiredShowSeparator
        postInvalidateOnAnimation()
    }

    private var currentAlpha = 1f
    fun setBlurAlpha(alpha: Float) {
        val targetAlpha = 1f.coerceAtMost(alpha * 10)
        if (currentAlpha == targetAlpha) return
        currentAlpha = targetAlpha
        if (blurryBackgroundView == null) {
            // No blurs available
            backgroundView.alpha = targetAlpha
        } else {
            // Combine blur and normal background
            if (blurryBackgroundView.alpha == targetAlpha) return
            blurryBackgroundView.alpha = targetAlpha
            backgroundView.alpha = 1 - targetAlpha
        }
        postInvalidateOnAnimation()
    }
}
