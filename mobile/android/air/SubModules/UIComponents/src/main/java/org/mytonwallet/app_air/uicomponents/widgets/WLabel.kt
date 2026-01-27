package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.text.Layout
import android.text.Spanned
import android.text.SpannedString
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.CharacterStyle
import android.util.TypedValue
import android.view.Gravity
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.graphics.withClip
import androidx.core.graphics.withTranslation
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.textOffset
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.findMatches
import org.mytonwallet.app_air.walletbasecontext.utils.isSameDayAs
import org.mytonwallet.app_air.walletbasecontext.utils.isSameYearAs
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import java.math.BigInteger
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

open class WLabel(context: Context) : AppCompatTextView(context), WThemedView {
    init {
        if (id == NO_ID) {
            id = generateViewId()
        }
        gravity = if (LocaleController.isRTL) Gravity.RIGHT else Gravity.LEFT
    }

    override var isTinted = false

    private var keyword: String? = null
    var highlightRanges: List<IntRange> = emptyList()
        set(value) {
            field = value
            highlightPath = null
            invalidate()
        }
    private var highlightPath: Path? = null
    private val dilationPaint = Paint().apply {
        style = Paint.Style.STROKE
        // extend area to make sure all content fit
        strokeWidth = 1.5f
        strokeJoin = Paint.Join.ROUND
        strokeCap = Paint.Cap.ROUND
    }

    private val datePattern by lazy {
        when (WGlobalStorage.getLangCode()) {
            "ru" -> "d MMMM"
            else -> "MMMM d"
        }
    }

    private val fullDatePattern by lazy {
        when (WGlobalStorage.getLangCode()) {
            "ru" -> "d MMMM yyyy"
            else -> "MMMM d, yyyy"
        }
    }

    private val monthAndDayFormat by lazy {
        SimpleDateFormat(datePattern, Locale(WGlobalStorage.getLangCode()))
    }

    private val fullDateFormat by lazy {
        SimpleDateFormat(fullDatePattern, Locale(WGlobalStorage.getLangCode()))
    }

    private var textOffset = 0
    fun setStyle(size: Float, font: WFont? = null) {
        typeface = (font ?: WFont.Regular).typeface
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
        textOffset = when (font) {
            WFont.NunitoSemiBold, WFont.NunitoExtraBold -> {
                0
            }

            else -> {
                FontManager.activeFont.textOffset
            }
        }
    }

    fun setLineHeight(size: Float) {
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, size)
    }

    fun setAmount(
        amount: BigInteger,
        decimals: Int,
        currency: String,
        currencyDecimals: Int,
        smartDecimals: Boolean,
        showPositiveSign: Boolean = false,
        forceCurrencyToRight: Boolean = false,
    ) {
        val newText = amount.toString(
            decimals = decimals,
            currency = currency,
            currencyDecimals = if (smartDecimals) amount.smartDecimalsCount(currencyDecimals) else currencyDecimals,
            showPositiveSign = showPositiveSign,
            forceCurrencyToRight = forceCurrencyToRight,
            roundUp = false
        )
        if (text != newText)
            text = newText
    }

    fun setAmount(
        amount: Double?,
        decimals: Int,
        currency: String,
        currencyDecimals: Int,
        smartDecimals: Boolean,
        showPositiveSign: Boolean = false
    ) {
        text = amount?.toString(
            decimals = decimals,
            currency = currency,
            currencyDecimals = currencyDecimals,
            smartDecimals = smartDecimals,
            showPositiveSign = showPositiveSign
        )
    }

    fun setTextIfChanged(newText: String?) {
        if (text == newText)
            return
        text = newText
    }

    fun setUserFriendlyDate(dt: Date) {
        val now = Date()
        if (now.isSameDayAs(dt)) {
            text = LocaleController.getString("Today")
        } else {
            val sameYear = now.isSameYearAs(dt)
            text =
                if (sameYear) monthAndDayFormat.format(dt) else fullDateFormat.format(dt)
        }
    }

    private var themedColor: WColor? = null
    private var themedHighlightColor: WColor? = null

    fun setTextColor(color: WColor?) {
        themedColor = color
        updateTheme()
    }

    fun setHighlightColor(color: WColor?) {
        themedHighlightColor = color
        invalidate()
    }

    override fun updateTheme() {
        themedColor?.let {
            setTextColor(it.color)
        }
    }

    fun animateTextColor(endColor: Int, duration: Long = AnimationConstants.VERY_QUICK_ANIMATION) {
        if (currentTextColor == endColor)
            return
        val colorAnimator = ValueAnimator.ofArgb(currentTextColor, endColor)
        colorAnimator.duration = duration
        colorAnimator.addUpdateListener { animator ->
            val animatedColor = animator.animatedValue as Int
            setTextColor(animatedColor)
        }
        colorAnimator.start()
    }

    fun highlight(keyword: String) {
        highlight(keyword = keyword, text = text.toString())
    }

    private fun highlight(keyword: String, text: String) {
        this.keyword = keyword
        this.highlightRanges = text.findMatches(keyword)
    }

    fun resetHighlight() {
        this.keyword = null
        highlightRanges = emptyList()
    }

    override fun onTextChanged(
        text: CharSequence,
        start: Int,
        lengthBefore: Int,
        lengthAfter: Int
    ) {
        super.onTextChanged(text, start, lengthBefore, lengthAfter)
        keyword?.takeIf { it.isNotEmpty() }?.let { highlight(it, text.toString()) }
    }

    var applyFontOffsetFix = false

    @SuppressLint("WrongCall")
    override fun onDraw(canvas: Canvas) {
        val highlightPath = obtainHighlightPath()
        if (applyFontOffsetFix && textOffset != 0) {
            canvas.withTranslation(0f, textOffset.toFloat()) {
                onDraw(this, highlightPath)
            }
        } else {
            onDraw(canvas, highlightPath)
        }
    }

    fun calcWidth(): Int {
        val textWidth = (text as? SpannedString)?.let { spannable ->
            StaticLayout.Builder.obtain(spannable, 0, spannable.length, paint, Int.MAX_VALUE)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .build().getLineWidth(0)
        } ?: run {
            paint.measureText(text.toString())
        }
        return (textWidth + paddingLeft + paddingRight).roundToInt()
    }

    private fun onDraw(canvas: Canvas, highlightPath: Path?) {
        if (highlightPath == null) {
            super.onDraw(canvas)
        } else {
            highlightPath.fillType = Path.FillType.INVERSE_WINDING
            canvas.withClip(highlightPath) {
                super.onDraw(this)
            }
            highlightPath.fillType = Path.FillType.WINDING
            drawHighlight(canvas, highlightPath)
        }
    }

    private fun drawHighlight(canvas: Canvas, clipPath: Path) {
        val color = themedHighlightColor?.color ?: return
        val originalColor = paint.color
        paint.color = color

        val dx = totalPaddingLeft.toFloat()
        val dy = totalPaddingTop.toFloat()

        canvas.withTranslation(dx, dy) {
            withClip(clipPath) {
                layout.draw(this)
            }
        }
        paint.color = originalColor
    }

    private fun obtainHighlightPath(): Path? {
        highlightPath?.let { return it }

        if (highlightRanges.isEmpty()) {
            return null
        }
        val textLength = text?.length ?: 0
        if (textLength == 0) {
            return null
        }

        val resultPath = Path()
        val text = layout.text
        val textString = text.toString()
        val activePaint = TextPaint(layout.paint)

        for (range in highlightRanges) {
            val start = range.first.coerceIn(0, textLength)
            val end = range.last.coerceIn(0, textLength)
            if (start > end) {
                continue
            }

            if (start == end) {
                // one letter -> exact glyph
                addExactGlyphPath(resultPath, start, text, activePaint, textString)
            } else {
                // fast method to add path for all glyphs
                if (end - start > 1) {
                    val middlePath = Path()
                    layout.getSelectionPath(start, end + 1, middlePath)
                    resultPath.op(middlePath, Path.Op.UNION)
                }
                // first glyph - always exact
                addExactGlyphPath(resultPath, start, text, activePaint, textString)
                // last glyph - always exact
                addExactGlyphPath(resultPath, end, text, activePaint, textString)
            }
        }
        // to fil all content correctly - add extra space around
        return dilatePath(resultPath).also { highlightPath = it }
    }

    private fun dilatePath(basePath: Path): Path {
        val dilatedPath = Path()
        // generate outline path
        dilationPaint.getFillPath(basePath, dilatedPath)
        // add outline to original
        dilatedPath.op(basePath, Path.Op.UNION)
        return dilatedPath
    }

    private fun addExactGlyphPath(
        targetPath: Path,
        index: Int,
        text: CharSequence,
        paint: TextPaint,
        textString: String
    ) {
        if (text is Spanned) {
            val spans = text.getSpans(index, index + 1, CharacterStyle::class.java)
            paint.set(layout.paint)
            for (span in spans) {
                span.updateDrawState(paint)
            }
        }

        val line = layout.getLineForOffset(index)
        val x = layout.getPrimaryHorizontal(index)
        val y = layout.getLineBaseline(line).toFloat()

        val glyphPath = Path()
        paint.getTextPath(textString, index, index + 1, x, y, glyphPath)
        targetPath.op(dilatePath(glyphPath), Path.Op.UNION)
    }
}
