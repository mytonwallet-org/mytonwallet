package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import kotlin.math.abs
import kotlin.math.sin
import kotlin.random.Random

class ConfettiView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {

    private val confetti = mutableListOf<Confetti>()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var lastRequestedAt: Long? = null
    private var isAnimating = false

    companion object {
        private const val CONFETTI_FADEOUT_TIMEOUT = 10000L
        private const val DEFAULT_CONFETTI_SIZE = 10f
        private val CONFETTI_COLORS = listOf(
            Color.parseColor("#E8BC2C"),
            Color.parseColor("#D0049E"),
            Color.parseColor("#02CBFE"),
            Color.parseColor("#5723FD"),
            Color.parseColor("#FE8C27"),
            Color.parseColor("#6CB859")
        )
    }

    fun triggerConfetti() {
        lastRequestedAt = System.currentTimeMillis()
        generateConfetti(width, height, if (height > width) 50 else 100)
        if (!isAnimating) {
            isAnimating = true
            invalidate()
        }
        postDelayed({
            confetti.clear()
            isAnimating = false
            invalidate()
        }, CONFETTI_FADEOUT_TIMEOUT)
    }

    private fun generateConfetti(w: Int, h: Int, amount: Int) {
        repeat(amount) { i ->
            val leftSide = i % 2 == 0
            val posX = if (leftSide) w * -0.1f else w * 1.1f
            val posY = h * 0.75f
            val randomX = Random.nextFloat() * w * 1.5f
            val randomY = -h / 2f - Random.nextFloat() * h
            val velocityX = if (leftSide) randomX else -randomX
            val velocityY = randomY

            confetti.add(
                Confetti(
                    posX, posY,
                    velocityX, velocityY,
                    DEFAULT_CONFETTI_SIZE,
                    CONFETTI_COLORS.random(),
                    DEFAULT_CONFETTI_SIZE,
                    Random.nextFloat() * 0.2f,
                    0f,
                    System.currentTimeMillis(),
                    0
                )
            )
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        if (!isAnimating || confetti.isEmpty()) return

        val iterator = confetti.iterator()
        val now = System.currentTimeMillis()

        while (iterator.hasNext()) {
            val c = iterator.next()
            val diff = (now - c.lastDrawnAt) / 1000f

            c.posX += c.velocityX * diff
            c.posY += c.velocityY * diff
            c.velocityX *= 0.98f
            c.velocityY += diff * 1000f

            c.flicker = c.size * abs(sin(c.frameCount * c.flickerFrequency))
            c.rotation = 5 * c.frameCount * c.flickerFrequency * (Math.PI / 180).toFloat()
            c.frameCount++
            c.lastDrawnAt = now

            if (c.posY > height + c.size) {
                iterator.remove()
                continue
            }

            paint.color = c.color
            canvas.save()
            canvas.rotate(c.rotation, c.posX, c.posY)
            canvas.drawOval(
                c.posX - c.size,
                c.posY - c.flicker,
                c.posX + c.size,
                c.posY + c.flicker,
                paint
            )
            canvas.restore()
        }

        if (confetti.isNotEmpty()) {
            postInvalidateOnAnimation()
        } else {
            isAnimating = false
        }
    }

    data class Confetti(
        var posX: Float,
        var posY: Float,
        var velocityX: Float,
        var velocityY: Float,
        val size: Float,
        val color: Int,
        var flicker: Float,
        val flickerFrequency: Float,
        var rotation: Float,
        var lastDrawnAt: Long,
        var frameCount: Int
    )
}
