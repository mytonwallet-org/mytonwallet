package org.mytonwallet.app_air.uicomponents.widgets.balance

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.style.AbsoluteSizeSpan
import android.view.Gravity
import kotlinx.coroutines.Runnable
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getSpan
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import java.math.BigInteger
import kotlin.math.max
import kotlin.math.roundToInt

// TODO:: Optimize and unify all the labels
@SuppressLint("ViewConstructor")
class WBalanceView(
    context: Context,
    private val isScaledLabel: Boolean,
    private val decimalsVerticalOffset: Float = 0f,
    private val charSize: Int = 46.dp,
) : WView(context) {

    private val letterSpacing = 0f
    private val topMultiplier = if (isScaledLabel) 4 else 3

    private val label1: WAnimatedAmountLabel by lazy {
        WAnimatedAmountLabel(context).apply {
            gravity = Gravity.CENTER
            letterSpacing = this@WBalanceView.letterSpacing
        }
    }

    private val label2: WAnimatedAmountLabel by lazy {
        WAnimatedAmountLabel(context).apply {
            gravity = Gravity.CENTER
            letterSpacing = this@WBalanceView.letterSpacing
        }
    }

    private val fullLabel: GradientTextView by lazy {
        GradientTextView(context).apply {
            id = generateViewId()
            letterSpacing = this@WBalanceView.letterSpacing
            visibility = INVISIBLE
        }
    }

    var decimalsAlpha = 1f

    override fun setupViews() {
        super.setupViews()

        layoutDirection = LAYOUT_DIRECTION_LTR

        addView(label1)
        addView(label2)
        addView(fullLabel)
        setConstraints {
            toCenterY(label1)
            toLeft(label1)
            baseLineToBasLine(label2, label1)
            leftToRight(label2, label1)
            toRight(label2)
        }
        label2.translationX = letterSpacing * 100.dp
        label2.translationY = decimalsVerticalOffset.dp
    }

    fun setStyle(
        size: Float,
        decimalsSize: Float,
        font: WFont? = null
    ) {
        label1.setStyle(size, font)
        label2.setStyle(decimalsSize, font)
    }

    private var primaryColor: Int? = null
    private var secondaryColor: Int? = null
    fun setTextColor(
        color: Int,
        secondaryColor: Int,
        charColor: Int? = null,
        secondaryCharColor: Int? = null
    ) {
        this.primaryColor = color
        this.secondaryColor = secondaryColor
        label1.setTextColor(color)
        label1.charColor = charColor ?: secondaryColor
        if (!isScaledLabel)
            label1.charSize = charSize
        label2.setTextColor(secondaryColor)
        label2.charColor = secondaryCharColor ?: secondaryColor
        label2.alpha = decimalsAlpha
        label1.reset()
        label2.reset()
        fullLabel.setTextColor(secondaryColor)
    }

    data class AnimateConfig(
        val amount: BigInteger?,
        val decimals: Int,
        val currency: String,
        val animated: Boolean,
        val forceCurrencyToRight: Boolean
    )

    private var _currentVal: BigInteger? = null
    private var _text: String? = null
    fun animateText(animateConfig: AnimateConfig) {
        if (isAnimating && animateConfig.animated) {
            // It's animating to a number, schedule the next value
            nextValue = animateConfig
            return
        }
        runAnimateConfig(animateConfig)
    }

    private var isAnimating = false
        set(value) {
            field = value
            updateGradient()
        }

    private var nextValue: AnimateConfig? = null
    private var animateJob: Runnable? = null
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
        if (this._text == text) {
            val shouldSetSameText = isAnimating && !animateConfig.animated
            if (!shouldSetSameText) {
                return
            }
        }
        val isIncreasing =
            (animateConfig.amount ?: BigInteger.ZERO) > (_currentVal ?: BigInteger.ZERO)
        _currentVal = animateConfig.amount
        label1.morphFromTop = isIncreasing
        label2.morphFromTop = isIncreasing
        this._text = text
        val parts = text.split(".")
        isAnimating = true
        animateJob = Runnable {
            animateJob = null
            label2.setTextColor(
                (if ((animateConfig.amount
                        ?: BigInteger.valueOf(0)) >= BigInteger.valueOf(10)
                ) secondaryColor else primaryColor)
                    ?: WColor.SecondaryText.color
            )
            label1.firstDelayInMs = label2.nextLabelDelay
            label2.additionalCharacterCountForTiming =
                max(label1.text?.length ?: 0, label1.prevText?.length ?: 0)
            if (label1.text != parts[0] || !animateConfig.animated) {
                label1.animateText(parts[0], animateConfig.animated && animateConfig.amount != null)
                label2.forceMorphLeftCharacters = true
            } else {
                label2.forceMorphLeftCharacters = false
            }
            label2.animateText(
                if (parts.size > 1) ".${parts[1]}" else "",
                animateConfig.animated && animateConfig.amount != null
            )
            setFullLabelText()
            if (!animateConfig.animated)
                isAnimating = false
            else
                Handler(Looper.getMainLooper()).postDelayed({
                    if (this._text != text) {
                        // Already a non-animated text is set, this job is outdated.
                        return@postDelayed
                    }
                    isAnimating = false
                    applyNextAnimation()
                }, (1000 * (label1.morphingDuration) + label2.nextLabelDelay + 500).toLong())
        }
        if (isShowingLoadingGradient && animateConfig.animated) {
            // Fade for gradient to hide before animating the new amount
            Handler(Looper.getMainLooper()).postDelayed(
                { animateJob?.run() },
                AnimationConstants.QUICK_ANIMATION
            )
        } else {
            animateJob?.run()
        }
    }

    private fun applyNextAnimation() {
        if (nextValue == null)
            return
        runAnimateConfig(nextValue!!)
    }

    val text: String?
        get() {
            return _text
        }

    private var scale1 = 1f
    private var scale2 = 1f
    private var collapseProgress = 0f
    fun setScale(
        scale1: Float,
        scale2: Float,
        collapseProgress: Float,
    ) {
        this.scale1 = scale1
        this.scale2 = scale2
        this.collapseProgress = collapseProgress
        setFullLabelText()
        reposition()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w == 0 || !isScaledLabel)
            return
        reposition()
    }

    private fun reposition() {
        label1.pivotX = 0f
        label1.pivotY = label1.height / 2f
        label2.pivotX = 0f
        label2.pivotY = 0f
        fullLabel.pivotX = fullLabel.width.toFloat() / 2
        fullLabel.pivotY = fullLabel.height.toFloat() / 2

        label1.scaleX = scale1
        label1.scaleY = scale1
        label2.scaleX = scale2
        label2.scaleY = scale2
        fullLabel.scaleX = scale1
        fullLabel.scaleY = scale1

        label2.translationY =
            decimalsVerticalOffset - collapseProgress * (label1.textSize - label2.textSize) / 12f

        val scaledLabel1Width = label1.width * scale1
        val scaledLabel2Width = label2.width * scale2
        val totalWidth = scaledLabel1Width + scaledLabel2Width

        val startX = (label1.width + label2.width - totalWidth) / 2f
        label2.translationX = -label1.width + startX + scaledLabel1Width
        label2.translationY =
            topMultiplier * label2.top * (1 - scale2) + label2.baseline * (1 - scale2) - label1.baseline * (1 - scale1)
        label1.translationX = label1.left + label2.x - scaledLabel1Width
    }

    var isLoading: Boolean = false
        set(value) {
            field = value
            setFullLabelText()
            updateGradient()
        }

    private fun setFullLabelText() {
        if (label1.mText.isNullOrEmpty()) {
            fullLabel.text = null
            return
        }
        val spannable = SpannableStringBuilder()
        spannable.append(label1.getSpan(label1.mText?.toString()))
        spannable.append(
            label2.getSpan(
                label2.mText.toString(),
                (label2.textSize + collapseProgress * (label1.textSize - label2.textSize)).roundToInt()
            )
        )
        if (!isScaledLabel &&
            label1.mText?.toString()?.firstOrNull()?.toString()?.toIntOrNull() == null &&
            label1.mText?.toString()?.firstOrNull()?.toString() != "." &&
            spannable.isNotEmpty()
        )
            spannable.setSpan(
                AbsoluteSizeSpan(charSize),
                0,
                1,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        fullLabel.text = spannable
    }

    private var isShowingLoadingGradient = false
    private fun updateGradient() {
        val shouldShowGradient = isLoading && !isAnimating
        if (shouldShowGradient) {
            if (!isShowingLoadingGradient) {
                isShowingLoadingGradient = true
                fullLabel.apply {
                    setFullLabelText()
                    visibility = VISIBLE
                    alpha = 0f
                    startLoadingAnimation()
                    fadeIn()
                }
            }
            if (label1.alpha > 0f) {
                label1.fadeOut()
                label2.fadeOut()
                fullLabel.fadeIn()
            }
        } else if (isShowingLoadingGradient) {
            label1.apply {
                alpha = 1f
                fadeIn()
            }
            label2.apply {
                alpha = decimalsAlpha
                fadeIn(targetAlpha = decimalsAlpha)
            }
            fullLabel.fadeOut {
                if (isLoading && !isAnimating) return@fadeOut
                fullLabel.apply {
                    stopLoadingAnimation()
                    visibility = INVISIBLE
                }
                isShowingLoadingGradient = false
            }
        }
    }

    val scaledWidth: Int
        get() {
            return (label1.width * scale1 + label2.width * scale2).roundToInt()
        }
}
