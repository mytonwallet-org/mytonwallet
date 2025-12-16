package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.LinearGradient
import android.graphics.Shader

open class WLinearGradientLabel(context: Context) : WLabel(context) {
    private var gradientColors: IntArray? = null

    override fun updateTheme() {
        super.updateTheme()
        applyGradient()
    }

    fun setGradientColor(gradientColors: IntArray?) {
        this.gradientColors = gradientColors
        applyGradient()
    }

    private fun applyGradient() {
        if (gradientColors == null || width == 0) {
            paint.shader = null
            return
        }

        val gradient = LinearGradient(
            0f, 0f,
            width.toFloat(), 0f,
            gradientColors!!,
            null,
            Shader.TileMode.CLAMP
        )
        paint.shader = gradient
        invalidate()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        applyGradient()
    }
}
