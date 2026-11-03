package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

import android.content.Context
import android.graphics.Canvas
import android.graphics.Outline
import android.view.View
import android.view.ViewOutlineProvider

/**
 * Card-tilt sheen over a badge's glass background. Kept out of the glass view so per-frame tilt
 * redraws never re-record it under an outer glass capture, which would blank its blur.
 */
class CardBadgeLightView(context: Context) : View(context) {
    private var light: CardBadgeLight? = null

    var radius = 0f
        set(value) {
            if (field == value) return
            field = value
            invalidateOutline()
        }

    init {
        id = generateViewId()
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, radius)
            }
        }
        clipToOutline = true
    }

    fun setTilt(x: Float?, y: Float?) {
        if (x == null || y == null) {
            if (light != null) {
                light = null
                invalidate()
            }
            return
        }
        val light = light ?: CardBadgeLight().also { light = it }
        if (light.setTilt(x, y)) invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        light?.draw(canvas, width, height)
    }
}
