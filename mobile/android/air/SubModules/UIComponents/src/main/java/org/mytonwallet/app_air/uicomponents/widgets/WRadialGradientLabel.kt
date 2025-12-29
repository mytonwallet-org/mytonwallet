package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.RadialGradient
import android.graphics.Shader

open class WRadialGradientLabel(context: Context) : WLabel(context) {
    var containerWidth = 0
        set(value) {
            field = value
            applyGradient()
        }
    var gradientOffset = 0
        set(value) {
            field = value
            applyGradient()
        }

    private var gradientColor1: Int = 0
    private var gradientColor2: Int = 0
    private var shouldDrawGradient: Boolean = false

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (shouldDrawGradient) {
            applyGradient()
        }
    }

    fun setTextColor(color1: Int, color2: Int, drawGradient: Boolean) {
        super.setTextColor(color2)
        gradientColor1 = color1
        gradientColor2 = color2
        shouldDrawGradient = drawGradient

        if (drawGradient) {
            applyGradient()
        } else {
            paint.shader = null
            invalidate()
        }
    }

    private fun applyGradient() {
        if (width == 0 || height == 0 || containerWidth == 0)
            return
        val centerX = width / 2f + gradientOffset
        val centerY = height / 2f
        val radius = containerWidth * 0.4f
        paint.shader = RadialGradient(
            centerX,
            centerY,
            radius,
            gradientColor1,
            gradientColor2,
            Shader.TileMode.CLAMP
        )
        invalidate()
    }
}
