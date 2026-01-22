package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.Animator
import android.animation.AnimatorSet
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Rect
import android.graphics.drawable.Drawable
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristic
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.text.TextUtils
import android.view.Gravity
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import androidx.core.graphics.withTranslation
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.textCursorDrawableCompat
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

open class WFloatingHintEditText @JvmOverloads constructor(
    context: Context,
    delegate: Delegate? = null,
    multilinePaste: Boolean = true,
    private var animatedStateChange: Boolean = true
) : WEditText(context, delegate, multilinePaste) {

    private var viewState: ViewState? = ViewState()
    private var viewPropertiesStateSet: ViewPropertiesStateSet = ViewPropertiesStateSet()
    private var viewPropertiesStateAnimator: Animator? = null
    var floatingHintGravity: Int = Gravity.CENTER_VERTICAL or Gravity.START
        set(value) {
            if (field == value) {
                return
            }
            field = value
            invalidateHintLayout()
            invalidate()
        }
    private var floatingHintText: CharSequence? = null
    private var floatingHintDrawState: FloatingHintState? = null
    private val cursorDrawable: Drawable? = textCursorDrawableCompat?.mutate()?.apply {
        alpha = (viewPropertiesStateSet.current.cursorAlpha * 255).roundToInt()
    }

    init {
        textCursorDrawableCompat = cursorDrawable
    }

    override fun updateTheme() {
        super.updateTheme()
        setHintTextColor(WColor.SecondaryText.color)
    }

    override fun requestLayout() {
        hint?.let { hint -> setFloatingHint(hint) }
        super.requestLayout()
    }

    private fun setFloatingHint(hint: CharSequence) {
        super.setHint(null)
        if (TextUtils.equals(floatingHintText, hint)) {
            return
        }
        floatingHintText = hint
        invalidateHintLayout()
    }

    override fun setText(text: CharSequence?, type: BufferType?) {
        super.setText(text, type)
        if (!text.isNullOrBlank()) {
            invalidateHintLayout()
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        invalidateHintLayout()
    }

    override fun onTextChanged(text: CharSequence?, start: Int, before: Int, count: Int) {
        super.onTextChanged(text, start, before, count)
        if (text.isNullOrBlank()) {
            invalidate()
        } else {
            invalidateHintLayout()
        }
        viewState?.let { viewState ->
            onViewStateUpdated(viewState.copy(hasText = !text.isNullOrEmpty()))
        }
    }

    override fun onFocusChanged(
        focused: Boolean,
        direction: Int,
        previouslyFocusedRect: Rect?
    ) {
        super.onFocusChanged(focused, direction, previouslyFocusedRect)
        viewState?.let { viewState ->
            onViewStateUpdated(viewState.copy(hasFocus = focused))
        }
    }

    private fun onViewStateUpdated(updatedState: ViewState) {
        if (viewState == updatedState) {
            return
        }
        viewPropertiesStateAnimator?.cancel()
        viewState = updatedState
        onStartMoveToState(updatedState)
        if (animatedStateChange) {
            startViewPropertiesAnimation()
        } else {
            onViewPropertiesPrimaryAnimationProgress(1f)
            onViewPropertiesSecondaryAnimationProgress(1f)
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        viewPropertiesStateAnimator?.end()
        viewPropertiesStateAnimator = null
    }

    open fun onStartMoveToState(targetState: ViewState) {
        viewPropertiesStateSet = viewPropertiesStateSet.copy(
            source = viewPropertiesStateSet.current.copy(),
            target = buildTargetViewPropertiesState(targetState)
        )
    }

    open fun onViewPropertiesPrimaryAnimationProgress(progress: Float) {
        viewPropertiesStateSet.applyPrimaryLerp(progress)
        invalidate()
    }

    open fun onViewPropertiesSecondaryAnimationProgress(progress: Float) {
        viewPropertiesStateSet.applySecondaryLerp(progress)
        cursorDrawable?.alpha = (viewPropertiesStateSet.current.cursorAlpha * 255).roundToInt()
        invalidate()
    }

    private fun startViewPropertiesAnimation() {
        val primaryAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener { animation ->
                val animatedValue = animation.animatedValue as Float
                onViewPropertiesPrimaryAnimationProgress(animatedValue)
                invalidate()
            }
        }
        val secondaryAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.SUPER_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener { animation ->
                val animatedValue = animation.animatedValue as Float
                onViewPropertiesSecondaryAnimationProgress(animatedValue)
                invalidate()
            }
        }
        viewPropertiesStateAnimator = AnimatorSet().apply {
            playSequentially(primaryAnimator, secondaryAnimator)
            start()
        }
    }

    private fun buildTargetViewPropertiesState(targetState: ViewState): ViewPropertiesState {
        return when {
            // initial
            !targetState.hasFocus && !targetState.hasText -> ViewPropertiesState()

            // focus, empty
            targetState.hasFocus && !targetState.hasText -> ViewPropertiesState(
                hintAlpha = 1f,
                cursorAlpha = 1f
            )

            // non-empty
            else -> ViewPropertiesState(
                hintAlpha = 0f,
                cursorAlpha = 1f
            )
        }
    }


    override fun onRtlPropertiesChanged(layoutDirection: Int) {
        super.onRtlPropertiesChanged(layoutDirection)
        invalidateHintLayout()
    }

    private fun invalidateHintLayout() {
        floatingHintDrawState = null
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        if (!shouldDrawHint()) {
            return
        }

        val floatingHintDrawState = obtainFloatingHintDrawState() ?: return

        onDrawHint(
            canvas = canvas,
            hintX = floatingHintDrawState.x,
            contextX = floatingHintDrawState.contentX,
            hintY = floatingHintDrawState.y,
            hintLayout = floatingHintDrawState.hintLayout
        )
    }

    private fun onDrawHint(
        canvas: Canvas,
        hintX: Float,
        contextX: Float,
        hintY: Float,
        hintLayout: StaticLayout
    ) {
        val viewPropertiesState = viewPropertiesStateSet.current
        hintLayout.paint.alpha = (viewPropertiesState.hintAlpha * 255).roundToInt()
        val hintExtraPadding = paddingRight - paddingLeft
        val contentXOffset = -viewPropertiesState.hintTranslationX * (contextX + hintExtraPadding)
        canvas.withTranslation(hintX + contentXOffset - scrollX, hintY - scrollY) {
            hintLayout.draw(canvas)
        }
    }

    private fun shouldDrawHint(): Boolean {
        return text.isNullOrEmpty() && !floatingHintText.isNullOrBlank()
    }

    private fun obtainFloatingHintDrawState(): FloatingHintState? {
        if (floatingHintDrawState != null) {
            return floatingHintDrawState
        }

        val textForHint = floatingHintText ?: return null

        val hintGravity = floatingHintGravity
        val isRtl = layoutDirection == LAYOUT_DIRECTION_RTL
        val horizontalGravity = resolveHorizontalGravity(hintGravity, isRtl)
        val verticalGravity = resolveVerticalGravity(hintGravity)

        val paddingLeft: Int
        val paddingRight: Int
        if (horizontalGravity == Gravity.CENTER_HORIZONTAL) {
            max(compoundPaddingLeft, compoundPaddingRight).let { padding ->
                paddingLeft = padding
                paddingRight = padding
            }
        } else {
            paddingLeft = compoundPaddingLeft
            paddingRight = compoundPaddingRight
        }
        val contentLeft = paddingLeft
        val contentRight = width - paddingRight

        val paddingTop: Int
        val paddingBottom: Int
        if (verticalGravity == Gravity.CENTER_VERTICAL) {
            max(compoundPaddingTop, compoundPaddingBottom).let { padding ->
                paddingTop = padding
                paddingBottom = padding
            }
        } else {
            paddingTop = compoundPaddingTop
            paddingBottom = compoundPaddingBottom
        }
        val contentTop = paddingTop
        val contentBottom = height - paddingBottom
        val contentWidth = (contentRight - contentLeft).coerceAtLeast(0)

        if (contentWidth == 0) {
            return null
        }

        val layout = createHintLayout(textForHint, contentWidth)

        val layoutWidth = layout.width
        val x = when (horizontalGravity) {
            Gravity.CENTER_HORIZONTAL -> contentLeft + (contentWidth - layoutWidth) / 2
            Gravity.RIGHT, Gravity.END -> contentRight - layoutWidth
            else -> contentLeft
        }.toFloat()

        val layoutHeight = layout.height
        val y = when (verticalGravity) {
            Gravity.CENTER_VERTICAL -> contentTop + (contentBottom - contentTop - layoutHeight) / 2
            Gravity.BOTTOM -> contentBottom - layoutHeight
            else -> contentTop
        }.toFloat()

        var contentX: Float = layout.width.toFloat()
        for (i in 0 until layout.lineCount) {
            contentX = min(contentX, layout.getLineLeft(i))
        }

        return FloatingHintState(hintLayout = layout, x = x, contentX = contentX, y = y).also {
            floatingHintDrawState = it
        }
    }

    private fun createHintLayout(hintText: CharSequence, availableWidth: Int): StaticLayout {
        val hintPaint = TextPaint(paint)
        hintPaint.color = (hintTextColors?.defaultColor ?: currentTextColor).let { color ->
            hintTextColors?.defaultColor ?: color
        }

        val alignment = resolveAlignment(floatingHintGravity)
        val spacingMultiplier = lineSpacingMultiplier
        val spacingAdd = lineSpacingExtra

        val hyphenationFrequency = hyphenationFrequency
        val breakStrategyVal = breakStrategy
        val includePad = true

        val textDir: TextDirectionHeuristic = if (layoutDirection == LAYOUT_DIRECTION_RTL) {
            TextDirectionHeuristics.RTL
        } else {
            TextDirectionHeuristics.LTR
        }

        val layout = StaticLayout.Builder
            .obtain(hintText, 0, hintText.length, hintPaint, availableWidth)
            .setAlignment(alignment)
            .setIncludePad(includePad)
            .setLineSpacing(spacingAdd, spacingMultiplier)
            .setBreakStrategy(breakStrategyVal)
            .setHyphenationFrequency(hyphenationFrequency)
            .setTextDirection(textDir)
            .build()
        return layout
    }

    private fun resolveAlignment(gravity: Int): Layout.Alignment {
        val horizontalGravity = resolveHorizontalGravity(
            gravity, layoutDirection == LAYOUT_DIRECTION_RTL
        )
        return when (horizontalGravity) {
            Gravity.CENTER_HORIZONTAL -> Layout.Alignment.ALIGN_CENTER
            Gravity.RIGHT, Gravity.END -> Layout.Alignment.ALIGN_OPPOSITE
            else -> Layout.Alignment.ALIGN_NORMAL
        }
    }

    @Suppress("KotlinConstantConditions")
    private fun resolveHorizontalGravity(gravity: Int, isRtl: Boolean): Int {
        val hGravity = gravity and Gravity.HORIZONTAL_GRAVITY_MASK
        if (hGravity == 0) {
            return Gravity.LEFT
        }
        if (hGravity == Gravity.LEFT || hGravity == Gravity.RIGHT || hGravity == Gravity.CENTER_HORIZONTAL) {
            return hGravity
        }
        return if (isRtl) {
            if (hGravity == Gravity.START) Gravity.RIGHT else Gravity.LEFT
        } else {
            if (hGravity == Gravity.START) Gravity.LEFT else Gravity.RIGHT
        }
    }

    private fun resolveVerticalGravity(gravity: Int): Int {
        val vGravity = gravity and Gravity.VERTICAL_GRAVITY_MASK
        return if (vGravity == 0) {
            Gravity.TOP
        } else {
            vGravity
        }
    }

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? {
        val inputConnection = super.onCreateInputConnection(outAttrs)
        if (outAttrs.hintText == null) {
            outAttrs.hintText = floatingHintText
        }
        return inputConnection
    }

    data class ViewState(
        val hasFocus: Boolean = false,
        val hasText: Boolean = false
    )

    private data class FloatingHintState(
        val hintLayout: StaticLayout,
        val x: Float,
        val contentX: Float,
        val y: Float,
    )

    private data class ViewPropertiesState(
        var hintAlpha: Float = 1f,
        var hintTranslationX: Float = 1f,
        var cursorAlpha: Float = 0f
    )

    private data class ViewPropertiesStateSet(
        val current: ViewPropertiesState = ViewPropertiesState(),
        val source: ViewPropertiesState = ViewPropertiesState(),
        val target: ViewPropertiesState = ViewPropertiesState()
    ) {
        fun applyPrimaryLerp(f: Float) {
            with(current) {
                hintAlpha = lerp(source.hintAlpha, target.hintAlpha, f)
                hintTranslationX = lerp(source.hintTranslationX, target.hintTranslationX, f)
            }
        }

        fun applySecondaryLerp(f: Float) {
            current.cursorAlpha = lerp(source.cursorAlpha, target.cursorAlpha, f)
        }
    }
}
