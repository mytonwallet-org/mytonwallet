package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.core.animation.doOnEnd
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.startsWithRtlChar
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp

@SuppressLint("ViewConstructor")
class WReplaceableLabel(
    context: Context,
    private val drawableSize: Int = 13.dp,
    progressStrokeWidthDp: Float = 1f.dp,
    private val useMarquee: Boolean = true
) : WFrameLayout(context),
    WThemedView {

    private val expandSize = 14.dp
    private val roundDrawable = RoundProgressDrawable(drawableSize.toFloat(), progressStrokeWidthDp)

    private val progressInset = (progressStrokeWidthDp.dp / 2f).roundToInt()
    private var isStartAligned = false

    private var animator: ValueAnimator? = null
    private var animationProgress: Float = 0f
    private val configs = mutableListOf<Config>()

    private val prevLabel = WLabel(context).apply {
        setSingleLine()
        isHorizontalFadingEdgeEnabled = useMarquee
        ellipsize = if (useMarquee) TextUtils.TruncateAt.MARQUEE else TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
        useCustomEmoji = true
    }

    private val currentLabel = WLabel(context).apply {
        setSingleLine()
        isHorizontalFadingEdgeEnabled = useMarquee
        ellipsize = if (useMarquee) TextUtils.TruncateAt.MARQUEE else TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
        useCustomEmoji = true
    }

    private val expandDrawable = context.requireDrawableCompat(
        org.mytonwallet.app_air.icons.R.drawable.ic_expand
    ).mutate()

    private val selectDelayMs = 1_000L
    private val selectRunnable = Runnable {
        prevLabel.isSelected = true
    }

    init {
        clipChildren = false
        clipToPadding = false
        setWillNotDraw(false)
        addView(
            prevLabel,
            LayoutParams(WRAP_CONTENT, MATCH_PARENT).apply {
                gravity = Gravity.CENTER
            }
        )
        addView(
            currentLabel,
            LayoutParams(WRAP_CONTENT, MATCH_PARENT).apply {
                gravity = Gravity.CENTER
            }
        )
        updateTheme()
    }

    data class Config(
        val text: String,
        val isLoading: Boolean,
        val isExpandable: Boolean,
        val textColor: WColor,
        val textSize: Float,
        val font: WFont,
        val progressColor: WColor = WColor.SecondaryText
    )

    fun setGravity(newGravity: Int) {
        isStartAligned =
            newGravity and Gravity.HORIZONTAL_GRAVITY_MASK != Gravity.CENTER_HORIZONTAL
        prevLabel.layoutParams = (prevLabel.layoutParams as LayoutParams).apply {
            gravity = newGravity
        }
        currentLabel.layoutParams = (currentLabel.layoutParams as LayoutParams).apply {
            gravity = newGravity
        }
    }

    fun setText(config: Config, animated: Boolean = true) {
        if (!animated || configs.isEmpty()) {
            configs.clear()
            configs.add(config)
            animator?.cancel()
            animationProgress = 0f
            applyConfig(prevLabel, config)
            applyPadding(
                prevLabel,
                if (config.isLoading) 1f else 0f,
                if (config.isExpandable) 1f else 0f,
                config.text
            )
            applyConfig(currentLabel, null)
            scheduleSelection()
            invalidate()
            return
        }

        if (configs.size > 2) configs.removeAt(2)
        configs.add(config)
        if (animator?.isRunning != true) startNextAnimation()
    }

    override fun updateTheme() {
        expandDrawable.setTint(WColor.PrimaryText.color)
        invalidate()
    }

    private fun scheduleSelection() {
        if (!useMarquee) return
        prevLabel.removeCallbacks(selectRunnable)
        prevLabel.isSelected = false
        prevLabel.postDelayed(selectRunnable, selectDelayMs)
    }

    private fun applyConfig(label: WLabel, config: Config?) {
        val config = config ?: run {
            label.text = null
            return
        }
        label.apply {
            text = config.text
            val progress = if (config.isLoading) 1f else 0f
            val expand = if (config.isExpandable) 1f else 0f
            applyPadding(label, progress, expand, config.text)
            setTextColor(config.textColor)
            setStyle(config.textSize, config.font)
        }
    }

    // The progress indicator always sits on the locale start side; the expand icon sits next
    // to the end of the text, mirrored to the left when the text itself starts with an RTL char.
    private fun indicatorOnLeft() = !LocaleController.isRTL

    private fun expandOnLeft(text: CharSequence?) = text?.startsWithRtlChar() == true

    private fun applyPadding(
        label: WLabel,
        progressVisibility: Float,
        expandVisibility: Float,
        text: CharSequence?
    ) {
        val progressPadding = (progressVisibility * (drawableSize + 11.dp)).roundToInt()
        val expandPadding = (expandVisibility * expandSize).roundToInt()
        val indicatorLeft = indicatorOnLeft()
        val expandLeft = expandOnLeft(text)
        label.setPadding(
            (if (indicatorLeft) progressPadding else 0) + (if (expandLeft) expandPadding else 0),
            0,
            (if (!indicatorLeft) progressPadding else 0) + (if (!expandLeft) expandPadding else 0),
            0
        )
    }

    private fun startNextAnimation() {
        animator?.cancel()
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener {
                animationProgress = it.animatedFraction
                invalidate()
            }
            doOnEnd {
                if (configs.size > 1) configs.removeAt(0)
                animationProgress = 0f
                if (configs.size > 1) {
                    startNextAnimation()
                } else {
                    val config = configs.firstOrNull()
                    applyConfig(prevLabel, config)
                    scheduleSelection()
                }
                invalidate()
            }
            applyConfig(prevLabel, if (configs.size > 1) configs.firstOrNull() else null)
            applyConfig(currentLabel, if (configs.size > 1) configs[1] else configs[0])
            start()
        }
    }

    private val textOffset = 20f

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val progressVisibility = if (configs.size > 1) {
            val prevLoading = configs.firstOrNull()?.isLoading == true
            val nextLoading = configs.getOrNull(1)?.isLoading == true
            when {
                prevLoading && nextLoading -> 1f
                prevLoading -> 1f - labelAlphaOut(animationProgress)
                nextLoading -> labelAlphaIn(animationProgress)
                else -> 0f
            }
        } else {
            if (configs.firstOrNull()?.isLoading == true) 1f else 0f
        }
        val expandVisibility = if (configs.size > 1) {
            lerp(
                if (configs.firstOrNull()?.isExpandable == true) 1f else 0f,
                if (configs.getOrNull(1)?.isExpandable == true) 1f else 0f,
                animationProgress
            )
        } else {
            if (configs.firstOrNull()?.isExpandable == true) 1f else 0f
        }
        val widthValue = if (configs.size > 1) {
            lerp(
                prevLabel.measuredWidth.toFloat(),
                currentLabel.measuredWidth.toFloat(),
                animationProgress
            ).roundToInt()
        } else {
            prevLabel.measuredWidth
        }
        configLabels()
        drawProgress(canvas, widthValue, progressVisibility)
        drawExpand(canvas, widthValue, expandVisibility)
    }

    private fun labelAlphaOut(progress: Float) = (progress * 10 / 7f).coerceIn(0f, 1f)

    private fun labelAlphaIn(progress: Float) = ((progress - 0.3f) * 10 / 7f).coerceIn(0f, 1f)

    private fun configLabels() {
        configs.firstOrNull()?.let { config ->
            prevLabel.alpha = 1f - labelAlphaOut(animationProgress)
            prevLabel.translationY = -lerp(0f, textOffset, animationProgress)
        } ?: run {
            prevLabel.alpha = 0f
        }

        configs.getOrNull(1)?.let { config ->
            currentLabel.alpha = labelAlphaIn(animationProgress)
            currentLabel.translationY = lerp(textOffset, 0f, animationProgress)
        } ?: run {
            currentLabel.alpha = 0f
        }
    }

    private fun drawProgress(canvas: Canvas, widthValue: Int, progressVisibility: Float) {
        if (progressVisibility > 0f) invalidate() else return

        val top = 7f.dp.roundToInt() + (13.dp - drawableSize) / 2
        val indicatorLeft = indicatorOnLeft()
        val prevConfigIsLoading = configs.firstOrNull()?.isLoading == true
        val loadingConfig = if (prevConfigIsLoading) configs.firstOrNull() else configs.getOrNull(1)
        roundDrawable.color = (loadingConfig?.progressColor ?: WColor.SecondaryText).color
        roundDrawable.alpha = (progressVisibility * 255).toInt().coerceIn(0, 255)
        if (progressVisibility == 1f) {
            val textLeft = when {
                !isStartAligned -> (measuredWidth - widthValue) / 2
                LocaleController.isRTL -> measuredWidth - widthValue
                else -> 0
            }
            val left = if (indicatorLeft) textLeft else textLeft + widthValue - drawableSize
            roundDrawable.setBounds(
                left + progressInset,
                top + progressInset,
                left + drawableSize - progressInset,
                top + drawableSize - progressInset
            )
        } else {
            val label = if (prevConfigIsLoading) prevLabel else currentLabel
            val left = if (indicatorLeft) label.left else label.right - drawableSize
            val shiftedTop = top + label.translationY.roundToInt()
            roundDrawable.setBounds(
                left + progressInset,
                shiftedTop + progressInset,
                left + drawableSize - progressInset,
                shiftedTop + drawableSize - progressInset
            )
        }
        roundDrawable.draw(canvas)
    }

    private fun drawExpand(canvas: Canvas, widthValue: Int, drawVisibility: Float) {
        if (drawVisibility == 0f) return
        val alpha = (drawVisibility * 255).toInt().coerceIn(0, 255)
        expandDrawable.alpha = alpha

        val top = 7f.dp.roundToInt()
        val mirror: Boolean
        if (drawVisibility == 1f) {
            mirror = expandOnLeft(configs.firstOrNull()?.text)
            val textLeft = (measuredWidth - widthValue) / 2
            val left = if (mirror) {
                textLeft
            } else {
                textLeft + widthValue - expandSize
            }
            expandDrawable.setBounds(
                left,
                top,
                left + expandSize,
                top + expandSize
            )
        } else {
            val prevConfigHasExpand = configs.firstOrNull()?.isLoading == false
            val config = if (prevConfigHasExpand) configs.firstOrNull() else configs.getOrNull(1)
            val label = if (prevConfigHasExpand) prevLabel else currentLabel
            mirror = expandOnLeft(config?.text)
            val left = if (mirror) label.left else label.right - expandSize
            expandDrawable.setBounds(
                left,
                top + label.translationY.roundToInt(),
                left + expandSize,
                top + label.translationY.roundToInt() + expandSize
            )
        }
        if (mirror) {
            val bounds = expandDrawable.bounds
            val cx = bounds.exactCenterX()
            canvas.save()
            canvas.scale(-1f, 1f, cx, 0f)
            expandDrawable.draw(canvas)
            canvas.restore()
        } else {
            expandDrawable.draw(canvas)
        }
    }
}
