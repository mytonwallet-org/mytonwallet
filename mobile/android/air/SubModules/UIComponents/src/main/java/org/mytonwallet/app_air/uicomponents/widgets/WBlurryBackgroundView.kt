package org.mytonwallet.app_air.uicomponents.widgets;

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Shader
import eightbitlab.com.blurview.BlurView
import eightbitlab.com.blurview.BlurViewFacade
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class WBlurryBackgroundView(
    context: Context,
    val fadeSide: Side?,
    val overrideBlurRadius: Float? = null
) : BlurView(context), WThemedView {

    enum class Side {
        TOP,
        BOTTOM;
    }

    init {
        id = generateViewId()
    }

    private var configured = false
    override fun onAttachedToWindow() {
        if (isPlaying != false)
            super.onAttachedToWindow()
        // else: should not call the super method to prevent unwanted blur resume!
        if (configured)
            return
        configured = true
        setupViews()
    }

    fun setupViews() {
        setBlurRadius(overrideBlurRadius ?: if (ThemeManager.isDark) 10f else 20f)
        updateTheme()
    }

    private var overrideOverlayColor: WColor? = null
        set(value) {
            field = value
            solidBackgroundColor = value?.color
                ?: (if (ThemeManager.uiMode.hasRoundedCorners) WColor.SecondaryBackground.color else WColor.Background.color)
        }

    private var overlayAlpha: Int? = null

    private var solidBackgroundColor =
        overrideOverlayColor?.color
            ?: (if (ThemeManager.uiMode.hasRoundedCorners) WColor.SecondaryBackground.color else WColor.Background.color)

    fun setOverlayColor(overlayColor: WColor, alpha: Int? = null): BlurViewFacade {
        overrideOverlayColor = overlayColor
        overlayAlpha = alpha
        val alpha = alpha ?: if (ThemeManager.isDark) 230 else 180
        return super.setOverlayColor(overrideOverlayColor!!.color.colorWithAlpha(alpha))
    }

    override fun updateTheme() {
        setBlurRadius(if (ThemeManager.isDark) 10f else 20f)

        solidBackgroundColor =
            overrideOverlayColor?.color
                ?: (if (ThemeManager.uiMode.hasRoundedCorners) WColor.SecondaryBackground.color else WColor.Background.color)

        val alpha = overlayAlpha ?: if (ThemeManager.isDark) 230 else 180
        val color = solidBackgroundColor.colorWithAlpha(alpha)
        setOverlayColor(color)
        updateLinearGradient()
    }

    private val fadeHeight = 10f.dp
    var shader = LinearGradient(
        0f,
        0f,
        0f,
        fadeHeight,
        solidBackgroundColor,
        Color.TRANSPARENT,
        Shader.TileMode.CLAMP
    )
    val paint = Paint().apply {
        PorterDuffXfermode(PorterDuff.Mode.DST_IN)
        shader = this.shader
    }

    private fun updateLinearGradient() {
        when (fadeSide) {
            Side.TOP -> {
                shader = LinearGradient(
                    0f,
                    0f,
                    0f,
                    fadeHeight,
                    solidBackgroundColor,
                    Color.TRANSPARENT,
                    Shader.TileMode.CLAMP
                )
            }

            Side.BOTTOM -> {
                shader = LinearGradient(
                    0f,
                    (height - fadeHeight),
                    0f,
                    height.toFloat(),
                    Color.TRANSPARENT,
                    solidBackgroundColor,
                    Shader.TileMode.CLAMP
                )
            }

            else -> {
                return
            }
        }
        paint.shader = shader
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        updateLinearGradient()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        when (fadeSide) {
            Side.TOP -> {
                canvas.drawRect(0f, 0f, width.toFloat(), fadeHeight, paint)
            }

            Side.BOTTOM -> {
                canvas.drawRect(0f, (height - fadeHeight), width.toFloat(), height.toFloat(), paint)
            }

            null -> {
                return
            }
        }
    }

    private var isPlaying: Boolean? = null
    fun resumeBlurring() {
        isPlaying = true
        setBlurAutoUpdate(true)
    }
    fun pauseBlurring() {
        isPlaying = false
        setBlurAutoUpdate(false)
    }
}
