package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View
import android.view.animation.LinearInterpolator
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class TypingIndicatorView(context: Context) : View(context) {

    private val dotRadius = 3.5f.dp
    private val dotSpacing = 5f.dp
    private val dotCount = 3

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = WColor.SecondaryText.color
    }

    private var phase = 0f
    private val animator = ValueAnimator.ofFloat(0f, 3f).apply {
        duration = 1000
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            phase = it.animatedValue as Float
            invalidate()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        animator.start()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        animator.cancel()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = (dotRadius * 2 * dotCount + dotSpacing * (dotCount - 1)).toInt() + paddingLeft + paddingRight
        val height = (dotRadius * 2).toInt() + paddingTop + paddingBottom
        setMeasuredDimension(width, height)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cy = paddingTop + dotRadius
        var cx = paddingLeft + dotRadius

        for (i in 0 until dotCount) {
            val d = ((phase - i) % dotCount + dotCount) % dotCount
            val dist = minOf(d, dotCount - d).coerceAtMost(1f)
            val alpha = (1f - dist * 0.5f)
            val scale = 0.7f + 0.3f * (1f - dist)
            paint.alpha = (alpha * 180).toInt()
            canvas.drawCircle(cx, cy, dotRadius * scale, paint)
            cx += dotRadius * 2 + dotSpacing
        }
    }

    fun updateTheme() {
        paint.color = WColor.SecondaryText.color
        invalidate()
    }
}
