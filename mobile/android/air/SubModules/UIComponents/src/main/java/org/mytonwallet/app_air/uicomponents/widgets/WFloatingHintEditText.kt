package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristic
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.text.TextUtils
import android.util.AttributeSet
import android.view.Gravity
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import androidx.appcompat.R
import androidx.appcompat.widget.AppCompatEditText
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import kotlin.math.max

open class WFloatingHintEditText @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = R.attr.editTextStyle,
) : AppCompatEditText(context, attrs, defStyle), WThemedView {

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
    private var floatingHintDrawState: FloatingHintDrawState? = null

    override fun updateTheme() {
        setHintTextColor(WColor.SecondaryText.color)
        setTextColor(WColor.PrimaryText.color)
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

        val save = canvas.save()
        canvas.translate(floatingHintDrawState.x - scrollX, floatingHintDrawState.y - scrollY)

        floatingHintDrawState.hintLayout.draw(canvas)
        canvas.restoreToCount(save)
    }

    private fun shouldDrawHint(): Boolean {
        if (!text.isNullOrEmpty() || floatingHintText.isNullOrEmpty()) {
            return false
        }
        return alpha > 0f && visibility == VISIBLE
    }

    private fun obtainFloatingHintDrawState(): FloatingHintDrawState? {
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

        return FloatingHintDrawState(hintLayout = layout, x = x, y = y).also {
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

    private data class FloatingHintDrawState(
        val hintLayout: StaticLayout,
        val x: Float,
        val y: Float
    )
}
