package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.view.animation.DecelerateInterpolator
import androidx.core.graphics.ColorUtils
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils

class BackDrawable(val context: Context, close: Boolean) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val prevPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var reverseAngle = false
    private var lastFrameTime: Long = 0
    private val animationInProgress = false
    private var finalRotation = 0f
    private var currentRotation = 0f
    private var currentAnimationTime = 0
    private val alwaysClose: Boolean
    private val interpolator = DecelerateInterpolator()
    private var color = -0x1
    private var rotatedColor = -0x8a8a8b
    private var animationTime = 300.0f
    private var rotated = true
    private var arrowRotation = 0

    init {
        paint.strokeWidth = 2f.dp
        paint.strokeCap = Paint.Cap.ROUND
        prevPaint.strokeWidth = 2f.dp
        prevPaint.color = Color.RED
        alwaysClose = close
    }

    fun setColor(value: Int) {
        color = value
        invalidateSelf()
    }

    fun setRotatedColor(value: Int) {
        rotatedColor = value
        invalidateSelf()
    }

    fun setArrowRotation(angle: Int) {
        arrowRotation = angle
        invalidateSelf()
    }

    fun setRotation(rotation: Float, animated: Boolean) {
        lastFrameTime = 0
        if (currentRotation == 1f) {
            reverseAngle = true
        } else if (currentRotation == 0f) {
            reverseAngle = false
        }
        lastFrameTime = 0
        if (animated) {
            currentAnimationTime = if (currentRotation < rotation) {
                (currentRotation * animationTime).toInt()
            } else {
                ((1.0f - currentRotation) * animationTime).toInt()
            }
            lastFrameTime = System.currentTimeMillis()
            finalRotation = rotation
        } else {
            currentRotation = rotation
            finalRotation = currentRotation
        }
        invalidateSelf()
    }

    fun setAnimationTime(value: Float) {
        animationTime = value
    }

    fun setRotated(value: Boolean) {
        rotated = value
    }

    override fun draw(canvas: Canvas) {
        if (currentRotation != finalRotation) {
            if (lastFrameTime != 0L) {
                val dt = System.currentTimeMillis() - lastFrameTime

                currentAnimationTime += dt.toInt()
                currentRotation = if (currentAnimationTime >= animationTime) {
                    finalRotation
                } else {
                    if (currentRotation < finalRotation) {
                        interpolator.getInterpolation(currentAnimationTime / animationTime) * finalRotation
                    } else {
                        1.0f - interpolator.getInterpolation(currentAnimationTime / animationTime)
                    }
                }
            }
            lastFrameTime = System.currentTimeMillis()
            invalidateSelf()
        }

        paint.color =
            ColorUtils.blendARGB(color, rotatedColor, currentRotation)

        canvas.save()
        canvas.translate((intrinsicWidth / 2).toFloat(), (intrinsicHeight / 2).toFloat())
        if (arrowRotation != 0) {
            canvas.rotate(arrowRotation.toFloat())
        }
        var rotation = currentRotation
        if (!alwaysClose) {
            canvas.rotate(currentRotation * (if (reverseAngle) -225 else 135))
        } else {
            canvas.rotate(135 + currentRotation * (if (reverseAngle) -180 else 180))
            rotation = 1.0f
        }
        canvas.drawLine(
            (AnimUtils.lerp(-6.75f, -8f, rotation)).dp,
            0f,
            8.dp - (paint.strokeWidth / 2f) * (1f - rotation),
            0f,
            paint
        )
        val startYDiff: Float = (-0.25f).dp
        val endYDiff: Float = (
            AnimUtils.lerp(
                7f,
                8f,
                rotation
            )
            ).dp - (paint.strokeWidth / 4f) * (1f - rotation)
        val startXDiff: Float = (AnimUtils.lerp(-7f - 0.25f, 0f, rotation)).dp
        val endXDiff = 0f
        canvas.drawLine(startXDiff, -startYDiff, endXDiff, -endYDiff, paint)
        canvas.drawLine(startXDiff, startYDiff, endXDiff, endYDiff, paint)
        canvas.restore()
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
    }

    override fun setColorFilter(cf: ColorFilter?) {
        paint.setColorFilter(cf)
    }

    override fun getOpacity(): Int {
        return PixelFormat.TRANSPARENT
    }

    override fun getIntrinsicWidth(): Int {
        return 24.dp
    }

    override fun getIntrinsicHeight(): Int {
        return 24.dp
    }
}
