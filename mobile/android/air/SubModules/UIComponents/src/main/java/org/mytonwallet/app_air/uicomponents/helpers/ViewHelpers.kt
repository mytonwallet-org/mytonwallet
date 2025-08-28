package org.mytonwallet.app_air.uicomponents.helpers

import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.graphics.drawable.LayerDrawable
import android.graphics.drawable.RippleDrawable
import android.graphics.drawable.ShapeDrawable
import android.graphics.drawable.shapes.RoundRectShape

class ViewHelpers {
    companion object {
        fun roundedShapeDrawable(topRadius: Float, bottomRadius: Float): ShapeDrawable {
            val shapeDrawable = ShapeDrawable()
            shapeDrawable.shape = RoundRectShape(
                floatArrayOf(
                    topRadius, topRadius, topRadius, topRadius,
                    bottomRadius, bottomRadius, bottomRadius, bottomRadius
                ),
                null,
                null
            )
            return shapeDrawable
        }

        fun roundedShapeDrawable(color: Int, radius: Float): ShapeDrawable {
            return roundedShapeDrawable(color, radius, radius, radius, radius)
        }

        fun roundedShapeDrawable(
            color: Int,
            topLeftRadius: Float,
            topRightRadius: Float,
            bottomRightRadius: Float,
            bottomLeftRadius: Float
        ): ShapeDrawable {
            val shapeDrawable = ShapeDrawable()
            shapeDrawable.shape = RoundRectShape(
                floatArrayOf(
                    topLeftRadius, topLeftRadius, topRightRadius, topRightRadius,
                    bottomRightRadius, bottomRightRadius, bottomLeftRadius, bottomLeftRadius
                ),
                null,
                null
            )
            shapeDrawable.paint.color = color
            return shapeDrawable
        }

        fun roundedBorderedShareDrawable(
            color: Int,
            radius: Float,
            borderColor: Int,
            borderWidth: Float,
        ): LayerDrawable {
            val outerRadius =
                floatArrayOf(radius, radius, radius, radius, radius, radius, radius, radius)
            val inset = RectF(borderWidth, borderWidth, borderWidth, borderWidth)
            val roundRectShape = RoundRectShape(outerRadius, inset, outerRadius)
            val borderDrawable = ShapeDrawable(roundRectShape).apply {
                paint.apply {
                    setColor(borderColor)
                    style = Paint.Style.STROKE
                    strokeWidth = borderWidth
                }
            }
            val backgroundDrawable = ShapeDrawable(RoundRectShape(outerRadius, null, null)).apply {
                paint.color = color
            }
            return LayerDrawable(arrayOf(backgroundDrawable, borderDrawable))
        }

        fun roundedRippleDrawable(
            background: Drawable?,
            rippleColor: Int,
            cornerRadius: Float
        ): RippleDrawable {
            val radii = FloatArray(8) { cornerRadius }
            val shape = RoundRectShape(radii, null, null)
            val mask = ShapeDrawable(shape)
            mask.paint.color = Color.WHITE

            val rippleDrawable = RippleDrawable(
                ColorStateList.valueOf(rippleColor),
                background,
                mask
            )
            return rippleDrawable
        }
    }
}
