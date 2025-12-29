package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import androidx.core.animation.doOnEnd
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import kotlin.math.roundToInt

class WReplaceableLabel(context: Context) : WFrameLayout(context), WThemedView {

    private val drawableSize = 13.dp
    private val expandSize = 14.dp
    private val roundDrawable = RoundProgressDrawable(drawableSize, 1f.dp)

    private var animator: ValueAnimator? = null
    private var animationProgress: Float = 0f
    private val configs = mutableListOf<Config>()

    private val prevLabel = WLabel(context).apply {
        setStyle(20f, WFont.SemiBold)
        setSingleLine()
        isHorizontalFadingEdgeEnabled = true
        ellipsize = TextUtils.TruncateAt.MARQUEE
        gravity = Gravity.CENTER
    }

    private val currentLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setSingleLine()
        isHorizontalFadingEdgeEnabled = true
        ellipsize = TextUtils.TruncateAt.MARQUEE
        gravity = Gravity.CENTER
    }

    private val expandDrawable = ContextCompat.getDrawable(
        context,
        org.mytonwallet.app_air.uicomponents.R.drawable.ic_expand
    )!!

    private val selectDelayMs = 1_000L
    private val selectRunnable = Runnable {
        prevLabel.isSelected = true
    }

    init {
        clipChildren = false
        clipToPadding = false
        setWillNotDraw(false)
        addView(prevLabel, LayoutParams(WRAP_CONTENT, MATCH_PARENT).apply {
            gravity = Gravity.CENTER
        })
        addView(currentLabel, LayoutParams(WRAP_CONTENT, MATCH_PARENT).apply {
            gravity = Gravity.CENTER
        })
        updateTheme()
    }

    data class Config(
        val text: String,
        val isLoading: Boolean,
    )

    fun setText(config: Config, animated: Boolean = true) {
        if (!animated || configs.isEmpty()) {
            configs.clear()
            configs.add(config)
            animator?.cancel()
            animationProgress = 0f
            applyConfig(prevLabel, config)
            applyPadding(prevLabel, if (config.isLoading) 1f else 0f)
            applyConfig(currentLabel, null)
            scheduleSelection()
            invalidate()
            return
        }

        if (configs.size > 2) configs.removeAt(2)
        configs.add(config)
        if (animator?.isRunning != true)
            startNextAnimation()
    }

    override fun updateTheme() {
        roundDrawable.color = WColor.SecondaryText.color
        expandDrawable.setTint(WColor.PrimaryText.color)
    }

    private fun scheduleSelection() {
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
            applyPadding(label, progress)
            setTextColor(if (config.isLoading) WColor.SecondaryText else WColor.PrimaryText)
            if (config.isLoading)
                setStyle(16f, WFont.Medium)
            else
                setStyle(20f, WFont.SemiBold)
        }
    }

    private fun applyPadding(label: WLabel, progressVisibility: Float) {
        label.setPadding(
            (progressVisibility * 24.dp).roundToInt(),
            0,
            ((1 - progressVisibility) * expandSize).roundToInt(),
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
                if (configs.isNotEmpty()) configs.removeAt(0)
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

        val progressVisibility = if (configs.size > 1)
            lerp(
                if (configs.firstOrNull()?.isLoading == true) 1f else 0f,
                if (configs.getOrNull(1)?.isLoading == true) 1f else 0f,
                animationProgress
            )
        else
            if (configs.firstOrNull()?.isLoading == true) 1f else 0f
        val widthValue = if (configs.size > 1)
            lerp(
                prevLabel.measuredWidth.toFloat(),
                currentLabel.measuredWidth.toFloat(),
                animationProgress
            ).roundToInt()
        else
            prevLabel.measuredWidth
        configLabels()
        drawProgress(canvas, widthValue, progressVisibility)
        drawExpand(canvas, widthValue, 1 - progressVisibility)
    }

    private fun configLabels() {
        configs.firstOrNull()?.let { config ->
            val animationProgressOut = (animationProgress * 10 / 7f).coerceIn(0f, 1f)
            prevLabel.alpha = 1f - animationProgressOut
            prevLabel.translationY = -lerp(0f, textOffset, animationProgress)
        } ?: run {
            prevLabel.alpha = 0f
        }

        configs.getOrNull(1)?.let { config ->
            val animationProgressIn = ((animationProgress - 0.3f) * 10 / 7f).coerceIn(0f, 1f)
            currentLabel.alpha = animationProgressIn
            currentLabel.translationY = lerp(textOffset, 0f, animationProgress)
        } ?: run {
            currentLabel.alpha = 0f
        }
    }

    private fun drawProgress(canvas: Canvas, widthValue: Int, progressVisibility: Float) {
        val alpha = (progressVisibility * 255).toInt().coerceIn(0, 255)
        roundDrawable.alpha = alpha
        if (progressVisibility > 0f) invalidate() else return

        val top = 7f.dp.roundToInt()
        if (progressVisibility == 1f)
            roundDrawable.setBounds(
                (measuredWidth - widthValue) / 2,
                top,
                (measuredWidth - widthValue) / 2 + drawableSize,
                top + drawableSize
            )
        else {
            val prevConfigIsLoading = configs.firstOrNull()?.isLoading == true
            val label = if (prevConfigIsLoading) prevLabel else currentLabel
            roundDrawable.setBounds(
                label.left,
                top + label.translationY.roundToInt(),
                label.left + drawableSize,
                top + label.translationY.roundToInt() + drawableSize
            )
        }
        roundDrawable.draw(canvas)
    }

    private fun drawExpand(canvas: Canvas, widthValue: Int, drawVisibility: Float) {
        if (drawVisibility == 0f) return
        val alpha = (drawVisibility * 255).toInt().coerceIn(0, 255)
        expandDrawable.alpha = alpha

        val top = 7f.dp.roundToInt()
        if (drawVisibility == 1f)
            expandDrawable.setBounds(
                (measuredWidth - widthValue) / 2 + widthValue - expandSize,
                top,
                (measuredWidth - widthValue) / 2 + widthValue,
                top + expandSize
            )
        else {
            val prevConfigHasExpand = configs.firstOrNull()?.isLoading == false
            val label = if (prevConfigHasExpand) prevLabel else currentLabel
            expandDrawable.setBounds(
                label.right - expandSize,
                top + label.translationY.roundToInt(),
                label.right,
                top + label.translationY.roundToInt() + expandSize
            )
        }
        expandDrawable.draw(canvas)
    }
}
