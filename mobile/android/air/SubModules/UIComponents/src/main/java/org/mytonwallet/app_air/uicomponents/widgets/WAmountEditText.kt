package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Typeface
import android.os.Build
import android.util.TypedValue
import androidx.appcompat.widget.AppCompatEditText
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import me.vkryl.android.animatorx.FloatAnimator
import me.vkryl.core.alphaColor
import me.vkryl.core.fromTo
import me.vkryl.core.fromToArgb
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.helpers.AmountTextWatcher
import org.mytonwallet.app_air.uicomponents.helpers.EditTextTint
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class WAmountEditText(
    context: Context,
    val isLeadingSymbol: Boolean = true
) : AppCompatEditText(context), WThemedView {
    val amountTextWatcher = AmountTextWatcher()

    val isLoading = BoolAnimator(
        AnimationConstants.VERY_QUICK_ANIMATION,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        initialValue = false
    ) { _, _, _, _ ->
        updateInputColor()
    }

    val isError = BoolAnimator(
        AnimationConstants.VERY_QUICK_ANIMATION,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        initialValue = false
    ) { _, _, _, _ ->
        updateInputColor()
    }

    private var currentSymbol: String? = null
    private var currentSymbolLastNonNull: String? = null
    private val symbolIsVisible = BoolAnimator(
        duration = 220L,
        interpolator = AnimatorUtils.DECELERATE_INTERPOLATOR,
        initialValue = false,
    ) { _, _, _, _ ->
        updateInputColor()
    }

    private val symbolSize = FloatAnimator(220L, AnimatorUtils.DECELERATE_INTERPOLATOR, 0f) {
        updatePadding(it.roundToInt())
    }


    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        currentSymbolLastNonNull?.let { symbol ->
            if (symbolIsVisible.floatValue > 0f) {
                val currentColor = paint.color
                paint.color = alphaColor(
                    symbolIsVisible.floatValue, if (text.isNullOrBlank()) {
                        WColor.SecondaryText.color
                    } else {
                        currentColor
                    }
                )
                if (isLeadingSymbol)
                    canvas.drawText(symbol, scrollX.toFloat(), baseline.toFloat(), paint)
                else
                    canvas.drawText(
                        symbol,
                        width + scrollX.toFloat() - additional,
                        baseline.toFloat(),
                        paint
                    )
                paint.color = currentColor
            }
        }
    }

    override val isTinted = true
    override fun updateTheme() {
        setHintTextColor(WColor.SecondaryText.color)
        updateInputColor()
        highlightColor = WColor.Tint.color.colorWithAlpha(51)
        EditTextTint.applyColor(this, WColor.Tint.color)
    }

    fun setBaseCurrencySymbol(symbol: String?) {
        if (symbol == currentSymbol) {
            return
        }

        if (!symbol.isNullOrBlank()) {
            currentSymbolLastNonNull = symbol
        }

        currentSymbol = symbol
        symbolIsVisible.changeValue(!symbol.isNullOrBlank(), isAttachedToWindow)
        updateSymbolWidth(isAttachedToWindow)
    }

    fun hideBaseCurrencySymbol() {
        setBaseCurrencySymbol(null)
    }

    private fun updateInputColor() {
        val defaultColor = WColor.PrimaryText.color
        val errorColor = WColor.Error.color

        setTextColor(fromToArgb(defaultColor, errorColor, isError.floatValue))
        alpha = fromTo(1f, 0.4f, isLoading.floatValue)

        invalidate()
    }

    private fun updateSymbolWidth(animated: Boolean) {
        val width = currentSymbol?.let { paint.measureText(it) } ?: 0f
        symbolSize.changeValue(width, animated && isAttachedToWindow)
    }

    override fun setTextSize(size: Float) {
        super.setTextSize(size)
        post { updateSymbolWidth(false) }
    }

    override fun setTextSize(unit: Int, size: Float) {
        super.setTextSize(unit, size)
        post { updateSymbolWidth(false) }
    }

    override fun setTypeface(tf: Typeface?) {
        super.setTypeface(tf)
        post { updateSymbolWidth(false) }
    }

    override fun setTypeface(tf: Typeface?, style: Int) {
        super.setTypeface(tf, style)
        post { updateSymbolWidth(false) }
    }


    /* Padding Animation */
    private var additional = 0

    private fun updatePadding(additional: Int) {
        if (isLeadingSymbol)
            super.setPadding(paddingLeft + additional, paddingTop, paddingRight, paddingBottom)
        else
            super.setPadding(paddingLeft, paddingTop, paddingRight + additional, paddingBottom)
        this.additional = additional
    }

    override fun setPadding(left: Int, top: Int, right: Int, bottom: Int) {
        if (isLeadingSymbol)
            super.setPadding(left + additional, top, right, bottom)
        else
            super.setPadding(left, top, right + additional, bottom)
    }

    override fun getPaddingLeft(): Int {
        return super.getPaddingLeft() - additional
    }

    /* Init */

    init {
        background = null
        typeface = WFont.Medium.typeface
        setPadding(0, 0, 0, 0)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 28f)
        }

        addTextChangedListener(amountTextWatcher)
        updateTheme()
    }
}
