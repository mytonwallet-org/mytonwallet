package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.view.View
import android.widget.HorizontalScrollView

@SuppressLint("ViewConstructor")
class AutoScaleContainerView(
    private val contentView: View
) : HorizontalScrollView(contentView.context) {

    //private var marqueeAnimator: ValueAnimator? = null

    init {
        /*setFadingEdgeLength(48.dp)
        overScrollMode = OVER_SCROLL_NEVER
        clipChildren = false*/
        isHorizontalScrollBarEnabled = false

        contentView.layoutParams =
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        removeAllViews()
        addView(contentView)
        contentView.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            val oldWidth = oldRight - oldLeft
            val newWidth = right - left
            if (newWidth != oldWidth) {
                tryStartMarquee()
            }
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        tryStartMarquee()
    }

    private fun tryStartMarquee() {
        val child = contentView
        val scrollWidth = child.width
        val visibleWidth = width

        if (scrollWidth > visibleWidth) {
            contentView.pivotX = 0f
            contentView.pivotY = height.toFloat()
            contentView.scaleX = visibleWidth / scrollWidth.toFloat()
            contentView.scaleY = contentView.scaleX
            /*startMarqueeAnimation(scrollWidth - visibleWidth)
            isHorizontalFadingEdgeEnabled = true*/
        } else {
            contentView.scaleX = 1f
            contentView.scaleY = 1f
        }
    }

    /*private fun startMarqueeAnimation(distance: Int) {
        stopMarqueeAnimation()

        marqueeAnimator = ValueAnimator.ofInt(0, distance).apply {
            duration = 5000L
            interpolator = LinearInterpolator()
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationRepeat(animation: Animator) {
                    animation.pause()
                    postDelayed({ animation.resume() }, 1000)
                }
            })

            addUpdateListener { animation ->
                val scrollPos = animation.animatedValue as Int
                scrollTo(scrollPos, 0)
            }
            start()
        }
    }

    fun stopMarqueeAnimation() {
        marqueeAnimator?.cancel()
        marqueeAnimator = null
        isHorizontalFadingEdgeEnabled = false
        scrollTo(0, 0)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (marqueeAnimator == null)
            tryStartMarquee()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        // Do not stop animation if view's parent is changed in a moment!
        Handler(Looper.getMainLooper()).post {
            if (parent == null)
                stopMarqueeAnimation()
        }
    }*/
}
