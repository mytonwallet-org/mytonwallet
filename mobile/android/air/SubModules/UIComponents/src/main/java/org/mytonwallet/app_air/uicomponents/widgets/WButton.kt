package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.Drawable
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import android.view.View
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animator.ListAnimator.Measurable
import me.vkryl.android.animator.ReplaceAnimator
import me.vkryl.core.alphaColor
import me.vkryl.core.fromTo
import me.vkryl.core.fromToArgb
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.getCenterAlignBaseline
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt
import kotlin.math.min
import kotlin.math.roundToInt

class WButton(context: Context) : View(context), WThemedView {
    private val ripple = WRippleDrawable.create(120f.dp)
    private val progressDrawable = RoundProgressDrawable()
    var buttonHeight = 50.dp
    var clickableError = false

    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = WFont.Medium.typeface
        textSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            16f,
            context.resources.displayMetrics
        )
    }

    fun measureText(txt: String): Float {
        return textPaint.measureText(txt)
    }

    sealed class Type {

        data object Primary : Type()
        data object Destructive : Type()
        data class Secondary(
            val withBackground: Boolean = false
        ) : Type()

        companion object {
            val PRIMARY: Type = Primary
            val DESTRUCTIVE: Type = Destructive
            val SECONDARY: Type = Secondary()
            val SECONDARY_WITH_BACKGROUND: Type = Secondary(withBackground = true)
        }
    }

    data class Item(
        val maxWidth: Int,
        val text: String,
        val layout: StaticLayout
    ) : Measurable {
        override fun getWidth(): Int {
            return layout.width
        }

        override fun getHeight(): Int {
            return 0
        }
    }

    var type = Type.PRIMARY
        set(value) {
            field = value
            updateColors()
        }

    private val animator = ReplaceAnimator<Item>(
        { invalidate() },
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        AnimationConstants.VERY_QUICK_ANIMATION
    )

    private var isLoadingAnimator = me.vkryl.android.animatorx.BoolAnimator(
        AnimationConstants.VERY_VERY_QUICK_ANIMATION,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        initialValue = false
    ) { _, _, _, _ ->
        updateColors()
    }

    private var isErrorAnimator = me.vkryl.android.animatorx.BoolAnimator(
        AnimationConstants.VERY_VERY_QUICK_ANIMATION,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        initialValue = false
    ) { _, _, _, _ ->
        updateColors()
    }

    private var isEnabledAnimator = me.vkryl.android.animatorx.BoolAnimator(
        AnimationConstants.VERY_VERY_QUICK_ANIMATION,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        initialValue = true
    ) { _, _, _, _ ->
        updateColors()
    }

    constructor(context: Context, type: Type) : this(context) {
        this.type = type
    }

    init {
        background = ripple
        progressDrawable.callback = this
        updateTheme()
        if (id == NO_ID) {
            id = generateViewId()
        }
    }

    var isLoading: Boolean
        get() = isLoadingAnimator.value
        set(value) {
            setLoading(value, true)
        }

    var isError: Boolean
        get() = isErrorAnimator.value
        set(value) {
            setError(value, true)
        }

    fun setLoading(loading: Boolean, isAnimated: Boolean = true) {
        isLoadingAnimator.changeValue(loading, isAnimated && isAttachedToWindow)
        checkEnabled()
    }

    fun setError(error: Boolean, isAnimated: Boolean = true) {
        isErrorAnimator.changeValue(error, isAnimated && isAttachedToWindow)
        checkEnabled()
    }

    override fun setEnabled(enabled: Boolean) {
        setEnabled(enabled, true)
    }

    fun setEnabled(enabled: Boolean, isAnimated: Boolean = true) {
        isEnabledAnimator.changeValue(enabled, isAnimated && isAttachedToWindow)
        checkEnabled()
    }

    private fun checkEnabled() {
        super.setEnabled(isEnabledAnimator.value && !isLoadingAnimator.value && (!isErrorAnimator.value || clickableError))
    }

    override fun verifyDrawable(who: Drawable): Boolean {
        if (who == progressDrawable && isLoadingAnimator.floatValue > 0) {
            return true
        }

        return super.verifyDrawable(who)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val scale = 1f - isLoadingAnimator.floatValue
        val needProgress = isLoadingAnimator.floatValue > 0

        if (needProgress) {
            canvas.save()
            canvas.scale(scale, scale, measuredWidth / 2f, measuredHeight / 2f)
        }

        val baselineY = textPaint.fontMetrics.getCenterAlignBaseline(measuredHeight / 2f)
        animator.forEach {
            var offset = 14.dp * (1f - it.visibility)
            if (it.isAffectingList) {
                offset *= -1
            }

            val x = (measuredWidth - it.item.width) / 2f
            val y = baselineY + offset - it.item.layout.getLineBaseline(0)

            val alpha = (scale * it.visibility * 255).roundToInt()
            canvas.saveLayerAlpha(0f, 0f, measuredWidth.toFloat(), measuredHeight.toFloat(), alpha)

            val s = fromTo(0.8f, 1f, it.visibility)
            canvas.scale(s, s, measuredWidth / 2f, measuredHeight / 2f)

            canvas.translate(x, y)
            it.item.layout.paint.color = textPaint.color
            it.item.layout.draw(canvas)

            canvas.restore()
        }

        if (needProgress) {
            canvas.restore()

            canvas.save()
            canvas.scale(1f - scale, 1f - scale, measuredWidth / 2f, measuredHeight / 2f)
            progressDrawable.draw(canvas)
            canvas.restore()
        }
    }

    var text: CharSequence?
        set(value) {
            setText(value ?: "", true)
        }
        get() = animator.singleton()?.item?.text

    fun setText(text: CharSequence, isAnimated: Boolean = true) {
        if (animator.singleton()?.item?.text == text) {
            return
        }

        val maxWidth = measuredWidth - paddingLeft - paddingRight
        val staticLayout = StaticLayout.Builder.obtain(
            text, 0, text.length, textPaint, Int.MAX_VALUE
        ).build()

        val textWidth = 0.until(staticLayout.lineCount).maxOf { i ->
            staticLayout.getLineWidth(i)
        }
        val layout = StaticLayout(
            text, textPaint, (textWidth).ceilToInt(),
            Layout.Alignment.ALIGN_NORMAL, 1f, 0f, false
        )

        animator.replace(
            Item(maxWidth, text = text.toString(), layout),
            isAnimated && !animator.isEmpty && isAttachedToWindow && isLoadingAnimator.floatValue != 1f
        )
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, buttonHeight.exactly)

        val s = progressDrawable.minimumWidth
        val x = (measuredWidth - s) / 2
        val y = (measuredHeight - s) / 2
        progressDrawable.setBounds(x, y, x + s, y + s)

        rebuild()
    }

    override fun setPadding(left: Int, top: Int, right: Int, bottom: Int) {
        super.setPadding(left, top, right, bottom)
        rebuild()
    }

    private fun rebuild() {
        val oldItem = animator.singleton()?.item ?: return
        val maxWidth = measuredWidth - paddingLeft - paddingRight
        if (oldItem.maxWidth == maxWidth) {
            return
        }

        val textWidth = min((textPaint.measureText(oldItem.text)).ceilToInt(), maxWidth)
        if (oldItem.width == textWidth) {
            return
        }

        val layout = StaticLayout(
            oldItem.text, textPaint, textWidth,
            Layout.Alignment.ALIGN_NORMAL, 1f, 0f, false
        )

        animator.replace(Item(maxWidth, text = oldItem.text, layout), false)
    }

    override fun updateTheme() {
        updateColors()
    }

    override val isTinted = true
    private fun updateColors() {
        val tint = if (type == Type.DESTRUCTIVE) WColor.Error.color else WColor.Tint.color
        val tintColor = fromToArgb(
            alphaColor(
                0.5f,
                tint
            ),
            tint,
            isEnabledAnimator.floatValue
        )
        val type = type

        val errorBackgroundColor = when (type) {
            is Type.Primary, Type.Destructive -> fromToArgb(
                WColor.Error.color,
                WColor.Background.color,
                if (isEnabledAnimator.value && clickableError) 0f else 0.5f
            )

            is Type.Secondary -> if (type.withBackground) {
                alphaColor(.1f, fromToArgb(WColor.Error.color, WColor.Background.color, 0.5f))
            } else 0
        }

        val errorTextColor = when (type) {
            is Type.Primary, Type.Destructive -> WColor.TextOnTint.color
            is Type.Secondary -> 0
        }

        val backgroundColor = fromToArgb(
            when (type) {
                is Type.Primary, Type.Destructive -> tintColor
                is Type.Secondary -> if (type.withBackground) {
                    alphaColor(.1f, tintColor)
                } else 0
            }, errorBackgroundColor, isErrorAnimator.floatValue
        )

        val textColor = fromToArgb(
            when (type) {
                is Type.Primary, Type.Destructive -> WColor.TextOnTint.color
                is Type.Secondary -> tintColor
            }, errorTextColor, isErrorAnimator.floatValue
        )

        val rippleColor = when (type) {
            is Type.Primary, Type.Destructive -> WColor.backgroundRippleColor
            is Type.Secondary -> WColor.tintRippleColor
        }

        ripple.rippleColor = rippleColor
        ripple.backgroundColor = backgroundColor
        textPaint.color = textColor
        progressDrawable.color = textColor

        invalidate()
    }
}
