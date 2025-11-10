package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.Animator
import android.animation.AnimatorSet
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Rect
import android.graphics.drawable.Drawable
import android.graphics.drawable.ShapeDrawable
import android.os.Build
import android.text.StaticLayout
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import androidx.appcompat.R
import androidx.appcompat.content.res.AppCompatResources
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.ViewHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import kotlin.math.roundToInt

open class SwapSearchEditText @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = R.attr.editTextStyle,
) : WFloatingHintEditText(context, attrs, defStyle), WThemedView {

    private var viewState: ViewState? = ViewState()
    private var viewPropertiesState: ViewPropertiesState = ViewPropertiesState()
    private var propertiesAnimator: Animator? = null
    private val backgroundDrawable: ShapeDrawable =
        ViewHelpers.roundedShapeDrawable(0, 24f.dp)
    private val cursorDrawable: Drawable?
    private val searchDrawable: Drawable? =
        AppCompatResources.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_search_24
        )?.mutate()?.apply {
            setTint(WColor.SecondaryText.color)
        }

    init {
        setPaddingDp(20, 0, 20, 0)

        background = backgroundDrawable
        typeface = WFont.Regular.typeface
        isSingleLine = true
        isHorizontalFadingEdgeEnabled = true

        hint = LocaleController.getString("Search...")
        floatingHintGravity = Gravity.CENTER_HORIZONTAL or Gravity.CENTER_VERTICAL

        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 22f)
        }

        updateTheme()
        cursorDrawable = textCursorDrawable?.mutate()?.apply {
            alpha = (viewPropertiesState.cursorAlpha * 255).roundToInt()
        }
        textCursorDrawable = cursorDrawable
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        val x = 12.dp
        val y = measuredHeight / 2 - 12.dp
        searchDrawable?.setBounds(
            x, y,
            x + 24.dp,
            y + 24.dp
        )
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        val tx = -viewPropertiesState.iconTranslationX * (12 + 24).dp
        canvas.translate(tx + scrollX.toFloat(), 0f)
        searchDrawable?.apply {
            alpha = (viewPropertiesState.iconAlpha * 255).roundToInt()
            draw(canvas)
        }
        canvas.restore()
    }

    override fun onDrawHint(
        canvas: Canvas,
        hintX: Float,
        contextX: Float,
        hintY: Float,
        hintLayout: StaticLayout
    ) {
        hintLayout.paint.alpha = (viewPropertiesState.hintAlpha * 255).roundToInt()
        val contentXOffset = -viewPropertiesState.hintTranslationX * contextX
        super.onDrawHint(
            canvas = canvas,
            hintX = hintX + contentXOffset,
            contextX = contextX,
            hintY = hintY,
            hintLayout = hintLayout
        )
    }

    override fun updateTheme() {
        setHintTextColor(WColor.SecondaryText.color)
        setTextColor(WColor.PrimaryText.color)
        backgroundDrawable.paint.color = WColor.SearchFieldBackground.color
    }

    fun setTextKeepCursor(newText: String) {
        val currentSelectionStart = selectionStart
        val currentSelectionEnd = selectionEnd

        setText(newText)

        if (currentSelectionStart >= 0 && currentSelectionEnd >= 0) {
            val newLength = text?.length ?: 0
            val safeStart = currentSelectionStart.coerceAtMost(newLength)
            val safeEnd = currentSelectionEnd.coerceAtMost(newLength)
            setSelection(safeStart, safeEnd)
        }
    }

    override fun onFocusChanged(
        focused: Boolean,
        direction: Int,
        previouslyFocusedRect: Rect?
    ) {
        super.onFocusChanged(focused, direction, previouslyFocusedRect)
        viewState?.let { viewState ->
            onViewStateChanged(viewState.copy(hasFocus = focused))
        }
    }

    override fun onTextChanged(text: CharSequence?, start: Int, before: Int, count: Int) {
        super.onTextChanged(text, start, before, count)
        viewState?.let { viewState ->
            onViewStateChanged(viewState.copy(hasText = !text.isNullOrEmpty()))
        }
    }

    private fun onViewStateChanged(newState: ViewState) {
        if (viewState == newState) {
            return
        }
        viewState = newState
        moveToState(newState)
        invalidate()
    }

    private fun moveToState(state: ViewState) {
        val initialPropertiesState = viewPropertiesState.copy()
        val targetPropertiesState = when {
            // initial
            !state.hasFocus && !state.hasText -> ViewPropertiesState()

            // focus, empty
            state.hasFocus && !state.hasText -> ViewPropertiesState(
                iconAlpha = 0f,
                iconTranslationX = 1f,
                hintAlpha = 1f,
                hintTranslationX = 1f,
                cursorAlpha = 1f
            )

            // non-empty
            else -> ViewPropertiesState(
                iconAlpha = 0f,
                iconTranslationX = 1f,
                hintAlpha = 0f,
                hintTranslationX = 1f,
                cursorAlpha = 1f
            )
        }
        propertiesAnimator?.cancel()
        val primaryAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_VERY_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_OUT
            addUpdateListener { animation ->
                val animatedValue = animation.animatedValue as Float
                viewPropertiesState.applyPrimaryLerp(
                    initialPropertiesState,
                    targetPropertiesState,
                    animatedValue
                )
                invalidate()
            }
        }
        val secondaryAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.SUPER_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_OUT
            addUpdateListener { animation ->
                val animatedValue = animation.animatedValue as Float
                viewPropertiesState.applySecondaryLerp(
                    initialPropertiesState,
                    targetPropertiesState,
                    animatedValue
                )
                cursorDrawable?.alpha = (viewPropertiesState.cursorAlpha * 255).roundToInt()
                invalidate()
            }
        }
        propertiesAnimator = AnimatorSet().apply {
            playSequentially(primaryAnimator, secondaryAnimator)
            start()
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        propertiesAnimator?.end()
        propertiesAnimator = null
    }

    private data class ViewState(
        val hasFocus: Boolean = false,
        val hasText: Boolean = false
    )

    private data class ViewPropertiesState(
        var iconAlpha: Float = 1f,
        var iconTranslationX: Float = 0f,
        var hintAlpha: Float = 1f,
        var hintTranslationX: Float = 0f,
        var cursorAlpha: Float = 0f
    ) {
        fun applyPrimaryLerp(a: ViewPropertiesState, b: ViewPropertiesState, f: Float) {
            iconAlpha = lerp(a.iconAlpha, b.iconAlpha, f)
            iconTranslationX = lerp(a.iconTranslationX, b.iconTranslationX, f)
            hintAlpha = lerp(a.hintAlpha, b.hintAlpha, f)
            hintTranslationX = lerp(a.hintTranslationX, b.hintTranslationX, f)
        }

        fun applySecondaryLerp(a: ViewPropertiesState, b: ViewPropertiesState, f: Float) {
            cursorAlpha = lerp(a.cursorAlpha, b.cursorAlpha, f)
        }
    }
}
