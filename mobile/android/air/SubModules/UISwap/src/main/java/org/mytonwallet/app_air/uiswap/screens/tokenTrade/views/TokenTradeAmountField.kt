package org.mytonwallet.app_air.uiswap.screens.tokenTrade.views

import android.animation.Keyframe
import android.animation.PropertyValuesHolder
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.drawable.LayerDrawable
import android.text.InputFilter
import android.text.InputType
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.style.AbsoluteSizeSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatEditText
import androidx.core.graphics.withScale
import androidx.core.graphics.withTranslation
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.EditTextTint
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.TokenTradeAmountInput
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils

/** Only the number is editable. Affixes use the same scale and baseline as the number. */
class TokenTradeAmountField(context: Context) :
    FrameLayout(context),
    WThemedView {

    var onChange: ((TokenTradeAmountInput) -> Unit)? = null

    val editText = AmountEditText(context)

    private val clearCircle = context.getDrawableCompat(
        org.mytonwallet.app_air.icons.R.drawable.ic_clear_24_circle
    )?.mutate()

    private val clearButton = ImageView(context).apply {
        setImageDrawable(
            LayerDrawable(
                listOfNotNull(
                    clearCircle,
                    context.getDrawableCompat(
                        org.mytonwallet.app_air.icons.R.drawable.ic_clear_24_cross
                    )
                ).toTypedArray()
            )
        )
        scaleType = ImageView.ScaleType.FIT_CENTER
        val inset = ((44f - 16f * 24f / 20f) / 2f).dp.roundToInt()
        setPadding(inset, inset, inset, inset)
        contentDescription = LocaleController.getString("Clear")
        visibility = GONE
        setOnClickListener { editText.clear() }
    }

    init {
        id = generateViewId()
        layoutDirection = LAYOUT_DIRECTION_LTR
        addView(editText, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(clearButton, LayoutParams(44.dp, 44.dp, Gravity.END or Gravity.TOP))
        editText.onFrame = { layoutClearButton() }
        editText.onEdit = { input ->
            clearButton.visibility = if (input.text.isEmpty()) GONE else VISIBLE
            onChange?.invoke(input)
        }
        updateTheme()
    }

    fun configure(
        input: TokenTradeAmountInput,
        decimals: Int,
        prefix: String,
        suffix: String,
        hasAmount: Boolean,
        switchesUnit: Boolean = false
    ) {
        editText.configure(input, decimals, prefix, suffix, hasAmount, switchesUnit)
        clearButton.visibility = if (input.text.isEmpty()) GONE else VISIBLE
    }

    fun insert(text: String) = editText.insert(text)

    fun deleteBackward() = editText.deleteBackward()

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        layoutClearButton()
    }

    private fun layoutClearButton() {
        clearButton.translationY = max(0f, editText.capCenter() - clearButton.height / 2f)
    }

    override fun updateTheme() {
        clearCircle?.setTint(WColor.SecondaryText.color)
        clearButton.alpha = 0.6f
        editText.updateTheme()
    }

    @SuppressLint("ViewConstructor")
    class AmountEditText(context: Context) : AppCompatEditText(context) {
        var onEdit: ((TokenTradeAmountInput) -> Unit)? = null
        var onFrame: (() -> Unit)? = null

        private var amountInput = TokenTradeAmountInput()
        private var decimals = 2
        private var prefix = ""
        private var suffix = ""
        private var hasAmount = false
        private var scale = 1f
        private var numberWidth = 0f
        private var isApplyingText = false
        private var formattedSize = 0 to 0

        private val affixPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = WFont.Balance.typeface
        }

        // The number is drawn glyph by glyph so that inserted and removed characters can animate;
        // the text itself stays in the field, transparent, for the caret, selection and accessibility.
        private val glyphPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = WFont.Balance.typeface
        }
        private val glyphs = ArrayList<Glyph>()
        private var glyphColor = 0
        private var glyphScale = 1f
        private var fromScale = 1f
        private var fromNumberEnd = 0f
        private var toNumberEnd = 0f
        private var progress = 1f
        private val glyphAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
            addUpdateListener {
                progress = it.animatedValue as Float
                if (it.animatedFraction >= 1f) glyphs.removeAll(Glyph::isRemoved)
                invalidate()
                onFrame?.invoke()
            }
        }

        private var isCaretReady = false
        private var caretAlpha = 1f
        private val caretPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val inkBounds = Rect()

        // Digit height per unit of text size, so the caret spans the digits rather than the line
        private val digitHeightRatio = Rect().let { bounds ->
            glyphPaint.textSize = 100f
            glyphPaint.getTextBounds("0", 0, 1, bounds)
            bounds.height() / 100f
        }

        // Holds, fades out, holds hidden, and fades back in; steps instead when animations are off
        private val caretBlink = ValueAnimator.ofPropertyValuesHolder(
            PropertyValuesHolder.ofKeyframe(
                "alpha",
                Keyframe.ofFloat(0f, 1f),
                Keyframe.ofFloat(0.45f, 1f),
                Keyframe.ofFloat(0.6f, 0f),
                Keyframe.ofFloat(0.85f, 0f),
                Keyframe.ofFloat(1f, 1f)
            )
        ).apply {
            duration = CARET_BLINK_DURATION
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                val value = it.animatedValue as Float
                val alpha = if (WGlobalStorage.getAreAnimationsActive()) {
                    value
                } else if (value >= 0.5f) {
                    1f
                } else {
                    0f
                }
                if (alpha != caretAlpha) {
                    caretAlpha = alpha
                    invalidate()
                }
            }
        }

        // The previous unit's number, leaving upwards while the new one enters from below
        private var outgoing: DrawnNumber? = null
        private var switchProgress = 1f
        private val switchAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
            addUpdateListener {
                switchProgress = it.animatedValue as Float
                if (it.animatedFraction >= 1f) outgoing = null
                invalidate()
                onFrame?.invoke()
            }
        }

        init {
            background = null
            setPadding(0, 0, 0, 0)
            includeFontPadding = false
            isSingleLine = true
            gravity = Gravity.START or Gravity.TOP
            layoutDirection = LAYOUT_DIRECTION_LTR
            textDirection = TEXT_DIRECTION_LTR
            typeface = WFont.Balance.typeface
            setTextColor(Color.TRANSPARENT)
            setHintTextColor(Color.TRANSPARENT)
            showSoftInputOnFocus = false
            isCursorVisible = false
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            isHorizontalScrollBarEnabled = false
            contentDescription = LocaleController.getString("Amount")
            // Every edit goes through `applyEdit`, which rewrites the text as a whole.
            filters = arrayOf(
                InputFilter { _, _, _, dest, dstart, dend ->
                    if (isApplyingText) null else dest.subSequence(dstart, dend)
                }
            )
            setTextSize(TypedValue.COMPLEX_UNIT_PX, 72f.dp)
            isCaretReady = true
        }

        fun updateTheme() {
            EditTextTint.applyColor(this, WColor.Tint.color)
            highlightColor = WColor.Tint.color and 0x33FFFFFF
            render(animated = true)
        }

        fun configure(
            input: TokenTradeAmountInput,
            decimals: Int,
            prefix: String,
            suffix: String,
            hasAmount: Boolean,
            switchesUnit: Boolean
        ) {
            this.decimals = decimals
            if (amountInput == input && this.prefix == prefix && this.suffix == suffix &&
                this.hasAmount == hasAmount
            ) {
                return
            }
            val changedInput = amountInput != input
            val animatesSwitch =
                switchesUnit && isLaidOut && WGlobalStorage.getAreAnimationsActive()
            if (animatesSwitch) captureOutgoing()
            amountInput = input
            this.prefix = prefix
            this.suffix = suffix
            this.hasAmount = hasAmount
            render(animated = !changedInput && !animatesSwitch)
            if (changedInput) setSelection(length())
            if (animatesSwitch) {
                switchProgress = 0f
                switchAnimator.start()
            }
        }

        /** The vertical center of the digits' caps, following the running animations. */
        fun capCenter(): Float {
            val scale = AnimUtils.lerp(fromScale, glyphScale, progress)
            val center = baseline * scale / glyphScale - 72f.dp * scale * 0.36f
            val outgoing = outgoing ?: return center
            val outgoingCenter = outgoing.baseline - 72f.dp * outgoing.scale * 0.36f
            return AnimUtils.lerp(outgoingCenter, center, switchProgress)
        }

        private fun captureOutgoing() {
            outgoing = DrawnNumber(
                glyphs = glyphs.mapNotNull { it.frozen(progress) },
                prefix = prefix,
                suffix = suffix,
                color = glyphColor,
                scale = AnimUtils.lerp(fromScale, glyphScale, progress),
                baseline = baseline * AnimUtils.lerp(fromScale, glyphScale, progress) / glyphScale,
                numberEnd = AnimUtils.lerp(fromNumberEnd, toNumberEnd, progress)
            )
        }

        fun insert(text: String) {
            requestFocus()
            applyEdit(selectionStart.coerceAtLeast(0), selectionEnd.coerceAtLeast(0), text)
        }

        fun deleteBackward() {
            requestFocus()
            var start = selectionStart.coerceAtLeast(0)
            val end = selectionEnd.coerceAtLeast(0)
            if (start == end) {
                if (start == 0) return
                start--
            }
            applyEdit(start, end, "")
        }

        fun clear() = applyEdit(0, amountInput.text.length, "")

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            post { if (isAttachedToWindow) requestFocus() }
        }

        override fun onDetachedFromWindow() {
            super.onDetachedFromWindow()
            caretBlink.cancel()
        }

        override fun onFocusChanged(
            focused: Boolean,
            direction: Int,
            previouslyFocusedRect: Rect?
        ) {
            super.onFocusChanged(focused, direction, previouslyFocusedRect)
            restartCaretBlink()
        }

        override fun onWindowFocusChanged(hasWindowFocus: Boolean) {
            super.onWindowFocusChanged(hasWindowFocus)
            restartCaretBlink()
        }

        override fun onSelectionChanged(selStart: Int, selEnd: Int) {
            super.onSelectionChanged(selStart, selEnd)
            restartCaretBlink()
        }

        private fun restartCaretBlink() {
            if (!isCaretReady) return
            caretBlink.cancel()
            caretAlpha = 1f
            if (isFocused && hasWindowFocus()) caretBlink.start()
            invalidate()
        }

        override fun onTextContextMenuItem(id: Int): Boolean {
            when (id) {
                android.R.id.paste, android.R.id.pasteAsPlainText -> {
                    val clipboard = context.getSystemService(ClipboardManager::class.java)
                    val text = clipboard?.primaryClip?.getItemAt(0)?.coerceToText(context)
                    if (text != null) {
                        applyEdit(selectionStart, selectionEnd, text.toString())
                    }
                    return true
                }

                android.R.id.cut -> {
                    super.onTextContextMenuItem(android.R.id.copy)
                    applyEdit(selectionStart, selectionEnd, "")
                    return true
                }
            }
            return super.onTextContextMenuItem(id)
        }

        override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
            if (keyCode == KeyEvent.KEYCODE_DEL) {
                deleteBackward()
                return true
            }
            val char = event.unicodeChar.takeIf { it != 0 }?.toChar()
            if (char != null && (char.isDigit() || char == '.' || char == ',')) {
                insert(char.toString())
                return true
            }
            return super.onKeyDown(keyCode, event)
        }

        private fun applyEdit(start: Int, end: Int, replacement: String) {
            val editStart = min(start, end).coerceAtLeast(0)
            val edit = amountInput.replacing(
                editStart,
                max(start, end).coerceAtMost(amountInput.text.length),
                replacement,
                decimals
            ) ?: return
            // The placeholder zero may be kept by the first typed characters
            val keptPrefix = if (amountInput.text.isEmpty()) Int.MAX_VALUE else editStart
            amountInput = edit.input
            hasAmount = amountInput.amount(decimals).signum() > 0
            render(animated = true, keptPrefix = keptPrefix)
            setSelection(edit.caret.coerceIn(0, length()))
            onEdit?.invoke(amountInput)
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            if (formattedSize != w to h) post { render() }
        }

        private fun render(animated: Boolean = false, keptPrefix: Int = Int.MAX_VALUE) {
            formattedSize = width to height
            val number = amountInput.text
            val visibleNumber = number.ifEmpty { "0" }
            val clearReserved = if (number.isEmpty()) 0 else 52.dp
            val available = max(1f, width - clearReserved - 4f.dp)

            fun fullWidth(scale: Float): Float = measureNumber(visibleNumber, scale) +
                measureAffix(prefix, 64f, scale) + measureAffix(suffix, 32f, scale)

            var scale = if (width <= 0) {
                1f
            } else {
                minOf(1f, max(0.2f, height / 86f.dp), max(0.2f, available / max(1f, fullWidth(1f))))
            }
            repeat(3) {
                val width = fullWidth(scale)
                if (width <= available) return@repeat
                scale = max(0.2f, scale * (available - 1) / width)
            }
            this.scale = scale
            numberWidth = measureNumber(visibleNumber, scale)
            glyphColor = if (hasAmount) WColor.PrimaryText.color else WColor.SecondaryText.color

            val styled = SpannableString(visibleNumber).apply {
                val separator = indexOf('.')
                if (separator >= 0) {
                    setSpan(
                        AbsoluteSizeSpan((56f.dp * scale).roundToInt()),
                        separator,
                        length,
                        Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
            }
            isApplyingText = true
            val selection = selectionStart to selectionEnd
            setTextSize(TypedValue.COMPLEX_UNIT_PX, 72f.dp * scale)
            if (number.isEmpty()) {
                setText("")
                hint = styled
            } else {
                hint = null
                setText(styled)
            }
            isApplyingText = false
            if (selection.first >= 0) {
                setSelection(
                    selection.first.coerceIn(0, length()),
                    selection.second.coerceIn(0, length())
                )
            }
            val prefixWidth = measureAffix(prefix, 64f, scale).roundToInt()
            setPadding(prefixWidth, 0, clearReserved, 0)
            updateGlyphs(
                visibleNumber,
                prefixWidth.toFloat(),
                animated && isLaidOut && WGlobalStorage.getAreAnimationsActive(),
                keptPrefix
            )
            invalidate()
        }

        private fun updateGlyphs(number: String, start: Float, animated: Boolean, keptPrefix: Int) {
            val numberEnd = start + numberWidth
            val live = glyphs.filterNot(Glyph::isRemoved)
            val isUnchanged = live.size == number.length &&
                live.indices.all { live[it].char == number[it] } &&
                glyphScale == scale && toNumberEnd == numberEnd
            if (animated && isUnchanged) return

            val current = progress
            glyphs.forEach { it.freeze(current) }
            fromScale = AnimUtils.lerp(fromScale, glyphScale, current)
            fromNumberEnd = AnimUtils.lerp(fromNumberEnd, toNumberEnd, current)
            glyphScale = scale
            toNumberEnd = numberEnd

            // Characters outside the common prefix and suffix are the ones replaced by the edit
            val prefixLimit = minOf(keptPrefix, live.size, number.length)
            var prefixLength = 0
            while (prefixLength < prefixLimit && live[prefixLength].char == number[prefixLength]) {
                prefixLength++
            }
            var suffixLength = 0
            while (suffixLength < live.size - prefixLength &&
                suffixLength < number.length - prefixLength &&
                live[live.size - 1 - suffixLength].char == number[number.length - 1 - suffixLength]
            ) {
                suffixLength++
            }
            for (index in prefixLength until live.size - suffixLength) live[index].remove()
            val next = ArrayList<Glyph>(number.length)
            next.addAll(live.subList(0, prefixLength))
            for (index in prefixLength until number.length - suffixLength) {
                next.add(Glyph(number[index]))
            }
            next.addAll(live.subList(live.size - suffixLength, live.size))
            val removed = glyphs.filter(Glyph::isRemoved)
            glyphs.clear()
            glyphs.addAll(next)
            glyphs.addAll(removed)

            val separator = number.indexOf('.')
            val integralSize = 72f.dp * scale
            val fractionSize = 56f.dp * scale
            glyphPaint.textSize = integralSize
            val integralWidth = glyphPaint.measureText(
                number,
                0,
                if (separator >=
                    0
                ) {
                    separator
                } else {
                    number.length
                }
            )
            next.forEachIndexed { index, glyph ->
                val isFraction = separator in 0..index
                glyphPaint.textSize = if (isFraction) fractionSize else integralSize
                glyph.toX = start + if (isFraction) {
                    integralWidth + glyphPaint.measureText(number, separator, index)
                } else {
                    glyphPaint.measureText(number, 0, index)
                }
                glyph.toSize = glyphPaint.textSize
                if (!glyph.isPlaced) {
                    glyph.fromX = glyph.toX
                    glyph.fromSize = glyph.toSize
                    glyph.isPlaced = true
                }
            }

            if (animated) {
                progress = 0f
                glyphAnimator.start()
            } else {
                glyphAnimator.cancel()
                glyphs.removeAll(Glyph::isRemoved)
                glyphs.forEach { it.freeze(1f) }
                fromScale = glyphScale
                fromNumberEnd = toNumberEnd
                progress = 1f
            }
        }

        private fun measureNumber(number: String, scale: Float): Float {
            val measurePaint = Paint(paint)
            val separator = number.indexOf('.')
            val integral = if (separator >= 0) number.substring(0, separator) else number
            val fraction = if (separator >= 0) number.substring(separator) else ""
            measurePaint.textSize = 72f.dp * scale
            var width = measurePaint.measureText(integral)
            measurePaint.textSize = 56f.dp * scale
            width += measurePaint.measureText(fraction)
            return width
        }

        private fun measureAffix(text: String, size: Float, scale: Float): Float {
            if (text.isEmpty()) return 0f
            affixPaint.textSize = size.dp * scale
            return kotlin.math.ceil(affixPaint.measureText(text))
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val switchProgress = switchProgress
            val switchDistance = height * 0.4f
            outgoing?.let { number ->
                canvas.withTranslation(0f, -switchProgress * switchDistance) {
                    drawNumber(
                        this,
                        number.glyphs,
                        1f,
                        number.color,
                        number.scale,
                        number.baseline,
                        number.prefix,
                        number.suffix,
                        number.numberEnd,
                        1f - switchProgress
                    )
                }
            }
            val animatedScale = AnimUtils.lerp(fromScale, glyphScale, progress)
            canvas.withTranslation(0f, (1f - switchProgress) * switchDistance) {
                drawNumber(
                    this,
                    glyphs,
                    progress,
                    glyphColor,
                    animatedScale,
                    baseline * animatedScale / glyphScale,
                    prefix,
                    suffix,
                    AnimUtils.lerp(fromNumberEnd, toNumberEnd, progress),
                    switchProgress
                )
                drawCaret(this, baseline * animatedScale / glyphScale, animatedScale)
            }
        }

        private fun drawCaret(canvas: Canvas, baseline: Float, scale: Float) {
            if (caretAlpha <= 0f || !isFocused || !hasWindowFocus()) return
            val index = selectionStart
            if (index < 0 || index != selectionEnd) return
            // Removed glyphs follow the live ones, which are in text order
            var liveCount = 0
            while (liveCount < glyphs.size && !glyphs[liveCount].isRemoved) liveCount++
            if (liveCount == 0) return
            val isEmpty = amountInput.text.isEmpty()
            // The character before the caret sets its size, so it is short right after the separator
            val sizeGlyph = glyphs[(index - 1).coerceIn(0, liveCount - 1)]
            val size = AnimUtils.lerp(sizeGlyph.fromSize, sizeGlyph.toSize, progress)
            val halfWidth = 1f.dp
            val gap = halfWidth + size * 0.04f
            // Placed by the digits' ink rather than their advances, which glyphs like 7 reach
            val inkLeft = if (!isEmpty && index > 0) {
                inkEdge(glyphs[min(index, liveCount) - 1], true)
            } else if (prefix.isNotEmpty()) {
                affixPaint.textSize = 64f.dp * scale
                affixPaint.getTextBounds(prefix, 0, prefix.length, inkBounds)
                scrollX + inkBounds.right.toFloat()
            } else {
                Float.NaN
            }
            val inkRight = if (isEmpty) {
                inkEdge(glyphs[0], false)
            } else if (index < liveCount) {
                inkEdge(glyphs[index], false)
            } else {
                Float.NaN
            }
            val x = when {
                !inkLeft.isNaN() && !inkRight.isNaN() -> (inkLeft + inkRight) / 2f
                !inkLeft.isNaN() -> inkLeft + gap
                !inkRight.isNaN() -> inkRight - gap
                else -> return
            }
            val overhang = size * 0.06f
            caretPaint.color = WColor.Tint.color
            caretPaint.alpha = (Color.alpha(caretPaint.color) * caretAlpha).roundToInt()
            canvas.drawRect(
                x - halfWidth,
                baseline - size * digitHeightRatio - overhang,
                x + halfWidth,
                baseline + overhang,
                caretPaint
            )
        }

        private fun inkEdge(glyph: Glyph, isEnd: Boolean): Float {
            glyphPaint.textSize = AnimUtils.lerp(glyph.fromSize, glyph.toSize, progress)
            glyphPaint.getTextBounds(glyph.text, 0, 1, inkBounds)
            return AnimUtils.lerp(glyph.fromX, glyph.toX, progress) +
                if (isEnd) inkBounds.right else inkBounds.left
        }

        private fun drawNumber(
            canvas: Canvas,
            glyphs: List<Glyph>,
            progress: Float,
            color: Int,
            scale: Float,
            baseline: Float,
            prefix: String,
            suffix: String,
            numberEnd: Float,
            opacity: Float
        ) {
            if (opacity <= 0f) return
            val alpha = Color.alpha(color) * opacity
            glyphPaint.color = color
            for (glyph in glyphs) {
                val presence = AnimUtils.lerp(glyph.fromPresence, glyph.toPresence, progress)
                if (presence <= 0f) continue
                val x = AnimUtils.lerp(glyph.fromX, glyph.toX, progress)
                glyphPaint.textSize = AnimUtils.lerp(glyph.fromSize, glyph.toSize, progress)
                glyphPaint.alpha = (alpha * presence).roundToInt()
                if (presence >= 1f) {
                    canvas.drawText(glyph.text, x, baseline, glyphPaint)
                    continue
                }
                val presenceScale = 0.5f + 0.5f * presence
                val pivotX = x + glyphPaint.measureText(glyph.text) / 2f
                val offsetY = (1f - presence) * glyphPaint.textSize * 0.3f
                canvas.withTranslation(0f, offsetY) {
                    withScale(presenceScale, presenceScale, pivotX, baseline) {
                        drawText(glyph.text, x, baseline, glyphPaint)
                    }
                }
            }
            val affixColor = WColor.SecondaryText.color
            affixPaint.color = affixColor
            affixPaint.alpha = (Color.alpha(affixColor) * opacity).roundToInt()
            canvas.withTranslation(scrollX.toFloat(), 0f) {
                if (prefix.isNotEmpty()) {
                    affixPaint.textSize = 64f.dp * scale
                    drawText(prefix, 0f, baseline, affixPaint)
                }
                if (suffix.isNotEmpty()) {
                    affixPaint.textSize = 32f.dp * scale
                    drawText(suffix, numberEnd + 2f.dp, baseline, affixPaint)
                }
            }
        }
    }

    private companion object {
        const val CARET_BLINK_DURATION = 2000L
    }

    private class DrawnNumber(
        val glyphs: List<Glyph>,
        val prefix: String,
        val suffix: String,
        val color: Int,
        val scale: Float,
        val baseline: Float,
        val numberEnd: Float
    )

    private class Glyph(val char: Char) {
        val text = char.toString()
        var fromX = 0f
        var toX = 0f
        var fromSize = 0f
        var toSize = 0f
        var fromPresence = 0f
        var toPresence = 1f
        var isPlaced = false

        val isRemoved: Boolean
            get() = toPresence == 0f

        fun frozen(progress: Float): Glyph? {
            val presence = AnimUtils.lerp(fromPresence, toPresence, progress)
            if (presence <= 0f) return null
            return Glyph(char).also {
                it.fromX = AnimUtils.lerp(fromX, toX, progress)
                it.toX = it.fromX
                it.fromSize = AnimUtils.lerp(fromSize, toSize, progress)
                it.toSize = it.fromSize
                it.fromPresence = presence
                it.toPresence = presence
                it.isPlaced = true
            }
        }

        fun freeze(progress: Float) {
            fromX = AnimUtils.lerp(fromX, toX, progress)
            fromSize = AnimUtils.lerp(fromSize, toSize, progress)
            fromPresence = AnimUtils.lerp(fromPresence, toPresence, progress)
        }

        fun remove() {
            toX = fromX
            toSize = fromSize
            toPresence = 0f
        }
    }
}
