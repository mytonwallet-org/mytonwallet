package org.mytonwallet.app_air.uicomponents.widgets.balance

import android.animation.ValueAnimator
import android.animation.ValueAnimator.AnimatorUpdateListener
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Shader
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

class GradientTextView(context: Context) : AppCompatTextView(context) {
    private val animator: ValueAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
        setDuration(AnimationConstants.SLOW_ANIMATION)
        repeatMode = ValueAnimator.RESTART
        repeatCount = ValueAnimator.INFINITE
        setFloatValues(0f, 1f)

        addUpdateListener(AnimatorUpdateListener { animation: ValueAnimator? ->
            val progress = animation!!.getAnimatedValue() as Float
            updateShader(progress)
        })
    }
    private var linearGradient: LinearGradient? = null
    private val gradientMatrix = Matrix()

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        var segments = (w / 100).coerceIn(3, 15)
        if (segments % 2 == 0) segments += 1
        val colors = IntArray(segments) { i ->
            if (i % 2 == 0)
                currentTextColor.colorWithAlpha(191)
            else
                currentTextColor.colorWithAlpha(128)
        }
        val positions = FloatArray(segments) { i ->
            i.toFloat() / (segments - 1)
        }
        animator.setDuration(AnimationConstants.SLOW_ANIMATION * segments)
        linearGradient = LinearGradient(
            0f, 0.5f * height.toFloat(), width.toFloat(), 0.3f * height.toFloat(),
            colors,
            positions,
            Shader.TileMode.MIRROR
        )
        paint.setShader(linearGradient)
    }

    private fun updateShader(progress: Float) {
        gradientMatrix.setTranslate(progress * width, 0f)
        linearGradient?.setLocalMatrix(gradientMatrix)
        invalidate()
    }

    fun startLoadingAnimation() {
        animator.start()
    }

    fun stopLoadingAnimation() {
        animator.cancel()
        paint.setShader(null)
    }

    override fun onDraw(canvas: Canvas) {
        linearGradient?.let {
            if (paint.shader != it)
                paint.shader = it
        }
        super.onDraw(canvas)
    }
}
