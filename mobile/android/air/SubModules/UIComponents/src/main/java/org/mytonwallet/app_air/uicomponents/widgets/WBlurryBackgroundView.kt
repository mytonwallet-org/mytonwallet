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
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
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
        updateTheme()
    }

    private var overrideOverlayColor: WColor? = null
        set(value) {
            field = value
            solidBackgroundColor = value?.color ?: WColor.SecondaryBackground.color
        }

    private var overlayAlpha: Int? = null

    private var solidBackgroundColor =
        overrideOverlayColor?.color ?: WColor.SecondaryBackground.color

    fun setOverlayColor(overlayColor: WColor, alpha: Int? = null): BlurViewFacade {
        overrideOverlayColor = overlayColor
        overlayAlpha = alpha
        val alpha = alpha ?: if (ThemeManager.isDark) 200 else 140
        return super.setOverlayColor(overrideOverlayColor!!.color.colorWithAlpha(alpha))
    }

    override fun updateTheme() {
        val blurEnabled = WGlobalStorage.isBlurEnabled()
        setBlurEnabled(blurEnabled)

        solidBackgroundColor =
            overrideOverlayColor?.color ?: WColor.SecondaryBackground.color

        if (blurEnabled) {
            val blurRadius =
                (overrideBlurRadius ?: if (ThemeManager.isDark) 14f else 16f).coerceAtMost(25f)
            setBlurRadius(blurRadius)
            val alpha = overlayAlpha ?: if (ThemeManager.isDark) 200 else 140
            val color = solidBackgroundColor.colorWithAlpha(alpha)
            setOverlayColor(color)
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
        } else {
            // When blur is disabled, use solid opaque background
            setOverlayColor(android.graphics.Color.TRANSPARENT)
            setBackgroundColor(solidBackgroundColor)
        }
        updateLinearGradient()
        invalidate()
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

        // Don't draw gradient when rounded toolbars are off
        if (ViewConstants.TOOLBAR_RADIUS == 0f) return

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
        post {
            if (isPlaying == true) {
                setBlurAutoUpdate(true)
            }
        }
    }

    fun pauseBlurring() {
        isPlaying = false
        post {
            if (isPlaying == false) {
                setBlurAutoUpdate(false)
            }
        }
    }
}
