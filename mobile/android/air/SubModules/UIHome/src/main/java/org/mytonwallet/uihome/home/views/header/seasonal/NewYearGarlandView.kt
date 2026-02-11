package org.mytonwallet.uihome.home.views.header.seasonal

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.MotionEvent
import android.view.View
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.uihome.R

class NewYearGarlandView(context: Context) : View(context) {

    private data class Bulb(
        val x: Float,
        val y: Float,
        val color: Int
    )

    companion object {
        private const val VIEWBOX_WIDTH = 378f
        private const val VIEWBOX_HEIGHT = 72f
        private const val GLOW_SIZE = 32f
        private const val GLOW_BLUR = 10f
        private const val ON_OPACITY = 0.6f
        private const val STEP_DELAY_MS = 20L

        private val BULBS = listOf(
            Bulb(8f, 27f, Color.rgb(255, 255, 174)),
            Bulb(43f, 34f, Color.rgb(255, 179, 179)),
            Bulb(74f, 34f, Color.rgb(254, 251, 13)),
            Bulb(102f, 32f, Color.rgb(10, 255, 246)),
            Bulb(129f, 20f, Color.rgb(237, 163, 255)),
            Bulb(150f, 32f, Color.rgb(254, 251, 13)),
            Bulb(179f, 35f, Color.rgb(255, 255, 174)),
            Bulb(206f, 37f, Color.rgb(255, 179, 179)),
            Bulb(232f, 31f, Color.rgb(10, 255, 246)),
            Bulb(254f, 21f, Color.rgb(237, 163, 255)),
            Bulb(280f, 32f, Color.rgb(254, 251, 13)),
            Bulb(310f, 38f, Color.rgb(255, 179, 179)),
            Bulb(342f, 36f, Color.rgb(237, 163, 255)),
            Bulb(370f, 26f, Color.rgb(255, 255, 174)),
        )
    }

    private val garlandDrawable = context.resources.getDrawable(R.drawable.img_newyear_garland, null)
    private val bulbOpacities = FloatArray(BULBS.size) { 0f }
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var isOn = false
    private var isAnimating = false
    private var hasPlayedInitial = false
    private var animationAnimator: ValueAnimator? = null

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = (width * VIEWBOX_HEIGHT / VIEWBOX_WIDTH).toInt()
        setMeasuredDimension(width, height)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (!hasPlayedInitial) {
            hasPlayedInitial = true
            if (WGlobalStorage.getAreAnimationsActive()) {
                startAnimation(turnOn = true)
            } else {
                setAllOpacities(ON_OPACITY)
                isOn = true
                invalidate()
            }
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        animationAnimator?.cancel()
        animationAnimator = null
        isAnimating = false
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_UP) {
            toggle()
            performClick()
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return

        garlandDrawable.setBounds(0, 0, width, height)
        garlandDrawable.draw(canvas)

        val scaleX = w / VIEWBOX_WIDTH
        val scaleY = h / VIEWBOX_HEIGHT
        val scale = minOf(scaleX, scaleY)
        val bulbSize = GLOW_SIZE * scale
        val blur = GLOW_BLUR * scale

        for (i in BULBS.indices) {
            val opacity = bulbOpacities[i]
            if (opacity <= 0f) continue

            val bulb = BULBS[i]
            val cx = bulb.x / VIEWBOX_WIDTH * w
            val cy = bulb.y / VIEWBOX_HEIGHT * h

            glowPaint.color = bulb.color
            glowPaint.alpha = (opacity * 255).toInt()
            glowPaint.maskFilter = BlurMaskFilter(blur.coerceAtLeast(1f), BlurMaskFilter.Blur.NORMAL)

            canvas.drawCircle(cx, cy, bulbSize / 2f, glowPaint)
        }
    }

    private fun toggle() {
        if (isAnimating) return
        startAnimation(turnOn = !isOn)
    }

    private fun startAnimation(turnOn: Boolean) {
        if (isAnimating) return
        isAnimating = true

        animationAnimator?.cancel()

        if (!WGlobalStorage.getAreAnimationsActive()) {
            setAllOpacities(if (turnOn) ON_OPACITY else 0f)
            isOn = turnOn
            isAnimating = false
            invalidate()
            return
        }

        val totalSteps = BULBS.size
        val totalDurationMs = totalSteps * STEP_DELAY_MS

        animationAnimator = ValueAnimator.ofFloat(0f, totalSteps.toFloat()).apply {
            duration = totalDurationMs
            interpolator = null
            addUpdateListener { animator ->
                val progress = animator.animatedValue as Float
                val currentStep = progress.toInt().coerceAtMost(totalSteps - 1)

                if (turnOn) {
                    for (i in 0..currentStep) {
                        bulbOpacities[i] = ON_OPACITY
                    }
                } else {
                    val reverseStep = totalSteps - 1 - currentStep
                    for (i in totalSteps - 1 downTo reverseStep) {
                        bulbOpacities[i] = 0f
                    }
                }
                invalidate()
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    setAllOpacities(if (turnOn) ON_OPACITY else 0f)
                    isOn = turnOn
                    isAnimating = false
                    invalidate()
                }
            })
            start()
        }
    }

    private fun setAllOpacities(value: Float) {
        for (i in bulbOpacities.indices) {
            bulbOpacities[i] = value
        }
    }
}
