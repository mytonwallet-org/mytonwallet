package org.mytonwallet.app_air.uicomponents.commonViews

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.SweepGradient
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.LinearInterpolator
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
class WAgentHintView(
    context: Context,
    title: CharSequence,
    contentVerticalPadding: Int = 10.dp,
    animatePressAlpha: Boolean = true,
    showsIcon: Boolean = true,
    titleMaxLines: Int = 2,
    onTap: () -> Unit
) : WFrameLayout(context) {

    companion object {
        private val LIGHT_TITLE_GRADIENT_COLORS = intArrayOf(
            0xFF005DAF.toInt(),
            0xFF007BA5.toInt(),
            0xFF7D2EBA.toInt()
        )
        private val DARK_TITLE_GRADIENT_COLORS = intArrayOf(
            0xFF6DADE6.toInt(),
            0xFF5EB6D4.toInt(),
            0xFFC48CEE.toInt()
        )
        private val TITLE_GRADIENT_POSITIONS = floatArrayOf(0f, 0.4f, 1f)

        // Stop alphas (20% / 50% / 20%) scaled by an overall 24% opacity.
        private val LIGHT_FILL_GRADIENT_COLORS = intArrayOf(
            0x0C0088FF,
            0x1F00BEFF,
            0x0CB656FF
        )

        // Stop alphas (40% / 60% / 40%) scaled by an overall 24% opacity.
        private val DARK_FILL_GRADIENT_COLORS = intArrayOf(
            0x180088FF,
            0x2500BEFF,
            0x18B656FF
        )

        private const val DARK_FADE_COLOR = 0xFF202020.toInt()
    }

    private var titleGradientColors = LIGHT_TITLE_GRADIENT_COLORS

    private val titleLabel = WLabel(context)
    private val iconView = AppCompatImageView(context).apply {
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_agent_hint_arrow)
        if (LocaleController.isRTL) scaleX = -1f
    }
    private val bgDrawable = GradientDrawable().apply {
        cornerRadius = 22f.dp
    }
    private val bgFadeDrawable = GradientDrawable(
        GradientDrawable.Orientation.TOP_BOTTOM,
        intArrayOf(0, 0)
    ).apply {
        cornerRadius = 22f.dp
    }
    private val borderDrawable = GradientBorderDrawable(22f.dp, 0.75f.dp)
    private val fillDrawable = GradientFillDrawable(22f.dp, LocaleController.isRTL)
    private val initialAngle = (Math.random() * 360).toFloat()
    private val borderAnimator = ValueAnimator.ofFloat(0f, 360f).apply {
        duration = 12_000
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            val elapsed = it.animatedValue as Float
            borderDrawable.angle = initialAngle + elapsed
            invalidate()
        }
    }

    init {
        titleLabel.setStyle(16f, WFont.Medium)
        titleLabel.isSingleLine = titleMaxLines == 1
        titleLabel.maxLines = titleMaxLines
        titleLabel.ellipsize = TextUtils.TruncateAt.END
        titleLabel.useCustomEmoji = true
        titleLabel.text = title
        titleLabel.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            updateTitleShader()
        }

        val content = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingRelative(16.dp, contentVerticalPadding, 16.dp, contentVerticalPadding)
            if (showsIcon) {
                addView(iconView, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            }
            addView(
                titleLabel,
                LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    if (showsIcon) marginStart = 6.dp
                }
            )
        }

        isClickable = true
        isFocusable = true
        background = LayerDrawable(arrayOf(bgFadeDrawable, fillDrawable, bgDrawable))
        foreground = borderDrawable
        addView(content, LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER_VERTICAL))
        updateTheme()

        setOnClickListener { onTap() }
        var isTouchAccepted = false
        setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    isTouchAccepted = alpha > 0f
                    if (isTouchAccepted) {
                        val animator = animate().scaleX(0.97f).scaleY(0.97f)
                        if (animatePressAlpha) animator.alpha(0.82f)
                        animator.setDuration(100).start()
                    }
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val shouldPerformClick = isTouchAccepted && alpha > 0f &&
                        event.action == MotionEvent.ACTION_UP
                    isTouchAccepted = false
                    val animator = animate().scaleX(1f).scaleY(1f)
                    if (animatePressAlpha && alpha > 0f) animator.alpha(1f)
                    animator.setDuration(100).start()
                    if (shouldPerformClick) performClick()
                }
            }
            true
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updateBorderAnimation()
    }

    override fun onDetachedFromWindow() {
        borderAnimator.cancel()
        super.onDetachedFromWindow()
    }

    override fun onVisibilityChanged(changedView: View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        updateBorderAnimation()
    }

    fun updateTheme() {
        val isDark = ThemeManager.isDark
        bgDrawable.setColor(WColor.ThumbBackground.color.colorWithAlpha(41)) // 16%
        val fadeColor = if (isDark) DARK_FADE_COLOR else WColor.Background.color
        bgFadeDrawable.colors = intArrayOf(
            fadeColor,
            fadeColor.colorWithAlpha(0)
        )
        fillDrawable.setColors(
            if (isDark) DARK_FILL_GRADIENT_COLORS else LIGHT_FILL_GRADIENT_COLORS
        )
        titleGradientColors =
            if (isDark) DARK_TITLE_GRADIENT_COLORS else LIGHT_TITLE_GRADIENT_COLORS
        titleLabel.setTextColor(titleGradientColors[0])
        updateTitleShader()
    }

    private fun updateTitleShader() {
        val width = titleLabel.width.toFloat()
        if (width <= 0f) return
        val (fromX, toX) = if (LocaleController.isRTL) width to 0f else 0f to width
        titleLabel.paint.shader = LinearGradient(
            fromX,
            0f,
            toX,
            0f,
            titleGradientColors,
            TITLE_GRADIENT_POSITIONS,
            Shader.TileMode.CLAMP
        )
        titleLabel.invalidate()
    }

    fun setTitle(title: CharSequence) {
        titleLabel.text = title
    }

    private fun updateBorderAnimation() {
        if (isAttachedToWindow && isShown) {
            if (!borderAnimator.isStarted) borderAnimator.start()
        } else {
            borderAnimator.cancel()
        }
    }
}

private class GradientFillDrawable(private val cornerRadius: Float, private val isRtl: Boolean) :
    Drawable() {

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    private var colors = intArrayOf(0, 0, 0)

    private val rectF = RectF()

    fun setColors(colors: IntArray) {
        val oriented = if (isRtl) colors.reversedArray() else colors
        if (oriented.contentEquals(this.colors)) return
        this.colors = oriented
        updateShader()
        invalidateSelf()
    }

    override fun onBoundsChange(bounds: Rect) {
        super.onBoundsChange(bounds)
        updateShader()
    }

    private fun updateShader() {
        val bounds = bounds
        fillPaint.shader = if (bounds.isEmpty) {
            null
        } else {
            LinearGradient(
                bounds.left.toFloat(),
                bounds.exactCenterY(),
                bounds.right.toFloat(),
                bounds.exactCenterY(),
                colors,
                null,
                Shader.TileMode.CLAMP
            )
        }
    }

    override fun draw(canvas: Canvas) {
        val bounds = bounds
        if (bounds.isEmpty || fillPaint.shader == null) return
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
    private val borderWidth: Float
) : Drawable() {

    var angle = 0f

    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = borderWidth
    }

    private val colors = intArrayOf(
        0x8000BEFF.toInt(),
        0x8000BEFF.toInt(),
        0x800088FF.toInt(),
        0x80B656FF.toInt(),
        0x8000BEFF.toInt()
    )
    private val positions = floatArrayOf(
        0f,
        0.14425f,
        0.38464f,
        0.75f,
        1f
    )

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
