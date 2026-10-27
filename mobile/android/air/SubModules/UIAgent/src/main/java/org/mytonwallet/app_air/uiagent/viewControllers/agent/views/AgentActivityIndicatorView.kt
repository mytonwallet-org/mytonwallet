package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import android.text.TextPaint
import android.text.TextUtils
import android.view.View
import android.view.animation.LinearInterpolator
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.sp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

class AgentActivityIndicatorView(context: Context) : View(context) {

    private val iconSize = 24.dp
    private val iconGap = 4.dp
    private val minHeight = 40.dp

    private val icon = context.getDrawableCompat(R.drawable.ic_agent_filled)
    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = WFont.Medium.typeface
        textSize = adaptiveFontSize(17f).sp
    }
    private val gradientPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
    }
    private val gradientMatrix = Matrix()
    private var gradientWidth = 0
    private var gradientIsDark: Boolean? = null

    private val text = LocaleController.getString("\$agent_analyzing")
    private val textWidth = textPaint.measureText(text)
    private val textBaselineOffset = textPaint.fontMetrics.let { -(it.ascent + it.descent) / 2f }
    private var displayText = text
    private var displayTextWidth = textWidth
    private var textLeft = 0f
    private var textBaseline = 0f
    private var renderingActive = true
    private var isAggregatedVisible = false

    private var shimmerProgress = 0f
    private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 5000
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            shimmerProgress = it.animatedValue as Float
            invalidate()
        }
    }

    init {
        contentDescription = text
        setPaddingRelative(20.dp, 0, 14.dp, 0)
    }

    override fun onVisibilityAggregated(isVisible: Boolean) {
        super.onVisibilityAggregated(isVisible)
        isAggregatedVisible = isVisible
        updateAnimation()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        animator.cancel()
        shimmerProgress = 0f
        isAggregatedVisible = false
    }

    fun setRenderingActive(active: Boolean) {
        if (renderingActive == active) return
        renderingActive = active
        updateAnimation()
    }

    private fun updateAnimation() {
        val shouldAnimate = renderingActive && isAttachedToWindow && isAggregatedVisible &&
            WGlobalStorage.getAreAnimationsActive()
        if (shouldAnimate) {
            if (!animator.isStarted) {
                animator.start()
            } else if (animator.isPaused) {
                animator.resume()
            }
        } else if (animator.isStarted && !animator.isPaused) {
            animator.pause()
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = paddingLeft + iconSize + iconGap +
            textWidth.toInt() + paddingRight
        setMeasuredDimension(
            resolveSize(width, widthMeasureSpec),
            minHeight + paddingTop + paddingBottom
        )
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val availableTextWidth = w - paddingLeft - paddingRight - iconSize - iconGap
        displayText = TextUtils.ellipsize(
            text,
            textPaint,
            availableTextWidth.coerceAtLeast(0).toFloat(),
            TextUtils.TruncateAt.END
        ).toString()
        displayTextWidth = textPaint.measureText(displayText)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        val isRtl = layoutDirection == LAYOUT_DIRECTION_RTL
        val contentTop = paddingTop
        val contentHeight = height - paddingTop - paddingBottom
        val iconLeft = if (isRtl) width - paddingStart - iconSize else paddingStart
        textLeft = if (isRtl) {
            iconLeft - iconGap - displayTextWidth
        } else {
            (iconLeft + iconSize + iconGap).toFloat()
        }
        val iconTop = contentTop + (contentHeight - iconSize) / 2
        textBaseline = contentTop + contentHeight / 2f + textBaselineOffset
        icon?.setBounds(iconLeft, iconTop, iconLeft + iconSize, iconTop + iconSize)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val isRtl = layoutDirection == LAYOUT_DIRECTION_RTL
        val layer = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
        icon?.draw(canvas)
        canvas.drawText(displayText, textLeft, textBaseline, textPaint)
        updateGradient()
        val shift = 2 * width * shimmerProgress
        gradientMatrix.setTranslate(if (isRtl) -shift else shift, 0f)
        gradientPaint.shader?.setLocalMatrix(gradientMatrix)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), gradientPaint)
        canvas.restoreToCount(layer)
    }

    private fun updateGradient() {
        val isDark = ThemeManager.isDark
        if (gradientWidth == width && gradientIsDark == isDark) return
        gradientWidth = width
        gradientIsDark = isDark
        val edgeColor = Color.parseColor(if (isDark) "#469CEC" else "#2C92F0")
        val midColor = Color.parseColor("#00BEFF")
        gradientPaint.shader = LinearGradient(
            0f,
            0f,
            2f * width,
            0f,
            intArrayOf(edgeColor, midColor, Color.parseColor("#B656FF"), midColor, edgeColor),
            floatArrayOf(0f, 0.2f, 0.5f, 0.8f, 1f),
            Shader.TileMode.REPEAT
        )
    }
}
