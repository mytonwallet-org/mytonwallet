package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import androidx.core.graphics.withClip
import androidx.core.view.isGone
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardTextType
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

class RadialGradientView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    companion object {
        private val GRADIENT_COLORS_LIGHT_TEXT = intArrayOf(
            Color.argb(255, 0, 0, 0),
            Color.argb(204, 0, 0, 0),
            Color.argb(128, 0, 0, 0),
            Color.argb(51, 0, 0, 0),
            Color.argb(0, 0, 0, 0)
        )

        private val GRADIENT_COLORS_DARK_TEXT = intArrayOf(
            Color.argb(255, 255, 255, 255),
            Color.argb(204, 255, 255, 255),
            Color.argb(128, 255, 255, 255),
            Color.argb(51, 255, 255, 255),
            Color.argb(0, 255, 255, 255),
        )
    }

    init {
        id = generateViewId()
    }

    private val radialPaint = Paint().apply {
        alpha = 102
        isAntiAlias = true
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)

        update()
    }

    var isTextLight = true
        set(value) {
            field = value
            update()
        }

    private val path = Path()
    var cornerRadius: Float = 0f
        set(value) {
            field = value
            update()
        }

    private fun update() {
        val gradientWidth = width
        val gradientHeight = height
        if (gradientWidth == 0 || gradientHeight == 0) return

        val colors =
            if (isTextLight) GRADIENT_COLORS_LIGHT_TEXT else GRADIENT_COLORS_DARK_TEXT

        radialPaint.shader = RadialGradient(
            0.5f * gradientWidth,
            0.5f * gradientHeight,
            gradientHeight.toFloat() * 1.33f,
            colors,
            floatArrayOf(0f, 0.25f, 0.5f, 0.75f, 1f),
            Shader.TileMode.CLAMP
        )

        path.reset()
        path.addRoundRect(
            0f, 0f, width.toFloat(), height.toFloat(),
            cornerRadius, cornerRadius,
            Path.Direction.CW
        )
        path.close()
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.withClip(path) {
            drawPaint(radialPaint)
        }
    }

    fun configure(nft: ApiNft?) {
        isTextLight =
            nft?.metadata?.mtwCardTextType == ApiMtwCardTextType.LIGHT
        isGone = when (nft?.metadata?.mtwCardType) {
            ApiMtwCardType.STANDARD -> {
                false
            }

            else -> {
                true
            }
        }
    }
}
