package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.view.View
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.AnimationConstants

@SuppressLint("ViewConstructor")
class WGradientMaskView(child: View) : FrameLayout(child.context) {

    private var gradientColors: IntArray = intArrayOf()
    private var _width = 0
    private var _height = 0
    private var _additionalWidth = 0f
    private var segments = 3

    fun setupColors(colors: IntArray) {
        this.gradientColors = colors
        updateGradient()
    }

    fun setupLayout(
        width: Int? = null,
        height: Int? = null,
        parentWidth: Int? = null
    ) {
        this._width = width ?: _width
        this._height = height ?: _height
        this._additionalWidth = parentWidth?.let {
            (parentWidth - _width).coerceAtLeast(0) / 2f
        } ?: _additionalWidth
        updateGradient()
    }

    var isLoading: Boolean = true
        set(value) {
            field = value
            if (value) {
                startMasking()
            } else {
                stopMasking()
            }
        }

    private val animator: ValueAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = AnimationConstants.SLOW_ANIMATION
        repeatMode = ValueAnimator.RESTART
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()

        addUpdateListener { animation ->
            val progress = animation.animatedValue as Float
            updateShader(progress)
        }
    }

    private var linearGradient: LinearGradient? = null
    private val gradientMatrix = Matrix()
    private val maskPaint = Paint().apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
    }
    private val gradientPaint = Paint()
    private var isAnimating = false
    private var fadeAlpha = 0f
    private var fadeAnimator: ValueAnimator? = null

    init {
        addView(child)
        clipChildren = false
        clipToPadding = false
        setWillNotDraw(false)
    }

    fun updateGradient() {
        if (!isAnimating)
            return
        if (_width <= 0 || _height <= 0 || gradientColors.size != segments) return

        val positions = FloatArray(segments) { i ->
            i.toFloat() / (segments - 1)
        }

        animator.duration = AnimationConstants.SLOW_ANIMATION * segments

        linearGradient = LinearGradient(
            0f, 0f,
            _width.toFloat(), _height.toFloat(),
            gradientColors,
            positions,
            Shader.TileMode.MIRROR
        )

        gradientPaint.shader = linearGradient
    }

    private fun updateShader(progress: Float) {
        gradientMatrix.setTranslate(progress * _width, 0f)
        linearGradient?.setLocalMatrix(gradientMatrix)
        invalidate()
    }

    fun startMasking() {
        if (!isAnimating) {
            isAnimating = true
            updateGradient()

            fadeAnimator?.cancel()
            fadeAnimator = ValueAnimator.ofFloat(fadeAlpha, 1f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION
                addUpdateListener { animation ->
                    fadeAlpha = animation.animatedValue as Float
                    invalidate()
                }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        animator.start()
                    }
                })
                start()
            }
        }
    }

    fun stopMasking() {
        if (isAnimating) {
            fadeAnimator?.cancel()
            fadeAnimator = ValueAnimator.ofFloat(fadeAlpha, 0f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION
                addUpdateListener { animation ->
                    fadeAlpha = animation.animatedValue as Float
                    invalidate()
                }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        isAnimating = false
                        animator.cancel()
                        gradientPaint.shader = null
                        invalidate()
                    }
                })
                start()
            }
        }
    }

    override fun dispatchDraw(canvas: Canvas) {
        if (!isAnimating || fadeAlpha <= 0f) {
            super.dispatchDraw(canvas)
            return
        }

        // Draw main content
        if (fadeAlpha < 1) {
            val previousAlpha = alpha
            alpha = 1 - fadeAlpha
            super.dispatchDraw(canvas)
            alpha = previousAlpha
        }

        val child = getChildAt(0)
        val left = -_additionalWidth
        val top = -child.height.toFloat()
        val right = (width + _additionalWidth)
        val bottom = (height + child.height).toFloat()

        val saveCount = canvas.saveLayer(left, top, right, bottom, null)
        try {
            gradientPaint.alpha = (255 * fadeAlpha).toInt()
            canvas.drawRect(left, top, right, bottom, gradientPaint)

            val childSave = canvas.saveLayer(left, top, right, bottom, maskPaint)
            super.dispatchDraw(canvas)
            canvas.restoreToCount(childSave)
        } finally {
            canvas.restoreToCount(saveCount)
        }
    }

    fun onDestroy() {
        animator.cancel()
        fadeAnimator?.cancel()
        fadeAnimator = null
    }
}
