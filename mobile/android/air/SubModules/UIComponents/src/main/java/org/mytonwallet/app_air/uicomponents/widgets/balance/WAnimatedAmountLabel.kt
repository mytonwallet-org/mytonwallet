package org.mytonwallet.app_air.uicomponents.widgets.balance

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.text.Spannable
import android.text.SpannableString
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.util.AttributeSet
import android.util.TypedValue
import android.view.animation.LinearInterpolator
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.graphics.alpha
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt

private const val INITIAL_DELAY_IN_MS = 150f

private data class WALCharacterRect(
    val leftOffset: Float,
    val yOffsetPercent: Float,
    val alpha: Float,
    val color: Int?,
    val char: String
)

private data class WALCharacter(
    val oldLeftOffset: Float,
    val leftOffset: Float,
    var startChar: String,
    val endChar: String,
    val change: Change,
    var delay: Float = 0f,
    var charAnimationDuration: Float = 1f,
    var charColor: Int?
) {
    enum class Change {
        INC, DEC, NONE
    }

    private fun color(char: String): Int? {
        return if (char.toIntOrNull() != null || char == ".") null else charColor
    }

    var totalSteps: Int
    var startFrom0Alpha: Boolean
    var endWith0Alpha: Boolean

    init {
        val startNum = startChar.toIntOrNull()
        val endNum = endChar.toIntOrNull()

        if (startNum != null && endNum != null) {
            totalSteps = if (endNum == startNum) {
                10
            } else {
                if (change == Change.INC) {
                    if (endNum > startNum) {
                        abs(endNum - startNum)
                    } else {
                        abs(endNum + 10 - startNum)
                    }
                } else {
                    if (endNum < startNum) {
                        abs(startNum - endNum)
                    } else {
                        abs(startNum + 10 - endNum)
                    }
                }
            }
            startFrom0Alpha = false
            endWith0Alpha = false
        } else {
            if (startChar == " " && endNum != null) {
                totalSteps = 5
                startChar = if (endNum >= 5) {
                    (endNum - 5).toString()
                } else {
                    (endNum + 5).toString()
                }
                startFrom0Alpha = true
                endWith0Alpha = false
            } else if (endChar == "" && startNum != null) {
                totalSteps = 5
                startFrom0Alpha = false
                endWith0Alpha = true
            } else {
                totalSteps = 1
                startFrom0Alpha = false
                endWith0Alpha = false
            }
        }
    }

    fun currentRectangles(elapsed: Float): List<WALCharacterRect> {
        val progress = min(1f, max(0f, (elapsed - delay) / charAnimationDuration))
        val easedProgress = WInterpolator.easeInOut(progress)
        val currentLeftOffset = leftOffset * easedProgress + oldLeftOffset * (1 - easedProgress)

        if (change == Change.NONE) {
            return listOf(WALCharacterRect(currentLeftOffset, 0f, 1f, color(startChar), startChar))
        }

        val startNum = startChar.toIntOrNull()
        if (totalSteps <= 1 || startNum == null) {
            val rects = mutableListOf<WALCharacterRect>()

            val rect1 = WALCharacterRect(
                leftOffset = currentLeftOffset,
                yOffsetPercent = if (change == Change.INC) progress else -progress,
                alpha = ((if (endWith0Alpha) 1 - progress else 1f) * (1 - progress)),
                color = color(startChar),
                char = startChar
            )
            rects.add(rect1)

            if (progress > 0) {
                val rect2 = WALCharacterRect(
                    leftOffset = currentLeftOffset,
                    yOffsetPercent = if (change == Change.INC) -1 + progress else 1 - progress,
                    alpha = ((if (endWith0Alpha) 1 - progress else 1f) * progress),
                    color = color(endChar),
                    char = endChar
                )
                rects.add(rect2)
            }

            return rects
        }

        val currentStep = progress * totalSteps
        val stepProgress = currentStep - floor(currentStep)
        val currentStepChar =
            (norm(startNum + (currentStep * if (change == Change.INC) 1 else -1).toInt()) % 10).toString()
        val nextStepChar =
            (norm(startNum + ((currentStep + 1) * if (change == Change.INC) 1 else -1).toInt()) % 10)
                .toString()

        val rects = mutableListOf<WALCharacterRect>()

        val rect1 = WALCharacterRect(
            leftOffset = currentLeftOffset,
            yOffsetPercent = if (change == Change.INC) stepProgress else -stepProgress,
            alpha = (if (endWith0Alpha) (1 - progress) else 1f) *
                (if (startFrom0Alpha && currentStep < 1) 0f else 1 - stepProgress),
            color = color(currentStepChar),
            char = currentStepChar
        )
        rects.add(rect1)

        if (progress > 0) {
            val rect2 = WALCharacterRect(
                leftOffset = currentLeftOffset,
                yOffsetPercent = if (change == Change.INC) -1 + stepProgress else 1 - stepProgress,
                alpha = (if (endWith0Alpha) (1 - progress) else 1f) * stepProgress,
                color = color(nextStepChar),
                char = nextStepChar
            )
            rects.add(rect2)
        }

        return rects
    }

    private fun norm(value: Int): Int {
        return if (value >= 10) value else 10 + value
    }
}

class WAnimatedAmountLabel(
    context: Context,
    attrs: AttributeSet? = null,
) : AppCompatTextView(context, attrs) {

    init {
        id = generateViewId()
        letterSpacing = 0f
    }

    private val characters = mutableListOf<WALCharacter>()
    private val characterRects = mutableListOf<WALCharacterRect>()
    private var charHeight: Float = 0f

    private var elapsedTime: Float = 0f
    private var startTime: Double = 0.0
    private var totalWidth: Float = 0f
    private var prevWidth: Float = 0f
    var prevText: String? = null
    var morphFromTop = true
    private var morphingEnabled = true
    private var tempRenderMorphingEnabled = true
    var forceMorphLeftCharacters = false
    var firstDelayInMs: Float = 0f
    var additionalCharacterCountForTiming = 0
    var morphingDuration: Float = 1f
        private set
    private var onWidthChange: (() -> Unit)? = null
    var charColor: Int? = null
    var charSize: Int? = null

    private val paintCache = mutableMapOf<Pair<Float, Int>, Paint>()
    private var basePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        letterSpacing = this@WAnimatedAmountLabel.letterSpacing
    }

    private val backgroundExecutor = Executors.newSingleThreadExecutor()

    private var animator: ValueAnimator? = null
    private var isAnimating = false

    private val textMeasureCache = mutableMapOf<Pair<String, Float>, Float>()

    private var pendingLayoutUpdate = false
    private val layoutUpdateRunnable = Runnable {
        if (pendingLayoutUpdate) {
            requestLayout()
            pendingLayoutUpdate = false
        }
    }

    private var _protectedText: String? = null
    var mText: CharSequence?
        get() = _protectedText
        private set(value) {
            if (value == _protectedText) return

            prevText = _protectedText ?: ""
            tempRenderMorphingEnabled = morphingEnabled
            _protectedText = value.toString()

            backgroundExecutor.execute {
                processTextChange()
            }
        }

    fun setStyle(size: Float, font: WFont? = null) {
        typeface = (font ?: WFont.Regular).typeface
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)

        paintCache.clear()
        textMeasureCache.clear()

        basePaint.typeface = typeface
        basePaint.textSize = textSize
    }

    private fun color(char: String): Int? {
        return if (char.toIntOrNull() != null || char == ".") currentTextColor else charColor
    }

    fun animateText(text: String, animated: Boolean) {
        val attributedString = SpannableString(text).apply {
            text.forEachIndexed { index, character ->
                val color = color(character.toString()) ?: Color.BLACK
                setSpan(
                    ForegroundColorSpan(color),
                    index,
                    index + 1,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                charSizeFor(character.toString())?.let {
                    setSpan(
                        AbsoluteSizeSpan(it),
                        index,
                        index + 1,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
            }
        }
        morphingEnabled = animated
        if (!animated) {
            tempRenderMorphingEnabled = false
            stop()
        }
        super.setText(attributedString, BufferType.SPANNABLE)
        this.mText = text
    }

    private fun processTextChange() {
        val newText = _protectedText ?: ""
        val oldText = prevText ?: ""

        val measurements = mutableMapOf<String, Float>()
        val allChars = (newText + oldText).toSet()

        allChars.forEach { char ->
            val charStr = char.toString()
            val size = charSizeFor(charStr)?.toFloat() ?: textSize
            val key = Pair(charStr, size)

            if (!textMeasureCache.containsKey(key)) {
                basePaint.textSize = size
                textMeasureCache[key] = basePaint.measureText(charStr)
            }
            measurements[charStr] = textMeasureCache[key]!!
        }

        val newCharacters = mutableListOf<WALCharacter>()
        charHeight = basePaint.fontMetrics.run { descent - ascent }

        var oldLeftOffset = prevWidth
        prevWidth = totalWidth

        if (oldText.length > newText.length) {
            for (i in oldText.length - 1 downTo newText.length) {
                val char = oldText[i].toString()
                val oldCharSize = measurements[char] ?: 0f
                oldLeftOffset -= oldCharSize
                newCharacters.add(
                    0,
                    WALCharacter(
                        oldLeftOffset,
                        oldLeftOffset,
                        char,
                        " ",
                        WALCharacter.Change.INC,
                        charColor = charColor
                    )
                )
            }
        }

        oldLeftOffset = 0f
        var leftOffset = 0f
        var ignoreMorphingYet = !forceMorphLeftCharacters

        newText.forEachIndexed { i, newChar ->
            val oldChar = oldText.getOrNull(i) ?: ' '
            val change = if (oldChar == newChar && ignoreMorphingYet) WALCharacter.Change.NONE
            else if (morphFromTop) WALCharacter.Change.INC else WALCharacter.Change.DEC

            newCharacters.add(
                WALCharacter(
                    oldLeftOffset,
                    leftOffset,
                    oldChar.toString(),
                    newChar.toString(),
                    change,
                    charColor = charColor
                )
            )

            if (ignoreMorphingYet && change != WALCharacter.Change.NONE) {
                ignoreMorphingYet = false
            }

            oldLeftOffset += measurements[oldChar.toString()] ?: 0f
            leftOffset += measurements[newChar.toString()] ?: 0f
        }
        totalWidth = leftOffset

        for (i in newCharacters.size - 1 downTo 1) {
            newCharacters[i].delay =
                (INITIAL_DELAY_IN_MS * morphingDuration * 2 * (1 - 0.5.pow((newCharacters.size - 1 - i).toDouble()))).toFloat()
            newCharacters[i].charAnimationDuration =
                1000 * morphingDuration - newCharacters[i].delay -
                    (INITIAL_DELAY_IN_MS * morphingDuration * 2 * (1 - 0.5.pow((i + additionalCharacterCountForTiming).toDouble()))).toFloat()
        }

        post {
            synchronized(characters) {
                characters.clear()
                characters.addAll(newCharacters)
                characterRects.clear()
                characters.forEach {
                    characterRects.addAll(it.currentRectangles(0f))
                }
            }
            start()
        }
    }

    private fun start() {
        if (!morphingEnabled) {
            stop()
            return
        }

        stop()

        startTime = System.currentTimeMillis() / 1000.0 + firstDelayInMs / 1000
        isAnimating = true

        val totalDuration = (morphingDuration + firstDelayInMs * 2 / 1000) * 1000
        animator = ValueAnimator.ofFloat(0f, totalDuration).apply {
            duration = totalDuration.toLong()
            interpolator = LinearInterpolator()

            addUpdateListener { animation ->
                if (isAnimating) {
                    val animatedValue = animation.animatedValue as Float
                    updateAnimation(animatedValue)
                }
            }

            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    isAnimating = false
                    tempRenderMorphingEnabled = false
                    invalidate()
                }
            })

            start()
        }
    }

    private fun stop() {
        animator?.cancel()
        animator = null
        isAnimating = false
        removeCallbacks(layoutUpdateRunnable)
    }

    private fun updateAnimation(animatedTime: Float) {
        elapsedTime = max(0f, animatedTime)

        backgroundExecutor.execute {
            val charactersList = synchronized(characters) { characters.toList() }
            val newRects = mutableListOf<WALCharacterRect>()
            charactersList.forEach {
                newRects.addAll(it.currentRectangles(elapsedTime))
            }

            post {
                characterRects.clear()
                characterRects.addAll(newRects)

                if (prevWidth != totalWidth && !pendingLayoutUpdate) {
                    pendingLayoutUpdate = true
                    postDelayed(layoutUpdateRunnable, 8)
                } else {
                    invalidate()
                }
                onWidthChange?.invoke()
            }
        }
    }

    private fun getPaintForCharacter(char: String, color: Int?, alpha: Float): Paint {
        val size = charSizeFor(char)?.toFloat() ?: textSize
        val finalColor = color ?: currentTextColor
        val key = Pair(size, finalColor)

        val paint = paintCache.getOrPut(key) {
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = size
                typeface = this@WAnimatedAmountLabel.typeface
                letterSpacing = this@WAnimatedAmountLabel.letterSpacing
            }
        }

        paint.color = finalColor
        paint.alpha = ((finalColor.alpha) * alpha).roundToInt()

        return paint
    }

    override fun onDraw(canvas: Canvas) {
        if (!tempRenderMorphingEnabled || characters.isEmpty()) {
            super.onDraw(canvas)
            return
        }

        characterRects.forEach { charRect ->
            val paint = getPaintForCharacter(charRect.char, charRect.color, charRect.alpha)
            canvas.drawText(
                charRect.char,
                charRect.leftOffset,
                textSize / 15f + textSize + charRect.yOffsetPercent * charHeight,
                paint
            )
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        if (!tempRenderMorphingEnabled)
            return

        val progress = if (animator?.isRunning == true) {
            min(
                1f,
                (animator?.animatedValue as? Float
                    ?: 0f) / (morphingDuration * 1000 + firstDelayInMs) * 2
            )
        } else 1f

        val width = prevWidth * (1 - progress) + totalWidth * progress
        setMeasuredDimension(width.roundToInt(), measuredHeight)
    }

    val nextLabelDelay: Float
        get() = (INITIAL_DELAY_IN_MS * 2 * (1 - 0.5f.pow(1 + (text?.length ?: 1).toFloat())))

    fun reset() {
        stop()
        _protectedText?.let {
            animateText(it, false)
        }
    }

    private fun charSizeFor(character: String): Int? {
        return if (charSize != null &&
            character.toIntOrNull() == null &&
            character != "." &&
            character != " "
        )
            charSize
        else null
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stop()
    }
}
