package org.mytonwallet.app_air.uicomponents.widgets.balance

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.os.Handler
import android.os.Looper
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.graphics.withScale
import androidx.core.graphics.withTranslation
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getCenterAlignBaseline
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import java.math.BigInteger
import java.util.concurrent.Executors
import java.util.concurrent.Future
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt

class WBalanceView(context: Context) : AppCompatTextView(context), WThemedView {

    // Properties //////////////////////////////////////////////////////////////////////////////////
    var primaryColor: Int? = null
    var secondaryColor: Int? = null
    var currencySize = 46f
    var primarySize = 52f
    var decimalsSize = 38f
    var decimalsAlpha = 255
    var smartDecimalsAlpha = false
    var reducedDecimalsAlpha = 191

    // When true, decimals use primaryColor when amount < 10, secondaryColor when >= 10
    var smartDecimalsColor = false
    var defaultHeight = 56.dp
    var onTotalWidthChanged: ((value: Int) -> Unit)? = null
    var onAnimationStateChanged: ((isAnimating: Boolean) -> Unit)? = null

    // Container width is used to measure gradient width
    var containerWidth = 0
        set(value) {
            if (field == value) return
            field = value
            applyGradient()
            invalidate()
        }

    // Animating ///////////////////////////////////////////////////////////////////////////////////
    companion object {
        const val INITIAL_DELAY_IN_MS = 150
        const val PREFERRED_MORPHING_DURATION = 1500
    }

    var morphingDuration = PREFERRED_MORPHING_DURATION
    var changeDelay = 500L

    data class AnimateConfig(
        val amount: BigInteger?,
        val decimals: Int,
        val currency: String,
        val animated: Boolean,
        // `setInstantly` should be true if the first frame must be rendered with no delay and block main thread
        val setInstantly: Boolean,
        val forceCurrencyToRight: Boolean
    )

    private var _currentVal: AnimateConfig? = null
    private var _prevText: List<WBalanceViewCharacter> = emptyList()
    private var _text: List<WBalanceViewCharacter> = emptyList()
    private var _str: String? = null
    var balanceBaseline: Float = 0f
        private set

    fun animateText(animateConfig: AnimateConfig) {
        if (isAnimating && animateConfig.animated) {
            // It's animating to a number, schedule the next value
            nextValue = animateConfig
            return
        }
        runAnimateConfig(animateConfig)
    }

    private var nextValue: AnimateConfig? = null
    var isAnimating = false
        private set
    private var morphFromTop = true
    private fun runAnimateConfig(animateConfig: AnimateConfig) {
        val text = animateConfig.amount?.toString(
            animateConfig.decimals,
            animateConfig.currency,
            animateConfig.amount.smartDecimalsCount(animateConfig.decimals),
            false,
            forceCurrencyToRight = animateConfig.forceCurrencyToRight
        ) ?: ""
        // Clear next value
        nextValue = null
        if (this._str == text) {
            val shouldSetSameText = isAnimating && !animateConfig.animated
            if (!shouldSetSameText) {
                return
            }
        }
        _str = text
        val isIncreasing =
            (animateConfig.amount ?: BigInteger.ZERO) > (_currentVal?.amount ?: BigInteger.ZERO)
        _currentVal = animateConfig
        val amountDouble = animateConfig.amount?.toDouble()?.div(
            10.0.pow(animateConfig.decimals)
        ) ?: 0.0
        val isLargeAmount = kotlin.math.abs(amountDouble) >= 10
        if (smartDecimalsAlpha) {
            decimalsAlpha = if (isLargeAmount) reducedDecimalsAlpha else 255
        }
        morphFromTop = isIncreasing
        this._prevText = _text
        var size = primarySize.dp
        var color = primaryColor
        var decimalsPart = false
        var left = 0f
        val textMeasureCache = mutableMapOf<Pair<Char, Float>, Float>()
        prevIntegerPartWidth = integerPartWidth
        integerPartWidth = 0f
        elapsedTime = 0
        val basePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = this@WBalanceView.typeface
        }
        this._text = _str?.mapIndexed { i, character ->
            if (!decimalsPart && !character.isDigit() && i > 0 && character != ' ') {
                size = decimalsSize.dp
                color = if (smartDecimalsColor && !isLargeAmount) (primaryColor
                    ?: WColor.PrimaryText.color) else secondaryColor
                decimalsPart = true
                integerPartWidth = left
            }
            val isBaseCurrency = i == 0 && !character.isDigit()
            val charSize = if (isBaseCurrency) currencySize.dp else size
            val key = Pair(character, charSize)
            basePaint.textSize = charSize
            if (!textMeasureCache.containsKey(key)) {
                basePaint.measureText(character.toString()).let {
                    if (character == ' ')
                        textMeasureCache[key] = it / 2
                    else
                        textMeasureCache[key] = it
                }
            }
            val charLeft =
                left + (if (i > 0) getKerning(basePaint, _str!![i - 1], character) else 0f)
            left = charLeft + textMeasureCache[key]!!
            WBalanceViewCharacter(
                character,
                charSize,
                overrideColor = color,
                decimalsPart,
                isBaseCurrency,
                charLeft
            )
        } ?: emptyList()
        balanceBaseline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = primarySize.dp
            typeface = this@WBalanceView.typeface
        }.fontMetrics.getCenterAlignBaseline(defaultHeight / 2f)
        if (integerPartWidth == 0f)
            integerPartWidth = left
        prevWidth = totalWidth
        totalWidth = left
        isAnimating = true
        if (!animateConfig.animated ||
            _prevText.isEmpty() ||
            _text.isEmpty()
        ) {
            isAnimating = false
        } else
            Handler(Looper.getMainLooper()).postDelayed({
                if (this._str != text) {
                    // Already a non-animated text is set, this job is outdated.
                    return@postDelayed
                }
                isAnimating = false
                applyNextAnimation()
            }, morphingDuration + changeDelay)
        animateTextChange(setInstantly = animateConfig.setInstantly)
    }

    private fun getKerning(
        paint: Paint,
        prev: Char,
        curr: Char
    ): Float {
        if (prev in '0'..'9' && curr in '0'..'9') return 0f

        val chars = charArrayOf(prev, curr)

        val prevAdvance = paint.getRunAdvance(
            chars, 0, 1,
            0, 1,
            false, 1
        )

        val combinedAdvance = paint.getRunAdvance(
            chars, 0, 2,
            0, 2,
            false, 2
        )

        val currAdvance = paint.getRunAdvance(
            chars, 1, 2,
            1, 2,
            false, 2
        )

        return combinedAdvance - prevAdvance - currAdvance
    }

    private fun applyNextAnimation() {
        if (nextValue == null)
            return
        runAnimateConfig(nextValue!!)
    }

    val text: String?
        get() {
            return _str
        }

    override fun updateTheme() {
        if (primaryColor == null || secondaryColor == null) {
            _currentVal?.let {
                this._str = null
                animateText(it.copy(animated = false))
            }
        }
    }

    // SCALE ///////////////////////////////////////////////////////////////////////////////////////
    var scale1 = 1f
        private set
    private var scale2 = 1f
    var offset2 = (-1f).dp
        private set

    fun setScale(
        scale1: Float,
        scale2: Float,
        offset2: Float,
    ) {
        candidateScale1 = scale1
        candidateScale2 = scale2
        candidateOffset2 = offset2
        if (animatingCharacters.isNotEmpty())
            reposition(onBackground = true)
    }

    // PROCESS ANIMATIONS //////////////////////////////////////////////////////////////////////////
    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private var currentBackgroundTask: Future<*>? = null
    private var animator: ValueAnimator? = null
    private var elapsedTime: Int = 0
    private var pendingUpdateRunnable: Runnable? = null
    private var prevWidth = 0f
    private var prevIntegerPartWidth = 0f
    private var totalWidth: Float = 0f
        set(value) {
            field = value
            onTotalWidthChanged?.invoke(value.roundToInt())
        }
    private var _width = 0
    private var _widthOffset = 0f
    private var integerPartWidth = 0f
    private var animatingCharacters = mutableListOf<WBalanceViewAnimatingCharacter>()
    private val drawingCharacterRects = mutableListOf<WBalanceViewDrawingCharacterRect>()
    private val paintCache = mutableMapOf<Pair<Float, Int>, Paint>()

    private fun animateTextChange(setInstantly: Boolean) {
        val newText = _text
        val oldText = _prevText
        val animatingCharacters = mutableListOf<WBalanceViewAnimatingCharacter>()

        var ignoreMorphingYet = true
        for (i in 0 until max(oldText.size, newText.size)) {
            val oldChar = oldText.getOrNull(i)
            val newChar = newText.getOrNull(i)

            val change =
                if (oldChar == newChar && ignoreMorphingYet) WBalanceViewAnimatingCharacter.Change.NONE
                else if (morphFromTop) WBalanceViewAnimatingCharacter.Change.INC else WBalanceViewAnimatingCharacter.Change.DEC
            if (ignoreMorphingYet && change != WBalanceViewAnimatingCharacter.Change.NONE) {
                ignoreMorphingYet = false
            }

            animatingCharacters.add(
                WBalanceViewAnimatingCharacter(
                    oldChar,
                    newChar,
                    change
                )
            )
        }

        val durationPlusInitial = (PREFERRED_MORPHING_DURATION + INITIAL_DELAY_IN_MS) / 1000f
        var leadingNones = 0
        for (i in 0 until animatingCharacters.size) {
            if (animatingCharacters[i].change == WBalanceViewAnimatingCharacter.Change.NONE) {
                leadingNones += 1
                animatingCharacters[i].delay = 0
                animatingCharacters[i].charAnimationDuration = 1
            } else {
                break
            }
        }
        for (i in animatingCharacters.size - 1 downTo leadingNones) {
            animatingCharacters[i].delay =
                (INITIAL_DELAY_IN_MS * durationPlusInitial * 2 * (1 - 0.5.pow((animatingCharacters.size - 1 - i).toDouble()))).roundToInt()
            animatingCharacters[i].charAnimationDuration =
                (1000 * durationPlusInitial - animatingCharacters[i].delay -
                    INITIAL_DELAY_IN_MS * durationPlusInitial * 2 * (1 - 0.5.pow((i).toDouble()))).roundToInt()
        }

        synchronized(this@WBalanceView.animatingCharacters) {
            this.animatingCharacters = animatingCharacters
            currentBackgroundTask?.cancel(true)
            drawingCharacterRects.clear()
            this.animatingCharacters.forEach {
                drawingCharacterRects.addAll(
                    it.currentRectangles(
                        0,
                        scale1,
                        scale2,
                        offset2,
                        prevIntegerPartWidth,
                        integerPartWidth,
                        decimalsAlpha
                    )
                )
            }
        }
        animatingCharacters.firstOrNull { it.charAnimationDuration > 1 }?.let {
            morphingDuration = it.delay + it.charAnimationDuration
        }
        start(setInstantly)
    }

    private fun start(setInstantly: Boolean) {
        stop()

        if (!isAnimating) {
            elapsedTime = Int.MAX_VALUE
            reposition(onBackground = !setInstantly)
            return
        }

        val totalDuration = morphingDuration
        elapsedTime = 0
        if (setInstantly)
            reposition(onBackground = false)
        onAnimationStateChanged?.invoke(true)
        animator = ValueAnimator.ofInt(0, totalDuration).apply {
            duration = totalDuration.toLong()

            addUpdateListener { animation ->
                elapsedTime = lerp(
                    0f,
                    totalDuration.toFloat(),
                    WInterpolator.easeOut(animation.animatedFraction)
                ).roundToInt().coerceAtLeast(0)
                reposition(onBackground = true)
            }

            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationCancel(animation: Animator) {
                    super.onAnimationCancel(animation)
                    elapsedTime = totalDuration
                    onAnimationEnd(animation)
                }

                override fun onAnimationEnd(animation: Animator) {
                    isAnimating = false
                    reposition(onBackground = true)
                    animator = null
                    onAnimationStateChanged?.invoke(false)
                }
            })

            start()
        }
    }

    private fun stop() {
        animator?.cancel()
        animator = null
    }

    var candidateScale1: Float? = null
    var candidateScale2: Float? = null
    var candidateOffset2: Float? = null
    fun reposition(onBackground: Boolean) {
        val action = {
            val scale1Val = candidateScale1 ?: this.scale1
            val scale2Val = candidateScale2 ?: this.scale2
            val offset2Val = candidateOffset2 ?: this.offset2
            val charactersList = synchronized(animatingCharacters) { animatingCharacters }
            val newRects = mutableListOf<WBalanceViewDrawingCharacterRect>()
            charactersList.forEachIndexed { i, char ->
                if (Thread.interrupted()) {
                    return@forEachIndexed
                }
                newRects.addAll(
                    char.currentRectangles(
                        elapsedTime,
                        scale1Val,
                        scale2Val,
                        offset2Val,
                        prevIntegerPartWidth,
                        integerPartWidth,
                        decimalsAlpha
                    )
                )
            }

            val updateUi = {
                val progress = if (isAnimating)
                    elapsedTime / morphingDuration.toFloat()
                else 1f

                val newWidth = lerp(
                    prevIntegerPartWidth * scale1Val + (prevWidth - prevIntegerPartWidth) * scale2Val,
                    integerPartWidth * scale1Val + (totalWidth - integerPartWidth) * scale2Val,
                    progress
                )

                val sizeChanged = _width != newWidth.roundToInt()
                val shouldUpdateRects = isAnimating || sizeChanged || !onBackground
                if (shouldUpdateRects) {
                    _width = newWidth.roundToInt()
                    _widthOffset =
                        newWidth - newWidth.roundToInt() + (if (_width % 2 == 1) -0.5f else 0f)
                    drawingCharacterRects.clear()
                    drawingCharacterRects.addAll(newRects)
                    candidateScale1?.let {
                        this.scale1 = it
                        candidateScale1 = null
                    }
                    candidateScale2?.let {
                        this.scale2 = it
                        candidateScale2 = null
                    }
                    candidateOffset2?.let {
                        this.offset2 = it
                        candidateOffset2 = null
                    }
                    requestLayout()
                }
                invalidate()
            }

            if (!Thread.interrupted()) {
                if (onBackground) {
                    pendingUpdateRunnable?.let { removeCallbacks(it) }
                    pendingUpdateRunnable = Runnable {
                        if (charactersList == animatingCharacters)
                            updateUi()
                        pendingUpdateRunnable = null
                    }
                    post(pendingUpdateRunnable)
                } else {
                    updateUi()
                }
            }
        }

        if (onBackground) {
            currentBackgroundTask?.cancel(false)
            currentBackgroundTask = backgroundExecutor?.submit {
                action()
            }
        } else {
            currentBackgroundTask?.cancel(true)
            currentBackgroundTask = null
            action()
        }
    }

    private var drawGradient = false
    private var gradientShader: RadialGradient? = null

    fun updateColors(primaryColor: Int, secondaryColor: Int, drawGradient: Boolean) {
        if (this.primaryColor == primaryColor && this.secondaryColor == secondaryColor && this.drawGradient == drawGradient)
            return
        this.primaryColor = primaryColor
        this.secondaryColor = secondaryColor
        this.drawGradient = drawGradient

        if (drawGradient && _width > 0) {
            applyGradient()
        } else {
            gradientShader = null
        }

        paintCache.clear()

        stop()
        _currentVal?.copy(animated = false)?.let { it ->
            this._str = null
            animateText(it)
        }
    }

    private fun getPaintForCharacter(characterRect: WBalanceViewDrawingCharacterRect): Paint {
        val key = Pair(characterRect.textSize, characterRect.color)
        val paint = paintCache.getOrPut(key) {
            Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = characterRect.textSize
                typeface = this@WBalanceView.typeface
                color = characterRect.color
            }
        }
        paint.alpha = ((characterRect.alpha) * alpha).roundToInt()

        if (drawGradient && gradientShader != null) {
            paint.shader = gradientShader
        } else {
            paint.shader = null
        }

        return paint
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(_width, defaultHeight)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)

        applyGradient()
    }

    private fun applyGradient() {
        if (drawGradient && _width > 0 && containerWidth > 0) {
            val centerY = defaultHeight / 2f
            val radius = _width.toFloat() / 2f
            gradientShader = RadialGradient(
                containerWidth * 0.36f - (containerWidth - width) / 2f,
                centerY,
                radius,
                intArrayOf(primaryColor ?: 0, secondaryColor ?: 0),
                floatArrayOf(0f, 1f),
                Shader.TileMode.CLAMP
            )
        } else {
            gradientShader = null
        }
    }

    override fun onDraw(canvas: Canvas) {
        drawingCharacterRects.forEach { charRect ->
            charRect.char?.let { char ->
                val paint = getPaintForCharacter(charRect)
                val scale = lerp(scale1, scale2, charRect.scaleMultiplier)

                val pivotX = charRect.leftOffset - _widthOffset
                val pivotY = defaultHeight / 2f
                val offsetY = defaultHeight * (1 - scale1) / 2 + charRect.offsetY

                canvas.withTranslation(0f, offsetY) {
                    withScale(scale, scale, pivotX, pivotY) {
                        drawText(
                            char.toString(),
                            charRect.leftOffset - _widthOffset,
                            (balanceBaseline + charRect.yOffsetPercent * charRect.textSize * 1.05f) * scale,
                            paint
                        )
                    }
                }
            }
        }
    }

    private var interruptedAnimation = false
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (interruptedAnimation) {
            interruptedAnimation = false
            elapsedTime = morphingDuration
            reposition(false)
        }
    }

    fun interruptAnimation() {
        if (isAnimating) {
            stop()
            isAnimating = false
            interruptedAnimation = true
        }
    }
}
