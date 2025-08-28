package org.mytonwallet.app_air.uicomponents.drawable

import android.content.res.ColorStateList
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.RectShape
import android.graphics.drawable.shapes.RoundRectShape

class WRippleDrawable private constructor(
    color: Int,
    private val content: Drawable?,
    mask: Drawable?
): RippleDrawable(ColorStateList.valueOf(color), content, mask) {

    companion object {
        fun create(cornerRadius: Float): WRippleDrawable {
            return create(cornerRadius, cornerRadius, cornerRadius, cornerRadius)
        }

        fun create(drawable: Drawable, cornerRadius: Float): WRippleDrawable {
            return create(drawable, cornerRadius, cornerRadius, cornerRadius, cornerRadius)
        }

        fun create(drawable: Drawable): WRippleDrawable {
            return WRippleDrawable(0, drawable, ShapeDrawable(RectShape()))
        }

        fun create(rLeftTop: Float, rRightTop: Float, rLeftBottom: Float, rRightBottom: Float): WRippleDrawable {
            return create(null, rLeftTop, rRightTop, rLeftBottom, rRightBottom)
        }

        fun create(drawable: Drawable?, rLeftTop: Float, rRightTop: Float, rLeftBottom: Float, rRightBottom: Float): WRippleDrawable {
            return if (rLeftTop == 0f && rRightTop == 0f && rLeftBottom == 0f && rRightBottom == 0f) {
                WRippleDrawable(0, ColorDrawable(), ShapeDrawable(RectShape()))
            } else {
                val radii = FloatArray(8)
                radii[0] = rLeftTop
                radii[1] = rLeftTop
                radii[2] = rRightTop
                radii[3] = rRightTop
                radii[4] = rLeftBottom
                radii[5] = rLeftBottom
                radii[6] = rRightBottom
                radii[7] = rRightBottom

                val shape = RoundRectShape(radii, null, null)
                val mask = ShapeDrawable(shape)
                WRippleDrawable(0, drawable ?: ShapeDrawable(shape), mask)
            }.apply {
                backgroundColor = 0
                rippleColor = 0
            }
        }
    }

    var backgroundColor: Int
        set(value) {
            when (content) {
                is ColorDrawable -> { content.color = value }
                is ShapeDrawable -> { content.paint.color = value }
            }
        }
        get() {
            return when (content) {
                is ColorDrawable -> content.color
                is ShapeDrawable -> content.paint.color
                else -> 0
            }
        }

    var rippleColor: Int = color
        set(value) {
            if (value != field) {
                field = value
                setColor(ColorStateList.valueOf(value))
            }
        }
}
