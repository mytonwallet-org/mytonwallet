package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.LinearGradient
import kotlin.math.hypot
import android.graphics.Shader
import android.graphics.SweepGradient
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.LinearInterpolator
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import org.mytonwallet.app_air.uiagent.processors.AgentHint
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class AgentHintsSectionView(context: Context) : HorizontalScrollView(context) {

    var onHintTap: ((AgentHint) -> Unit)? = null

    private val row = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        setPadding(18.dp, 0, 16.dp, 0)
    }

    init {
        id = generateViewId()
        isHorizontalScrollBarEnabled = false
        overScrollMode = OVER_SCROLL_ALWAYS
        clipChildren = false
        clipToPadding = false
        addView(row, LayoutParams(WRAP_CONTENT, MATCH_PARENT))
    }

    override fun onInterceptTouchEvent(ev: MotionEvent?): Boolean {
        if (!isEnabled) return true
        return super.onInterceptTouchEvent(ev)
    }

    fun configure(hints: List<AgentHint>) {
        row.removeAllViews()
        for ((index, hint) in hints.withIndex()) {
            val card = AgentHintCardView(context, hint) { onHintTap?.invoke(it) }
            val lp = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                if (index > 0) marginStart = 12.dp
            }
            row.addView(card, lp)
        }
    }

    fun updateTheme() {
        for (i in 0 until row.childCount) {
            (row.getChildAt(i) as? AgentHintCardView)?.updateTheme()
        }
    }
}

@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
private class AgentHintCardView(
    context: Context,
    private val hint: AgentHint,
    private val onTap: (AgentHint) -> Unit
) : WFrameLayout(context) {

    private val titleLabel = WLabel(context)
    private val subtitleLabel = WLabel(context)
    private val bgDrawable = GradientDrawable().apply {
        cornerRadius = 18f.dp
    }
    private val borderDrawable = GradientBorderDrawable(18f.dp, 1.5f.dp)
    private val fillDrawable = GradientFillDrawable(18f.dp)
    private val initialAngle = (Math.random() * 360).toFloat()
    private val fillInitialAngle = (Math.random() * 360).toFloat()
    private val borderAnimator = ValueAnimator.ofFloat(0f, 360f).apply {
        duration = 12_000
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            val elapsed = it.animatedValue as Float
            borderDrawable.angle = initialAngle + elapsed
            fillDrawable.angle = fillInitialAngle + elapsed
            invalidate()
        }
    }

    init {
        titleLabel.setStyle(15f)
        titleLabel.typeface = WFont.SemiBold.typeface
        titleLabel.isSingleLine = true
        titleLabel.useCustomEmoji = true
        titleLabel.text = hint.title

        subtitleLabel.setStyle(15f)
        subtitleLabel.isSingleLine = true
        subtitleLabel.useCustomEmoji = true
        subtitleLabel.text = hint.subtitle

        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(16.dp, 12.dp, 16.dp, 12.dp)
            addView(titleLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            addView(subtitleLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        }

        isClickable = true
        isFocusable = true
        background = LayerDrawable(arrayOf(bgDrawable, fillDrawable))
        foreground = borderDrawable
        addView(content, LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER_VERTICAL))
        updateTheme()

        setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    animate().scaleX(0.97f).scaleY(0.97f).alpha(0.82f).setDuration(100).start()
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(100).start()
                    if (event.action == MotionEvent.ACTION_UP) onTap(hint)
                }
            }
            true
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        borderAnimator.start()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        borderAnimator.cancel()
    }

    fun updateTheme() {
        bgDrawable.setColor(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
    }
}

private class GradientFillDrawable(
    private val cornerRadius: Float,
) : Drawable() {

    var angle = 0f

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        alpha = 255
    }

    private val colors = intArrayOf(
        0x0C0088FF,  // 0%   – #0088FF 5%
        0x0C00BEFF,  // 13%  – #00BEFF 5%
        0x05B656FF,  // 25%  – #B656FF 2%
        0x0500BEFF,  // 38%  – #00BEFF 2%
        0x050088FF,  // 50%  – #0088FF 2%
        0x0C00BEFF,  // 63%  – #00BEFF 5%
        0x05B656FF,  // 75%  – #B656FF 2%
        0x0C00BEFF,  // 88%  – #00BEFF 5%
        0x0C0088FF,  // 100% – wrap back to close the loop
    )
    private val positions = floatArrayOf(0f, 0.13f, 0.25f, 0.38f, 0.50f, 0.63f, 0.75f, 0.88f, 1f)

    private val shaderMatrix = Matrix()
    private val rectF = RectF()
    private var cachedShader: LinearGradient? = null
    private var cachedCx = Float.NaN
    private var cachedCy = Float.NaN
    private var cachedRadius = Float.NaN

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        cachedShader = null
    }

    override fun draw(canvas: Canvas) {
        val bounds = bounds
        if (bounds.isEmpty) return

        val cx = bounds.exactCenterX()
        val cy = bounds.exactCenterY()
        val radius = hypot(bounds.width().toDouble(), bounds.height().toDouble()).toFloat() / 2f

        if (cachedShader == null || cachedCx != cx || cachedCy != cy || cachedRadius != radius) {
            cachedShader = LinearGradient(
                cx - radius,
                cy,
                cx + radius,
                cy,
                colors,
                positions,
                Shader.TileMode.CLAMP
            )
            cachedCx = cx
            cachedCy = cy
            cachedRadius = radius
        }

        shaderMatrix.setRotate(angle, cx, cy)
        cachedShader!!.setLocalMatrix(shaderMatrix)
        fillPaint.shader = cachedShader

        rectF.set(
            bounds.left.toFloat(),
            bounds.top.toFloat(),
            bounds.right.toFloat(),
            bounds.bottom.toFloat()
        )
        canvas.drawRoundRect(rectF, cornerRadius, cornerRadius, fillPaint)
    }

    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}

    @Suppress("OVERRIDE_DEPRECATION")
    override fun getOpacity() = PixelFormat.TRANSLUCENT
}

private class GradientBorderDrawable(
    private val cornerRadius: Float,
    private val borderWidth: Float,
) : Drawable() {

    var angle = 0f

    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = borderWidth
    }

    private val colors = intArrayOf(
        0xFF0088FF.toInt(),  // 0%   – #0088FF 100%
        0x8000BEFF.toInt(),  // 13%  – #00BEFF  50%
        0x1AB656FF,          // 25%  – #B656FF  10%
        0x1A00BEFF,          // 38%  – #00BEFF  10%
        0x1A0088FF,          // 50%  – #0088FF  10%
        0x8000BEFF.toInt(),  // 63%  – #00BEFF  50%
        0xFFB656FF.toInt(),  // 75%  – #B656FF 100%
        0xFF00BEFF.toInt(),  // 88%  – #00BEFF 100%
        0xFF0088FF.toInt(),  // 100% – wrap back to close the loop
    )
    private val positions = floatArrayOf(0f, 0.13f, 0.25f, 0.38f, 0.50f, 0.63f, 0.75f, 0.88f, 1f)

    private val shaderMatrix = Matrix()
    private val rectF = RectF()
    private var cachedShader: SweepGradient? = null
    private var cachedCx = Float.NaN
    private var cachedCy = Float.NaN

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        cachedShader = null
    }

    override fun draw(canvas: Canvas) {
        val bounds = bounds
        if (bounds.isEmpty) return

        val cx = bounds.exactCenterX()
        val cy = bounds.exactCenterY()

        if (cachedShader == null || cachedCx != cx || cachedCy != cy) {
            cachedShader = SweepGradient(cx, cy, colors, positions)
            cachedCx = cx
            cachedCy = cy
        }

        shaderMatrix.setRotate(angle, cx, cy)
        cachedShader!!.setLocalMatrix(shaderMatrix)
        borderPaint.shader = cachedShader

        val inset = borderWidth / 2f
        rectF.set(
            bounds.left + inset,
            bounds.top + inset,
            bounds.right - inset,
            bounds.bottom - inset
        )
        canvas.drawRoundRect(rectF, cornerRadius - inset, cornerRadius - inset, borderPaint)
    }

    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}

    @Suppress("OVERRIDE_DEPRECATION")
    override fun getOpacity() = PixelFormat.TRANSLUCENT
}
