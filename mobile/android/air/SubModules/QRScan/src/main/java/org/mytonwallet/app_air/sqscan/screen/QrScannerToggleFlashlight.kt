package org.mytonwallet.app_air.sqscan.screen

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import me.vkryl.core.fromToArgb
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp

class QrScannerToggleFlashlight @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    companion object {
        const val BACKGROUND_DARK = 0x40000000
        const val BACKGROUND_LIGHT = 0x80FFFFFF.toInt()
    }


    private val path = Path()
    private val pathReverse = Path()
    private val drawableLight = ContextCompat.getDrawable(context, R.drawable.ic_flashlight_75)
    private val drawableDark = ContextCompat.getDrawable(context, R.drawable.ic_flashlight_75)
    private val backgroundPaintLight = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = BACKGROUND_DARK
    }
    private val backgroundPaintDark = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = BACKGROUND_LIGHT
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        drawableLight?.setBounds(0, 0, measuredWidth, measuredHeight)
        drawableDark?.setBounds(0, 0, measuredWidth, measuredHeight)
        rebuildPath()
    }

    private val isEnabled =
        BoolAnimator(220L, AnimatorUtils.DECELERATE_INTERPOLATOR, false) { _, _, _, _ ->
            rebuildPath()
            invalidate()
        }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val factor = isEnabled.floatValue
        if (factor == 0f) {
            drawDisabled(canvas)
        } else if (factor == 1f) {
            drawEnabled(canvas)
        } else {
            if (isEnabled.value) {
                canvas.save()
                canvas.clipPath(path)
                drawEnabled(canvas)
                canvas.restore()
                canvas.save()
                canvas.clipPath(pathReverse)
                drawDisabled(canvas)
                canvas.restore()
            } else {
                canvas.save()
                canvas.clipPath(path)
                drawDisabled(canvas)
                canvas.restore()
                canvas.save()
                canvas.clipPath(pathReverse)
                drawEnabled(canvas)
                canvas.restore()
            }
        }
    }

    fun toggle(): Boolean {
        isEnabled.changeValue(!isEnabled.value, isAttachedToWindow)
        return isEnabled.value
    }

    private fun rebuildPath() {
        val cx = measuredWidth / 2f
        val cy = measuredHeight / 2f

        val s = if (isEnabled.value) {
            isEnabled.floatValue
        } else {
            1f - isEnabled.floatValue
        }
        val r = maxOf(measuredWidth, measuredHeight) / 2f

        ripple.rippleColor = fromToArgb(0x10FFFFFF, 0x10000000, isEnabled.floatValue)

        path.reset()
        path.addCircle(cx, cy, r * s, Path.Direction.CW)

        pathReverse.reset()
        pathReverse.addCircle(cx, cy, r, Path.Direction.CW)
        pathReverse.addCircle(cx, cy, r * s, Path.Direction.CCW)
    }

    private fun drawDisabled(canvas: Canvas) {
        drawableLight?.draw(canvas)
    }

    private fun drawEnabled(canvas: Canvas) {
        drawableDark?.draw(canvas)
    }

    private val rippleBackground = object : Drawable() {
        override fun draw(canvas: Canvas) {
            val cx = measuredWidth / 2f
            val cy = measuredHeight / 2f
            val r = maxOf(measuredWidth, measuredHeight) / 2f

            val factor = isEnabled.floatValue

            if (factor == 0f) {
                canvas.drawCircle(cx, cy, r, backgroundPaintLight)
            } else if (factor == 1f) {
                canvas.drawCircle(cx, cy, r, backgroundPaintDark)
            } else {
                if (isEnabled.value) {
                    canvas.drawPath(path, backgroundPaintDark)
                    canvas.drawPath(pathReverse, backgroundPaintLight)
                } else {
                    canvas.drawPath(path, backgroundPaintLight)
                    canvas.drawPath(pathReverse, backgroundPaintDark)
                }
            }
        }

        override fun setAlpha(alpha: Int) {

        }

        override fun setColorFilter(colorFilter: ColorFilter?) {

        }

        override fun getOpacity(): Int {
            return PixelFormat.UNKNOWN
        }
    }
    private val ripple = WRippleDrawable.create(rippleBackground, 75f.dp / 2)

    init {
        background = ripple
        drawableLight?.setTint(Color.WHITE)
        drawableDark?.setTint(Color.BLACK)
    }
}
