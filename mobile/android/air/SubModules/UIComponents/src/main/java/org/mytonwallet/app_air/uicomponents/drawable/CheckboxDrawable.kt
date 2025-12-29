package org.mytonwallet.app_air.uicomponents.drawable

import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.drawable.Drawable
import android.view.animation.DecelerateInterpolator
import androidx.core.animation.doOnEnd
import androidx.core.graphics.withSave
import org.mytonwallet.app_air.uicomponents.extensions.dp
import kotlin.math.sqrt

class CheckboxDrawable(private val invalidateCallback: (() -> Unit)? = null) : Drawable() {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val checkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        style = Paint.Style.STROKE
        strokeJoin = Paint.Join.ROUND
        strokeWidth = 1.9f.dp
    }
    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.2f.dp
    }
    private val eraser = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0
        xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
    }

    private val path = Path()

    private var progress = 0f
        set(value) {
            field = value
            invalidateSelf()
            invalidateCallback?.invoke()
        }

    var isChecked = false
        private set

    fun setChecked(isChecked: Boolean, animated: Boolean) {
        if (this.isChecked == isChecked)
            return
        this.isChecked = isChecked
        animator?.cancel()
        if (animated)
            animateToProgress(if (isChecked) 1f else 0f)
        else {
            progress = if (isChecked) 1f else 0f
            invalidateSelf()
        }
    }

    private fun animateToProgress(targetProgress: Float) {
        animator = ValueAnimator.ofFloat(progress, targetProgress).apply {
            duration = 200
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                progress = it.animatedValue as Float
                invalidateSelf()
            }
            doOnEnd {
                animator = null
            }
            start()
        }
    }

    private var animator: ValueAnimator? = null

    var checkedColor: Int = 0xFF007AFF.toInt()
        set(value) {
            field = value
            invalidateSelf()
        }

    var uncheckedColor: Int = 0xFFD1D1D6.toInt()
        set(value) {
            field = value
            invalidateSelf()
        }

    var checkmarkColor: Int = Color.WHITE
        set(value) {
            field = value
            invalidateSelf()
        }

    override fun draw(canvas: Canvas) {
        val bounds = bounds
        val cx = bounds.centerX().toFloat()
        val cy = bounds.centerY().toFloat()
        val radius = bounds.width().coerceAtMost(bounds.height()) / 2f - 1f.dp

        val roundProgress = if (progress >= 0.5f) 1.0f else progress / 0.5f
        val checkProgress = if (progress < 0.5f) 0.0f else (progress - 0.5f) / 0.5f

        backgroundPaint.color = if (progress > 0f) checkedColor else uncheckedColor
        canvas.drawCircle(cx, cy, radius, backgroundPaint)

        if (roundProgress > 0f) {
            canvas.withSave {
                canvas.saveLayerAlpha(
                    cx - radius - 1f.dp,
                    cy - radius - 1f.dp,
                    cx + radius + 1f.dp,
                    cy + radius + 1f.dp,
                    255
                )

                paint.color = checkedColor
                paint.style = Paint.Style.FILL
                canvas.drawCircle(cx, cy, radius - 0.5f.dp, paint)

                if (roundProgress < 1.0f) {
                    val holeRadius = radius * (1.0f - roundProgress)
                    canvas.drawCircle(cx, cy, holeRadius, eraser)
                }
            }
        }

        // Draw checkmark
        if (checkProgress > 0) {
            checkPaint.color = checkmarkColor
            checkPaint.alpha = (255 * checkProgress).toInt()

            val scale = 0.85f
            val checkSide = 9f.dp * scale * checkProgress
            val smallCheckSide = 4.5f.dp * scale * checkProgress
            val x = cx - 1.5f.dp
            val y = cy + 3f.dp

            path.reset()
            val smallSide = sqrt(smallCheckSide * smallCheckSide / 2.0f)
            path.moveTo(x - smallSide, y - smallSide)
            path.lineTo(x, y)
            val largeSide = sqrt(checkSide * checkSide / 2.0f)
            path.lineTo(x + largeSide, y - largeSide)

            canvas.drawPath(path, checkPaint)
        }
    }

    override fun setAlpha(alpha: Int) {
        paint.alpha = alpha
        checkPaint.alpha = alpha
        backgroundPaint.alpha = alpha
    }

    override fun setColorFilter(colorFilter: ColorFilter?) {
        paint.colorFilter = colorFilter
        checkPaint.colorFilter = colorFilter
        backgroundPaint.colorFilter = colorFilter
    }

    @Deprecated("Deprecated in Java")
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT

    override fun getIntrinsicWidth(): Int = 20.dp

    override fun getIntrinsicHeight(): Int = 20.dp
}
