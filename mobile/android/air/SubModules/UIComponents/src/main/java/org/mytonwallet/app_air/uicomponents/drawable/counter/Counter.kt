package org.mytonwallet.app_air.uicomponents.drawable.counter

import android.graphics.Canvas
import android.text.TextPaint
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animator.CounterAnimator
import me.vkryl.android.animator.ListAnimator
import me.vkryl.android.animatorx.BoolAnimator
import me.vkryl.android.animatorx.BoolAnimatorListener
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import kotlin.math.max
import kotlin.math.min

// TODO:: Fix known issue with RTL language
//  For now, avoid using this in RTL languages by either using a normal TextView
//  or conditionally using it only in LTR languages
class Counter(
    private val paint: TextPaint,
    private val callback: Callback?,
    private val isReverse: Boolean = false,
    duration: Long = 180L
) : CounterAnimator.Callback<CounterTextPart>, BoolAnimatorListener {
    private val counter = CounterAnimator(this, duration, isReverse)
    private val isHidden =
        BoolAnimator(duration, AnimatorUtils.DECELERATE_INTERPOLATOR, false, this)

    interface Callback {
        fun onCounterAppearanceChanged(counter: Counter, sizeChanged: Boolean)
        fun onCounterRequiredWidthChanged(counter: Counter) {}
        fun needAnimateChanges(counter: Counter): Boolean {
            return true; }
    }

    fun getVisibleWidth(): Float {
        return counter.width
    }

    fun getWidth(): Float {
        return counter.width * visibility
    }


    private var lastRequiredWidth = 0

    var requiredWidth: Int = 0
        private set

    var targetWidth: Int = 0
        private set

    val visibility: Float
        get() = 1f - isHidden.floatValue

    private fun updateSizes() {
        var targetTotalWidth = 0
        var left = Float.POSITIVE_INFINITY
        var right = Float.NEGATIVE_INFINITY
        var count = 0

        for (entry in counter) {
            count++
            left = min(left, entry.rectF.left)
            right = max(right, entry.rectF.right)
            if (entry.isAffectingList) {
                targetTotalWidth += entry.item.width
            }
        }

        requiredWidth = if (count > 0) {
            (right - left).ceilToInt()
        } else 0
        targetWidth = targetTotalWidth
        if (isHidden.value) {
            targetWidth = 0
            if (isHidden.floatValue == 1f) {
                requiredWidth = 0
            }
        }

        if (requiredWidth != lastRequiredWidth) {
            lastRequiredWidth = requiredWidth
            callback?.onCounterRequiredWidthChanged(this)
        }
    }

    private var count = 1L

    fun setValue(text: String?, animated: Boolean) {
        var animateChanges = animated
        if (animateChanges && (callback == null || !callback.needAnimateChanges(this))) {
            animateChanges = false
        }

        if (!text.isNullOrEmpty()) {
            counter.setCounter(count++, text, animateChanges && isHidden.floatValue != 1f)
        }
        isHidden.changeValue(text.isNullOrEmpty(), animateChanges)

        updateSizes()
    }

    fun draw(c: Canvas, x: Float, y: Float, alpha: Float) {
        for (entry in counter) {
            val textStartX = if (isReverse) {
                Math.round(x + getVisibleWidth() - entry.rectF.right)
            } else {
                Math.round(x + entry.rectF.left)
            }

            val textEndX = textStartX + entry.item.width
            val startY = Math.round(y + entry.item.height * .75f * entry.item.verticalPosition)
            entry.item.text.draw(
                c,
                textStartX,
                textEndX,
                0,
                startY,
                alpha * visibility * entry.visibility
            )
        }
    }

    // interfaces

    private var lastWidth = 0f

    fun invalidate() {
        val width: Float = getVisibleWidth()
        val changed = lastWidth != width
        lastWidth = width

        callback?.onCounterAppearanceChanged(this, changed)
    }

    override fun onItemsChanged(animator: CounterAnimator<*>?) {
        invalidate()
    }

    override fun onFinishMetadataAnimation(animator: ListAnimator<*>?, applyFuture: Boolean) {
        updateSizes()
        invalidate()
    }

    override fun onCreateTextDrawable(text: String, start: Int): CounterTextPart {
        return CounterTextPartImpl(text, paint)
    }


    override fun onAnimationUpdate(
        state: BoolAnimator.State,
        animatedValue: Float,
        stateChanged: Boolean,
        prevState: BoolAnimator.State
    ) {
        invalidate()
    }

    override fun onAnimationFinish(finalState: BoolAnimator.State, byAnimationEnd: Boolean) {
        super.onAnimationFinish(finalState, byAnimationEnd)
        updateSizes()
    }
}
