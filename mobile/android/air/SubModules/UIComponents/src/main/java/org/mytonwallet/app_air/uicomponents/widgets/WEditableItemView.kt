package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.Drawable
import android.text.TextPaint
import android.widget.FrameLayout
import androidx.core.view.children
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animator.ListAnimator.Measurable
import me.vkryl.android.animator.ReplaceAnimator
import me.vkryl.android.animatorx.BoolAnimator
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.helpers.ViewHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import kotlin.math.max
import kotlin.math.roundToInt

class WEditableItemView(context: Context) : FrameLayout(context), ReplaceAnimator.Callback,
    WThemedView {
    private class Item(
        val text: String,
        val textWidth: Int,
    ) : Measurable {
        override fun getWidth(): Int {
            return textWidth
        }

        override fun getHeight(): Int {
            return 0
        }
    }

    private val baseCurrLeftPadding = 12.dp
    private val baseCurrWidth = baseCurrLeftPadding + 9.dp
    private val baseCurrIndicatorText = LocaleController.getString("in")

    private val shapeDrawable = ViewHelpers.roundedShapeDrawable(0, 18f.dp)
    var drawable: Drawable? = null
        set(value) {
            field = value
            value?.setTint(WColor.SecondaryText.color)
        }

    private val dPaddingLeft: Int
        get() = if (LocaleController.isRTL) {
            drawable?.let { it.minimumWidth + 4.dp } ?: 12.dp
        } else {
            12.dp
        }
    private val dPaddingRight: Int
        get() = if (LocaleController.isRTL) {
            12.dp
        } else {
            drawable?.let { it.minimumWidth + 4.dp } ?: 12.dp
        }

    private val animator = ReplaceAnimator<Item>(
        this,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        AnimationConstants.VERY_QUICK_ANIMATION
    )

    private val currencyIndicatorAnimatedWidth get() = (currencyIndicatorVisible.floatValue * baseCurrWidth)
    private val currencyIndicatorVisible = BoolAnimator(
        220L,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        false,
    ) { _, _, _, _ ->
        prepare()
        invalidate()
    }


    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = WFont.Medium.typeface
        textSize = 16f.dp
    }

    private val baseCurrIndicatorPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = WFont.Regular.typeface
        textSize = 14f.dp
    }

    init {
        updateTheme()
    }

    override fun draw(canvas: Canvas) {
        shapeDrawable.draw(canvas)
        super.draw(canvas)
    }

    override fun dispatchDraw(canvas: Canvas) {
        val baseline = measuredHeight / 2f + 5.dp
        if (currencyIndicatorVisible.floatValue > 0f) {
            baseCurrIndicatorPaint.alpha = (currencyIndicatorVisible.floatValue * 255f).roundToInt()
            val xBaseCurr = if (LocaleController.isRTL) {
                animator.metadata.totalWidth + currencyIndicatorAnimatedWidth + dPaddingLeft + dPaddingRight - baseCurrLeftPadding - baseCurrIndicatorPaint.measureText(
                    baseCurrIndicatorText
                )
            } else {
                measuredWidth - animator.metadata.totalWidth - currencyIndicatorAnimatedWidth - dPaddingLeft - dPaddingRight + baseCurrLeftPadding
            }
            canvas.drawText(baseCurrIndicatorText, xBaseCurr, baseline, baseCurrIndicatorPaint)
        }

        super.dispatchDraw(canvas)
        animator.forEach {
            var offset = 12.dp * (1f - it.visibility)
            if (it.isAffectingList) {
                offset *= -1
            }

            val x = if (LocaleController.isRTL) {
                dPaddingLeft.toFloat()
            } else {
                measuredWidth - it.item.width - dPaddingRight.toFloat()
            }
            val y = baseline + offset

            textPaint.alpha = (it.visibility * 255).roundToInt()
            canvas.drawText(it.item.text, x, y, textPaint)
        }
        drawable?.draw(canvas)
    }

    fun setText(text: String) {
        animator.replace(
            Item(
                text,
                textPaint.measureText(text).roundToInt(),
            ), !animator.isEmpty && isAttachedToWindow
        )
        updateViewsAttached()
    }

    override fun updateTheme() {
        drawable?.setTint(WColor.SecondaryText.color)
        baseCurrIndicatorPaint.color = WColor.SecondaryText.color
        textPaint.color = WColor.PrimaryText.color
        shapeDrawable.paint.color = WColor.TrinaryBackground.color

        background = ViewHelpers.roundedRippleDrawable(
            null,
            WColor.backgroundRippleColor,
            18f.dp
        )
    }

    private fun calcMeasuredWidth(): Int {
        var width = 0
        animator.forEach { entry ->
            if (!entry.isJunk) {
                width = max(width, entry.item.width)
            }
        }
        width += dPaddingLeft + dPaddingRight + (if (currencyIndicatorVisible.value) baseCurrWidth else 0)
        return width
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(calcMeasuredWidth().exactly, 36.dp.exactly)
        prepare()
    }

    private fun prepare() {
        if (LocaleController.isRTL) {
            val shapeRight =
                animator.metadata.totalWidth.roundToInt() + currencyIndicatorAnimatedWidth.roundToInt() + dPaddingLeft + dPaddingRight
            shapeDrawable.setBounds(0, 0, shapeRight, measuredHeight)
            drawable?.let {
                val w = it.minimumWidth
                val h = it.minimumHeight
                val x = 4.dp
                val y = (measuredHeight - h) / 2
                it.setBounds(x, y, x + w, y + h)
            }
        } else {
            val shapeLeft =
                measuredWidth - animator.metadata.totalWidth.roundToInt() - currencyIndicatorAnimatedWidth.roundToInt() - dPaddingLeft - dPaddingRight
            shapeDrawable.setBounds(shapeLeft, 0, measuredWidth, measuredHeight)
            drawable?.let {
                val w = it.minimumWidth
                val h = it.minimumHeight
                val x = measuredWidth - w - 4.dp
                val y = (measuredHeight - h) / 2
                it.setBounds(x, y, x + w, y + h)
            }
        }

        animator.forEach {
            var offset = 12.dp * (1f - it.visibility)
            if (it.isAffectingList) {
                offset *= -1
            }
        }
    }

    private fun updateViewsAttached() {
        val attachedViews = mutableSetOf<WCustomImageView>()

        children.forEach { v ->
            (v as? WCustomImageView)?.let {
                attachedViews.add(it)
            }
        }

        attachedViews.forEach {
            removeView(it)
        }

        requestLayout()
    }

    override fun onItemChanged(animator: ReplaceAnimator<*>?) {
        prepare()
        invalidate()
    }

    override fun onForceApplyChanges(animator: ReplaceAnimator<*>?) {
        updateViewsAttached()
    }

    override fun onPrepareMetadataAnimation(animator: ReplaceAnimator<*>?) {
        updateViewsAttached()
    }

    override fun onFinishMetadataAnimation(animator: ReplaceAnimator<*>?, applyFuture: Boolean) {
        updateViewsAttached()
    }
}
