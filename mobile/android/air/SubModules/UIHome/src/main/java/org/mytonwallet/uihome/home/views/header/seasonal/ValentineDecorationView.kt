package org.mytonwallet.uihome.home.views.header.seasonal

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Shader
import android.view.MotionEvent
import android.view.View
import android.view.animation.LinearInterpolator
import android.view.animation.PathInterpolator
import org.mytonwallet.uihome.R

class ValentineDecorationView(context: Context) : View(context) {

    private data class HeartConfig(
        val x: Float,
        val y: Float,
        val shiftX: Float,
        val scale: Float,
        val delayMs: Long
    )

    private data class SparkConfig(
        val x: Float,
        val y: Float,
        val delayMs: Long
    )

    companion object {
        private const val DESIGN_WIDTH = 70f
        private const val DESIGN_HEIGHT = 48f
        private const val HEART_SIZE = 7f
        private const val SPARK_SIZE = 6f
        private const val IMAGE_PULSE_DURATION = 560L
        private const val HEART_TRAIL_DURATION = 680L
        private const val SPARK_FLASH_DURATION = 420L

        private val HEARTS = listOf(
            HeartConfig(17f, 26f, -4f, 0.9f, 0),
            HeartConfig(35f, 19f, 3f, 1.0f, 70),
            HeartConfig(50f, 32f, 4f, 0.85f, 140),
        )

        private val SPARKS = listOf(
            SparkConfig(46f, 13f, 40),
            SparkConfig(26f, 36f, 110),
        )

        // CSS cubic-bezier curves — applied per-keyframe-interval, NOT to the whole animation
        private val PULSE_BEZIER = PathInterpolator(0.22f, 1f, 0.36f, 1f)
        private val HEART_BEZIER = PathInterpolator(0.16f, 1f, 0.3f, 1f)
        private val SPARK_BEZIER = PathInterpolator(0f, 0f, 0.58f, 1f) // CSS ease-out
    }

    private val imageBitmap = BitmapFactory.decodeResource(resources, R.drawable.img_valentine)
    private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val imageMatrix = Matrix()
    private val heartPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val heartPath = Path()
    private val sparkPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private var pulseProgress = -1f
    private val heartProgress = FloatArray(HEARTS.size) { -1f }
    private val sparkProgress = FloatArray(SPARKS.size) { -1f }

    private val animators = mutableListOf<ValueAnimator>()

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action == MotionEvent.ACTION_UP) {
            triggerAnimation()
            performClick()
        }
        return true
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        cancelAll()
    }

    private fun triggerAnimation() {
        cancelAll()
        startPulse()
        HEARTS.forEachIndexed { i, h -> startHeartTrail(i, h.delayMs) }
        SPARKS.forEachIndexed { i, s -> startSparkFlash(i, s.delayMs) }
    }

    // All ValueAnimators use LinearInterpolator — bezier is applied per-keyframe-interval in draw

    private fun startPulse() {
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = IMAGE_PULSE_DURATION
            interpolator = LinearInterpolator()
            addUpdateListener { pulseProgress = it.animatedValue as Float; invalidate() }
            addListener(onEnd { pulseProgress = -1f; invalidate() })
            start()
            animators.add(this)
        }
    }

    private fun startHeartTrail(index: Int, delay: Long) {
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = HEART_TRAIL_DURATION
            startDelay = delay
            interpolator = LinearInterpolator()
            addUpdateListener { heartProgress[index] = it.animatedValue as Float; invalidate() }
            addListener(onEnd { heartProgress[index] = -1f; invalidate() })
            start()
            animators.add(this)
        }
    }

    private fun startSparkFlash(index: Int, delay: Long) {
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = SPARK_FLASH_DURATION
            startDelay = delay
            interpolator = LinearInterpolator()
            addUpdateListener { sparkProgress[index] = it.animatedValue as Float; invalidate() }
            addListener(onEnd { sparkProgress[index] = -1f; invalidate() })
            start()
            animators.add(this)
        }
    }

    private fun cancelAll() {
        animators.forEach { it.cancel() }
        animators.clear()
        pulseProgress = -1f
        heartProgress.fill(-1f)
        sparkProgress.fill(-1f)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return

        val sx = w / DESIGN_WIDTH
        val sy = h / DESIGN_HEIGHT

        drawImage(canvas, w, h)

        for (i in HEARTS.indices) {
            if (heartProgress[i] >= 0f) drawHeart(canvas, HEARTS[i], heartProgress[i], sx, sy)
        }
        for (i in SPARKS.indices) {
            if (sparkProgress[i] >= 0f) drawSpark(canvas, SPARKS[i], sparkProgress[i], sx, sy)
        }
    }

    /**
     * imagePulse: cubic-bezier(0.22, 1, 0.36, 1) per-keyframe-interval
     * Keyframes: 0% → 34% (rise) → 100% (fall back)
     */
    private fun drawImage(canvas: Canvas, w: Float, h: Float) {
        canvas.save()

        val p = pulseProgress
        if (p >= 0f) {
            // CSS applies the bezier to each keyframe interval independently
            val f: Float = if (p <= 0.34f) {
                // 0% → 34%: bezier applied to local progress within this interval
                PULSE_BEZIER.getInterpolation(p / 0.34f)
            } else {
                // 34% → 100%: bezier applied, then inverted (peak → rest)
                1f - PULSE_BEZIER.getInterpolation((p - 0.34f) / 0.66f)
            }

            val dy = -2.24f * (h / DESIGN_HEIGHT) * f
            val s = 1f + 0.02f * f

            canvas.translate(w / 2f, h / 2f)
            canvas.scale(s, s)
            canvas.translate(-w / 2f, -h / 2f + dy)

            val sat = 1f + 0.2f * f
            val bri = 1f + 0.08f * f
            val cm = ColorMatrix().apply { setSaturation(sat) }
            cm.postConcat(ColorMatrix(floatArrayOf(
                bri, 0f, 0f, 0f, 0f,
                0f, bri, 0f, 0f, 0f,
                0f, 0f, bri, 0f, 0f,
                0f, 0f, 0f, 1f, 0f
            )))
            imagePaint.colorFilter = ColorMatrixColorFilter(cm)
        } else {
            imagePaint.colorFilter = null
        }

        imageMatrix.reset()
        imageMatrix.setScale(w / imageBitmap.width, h / imageBitmap.height)
        canvas.drawBitmap(imageBitmap, imageMatrix, imagePaint)
        canvas.restore()
    }

    /**
     * heartTrail: cubic-bezier(0.16, 1, 0.3, 1) per-keyframe-interval
     *
     * Transform keyframes: 0%, 46%, 100% (opacity not specified at 18% for transform)
     * Opacity keyframes:   0%, 18%, 46%, 100% (different intervals from transform)
     *
     * CSS interpolates each property between its OWN keyframes independently.
     */
    private fun drawHeart(
        canvas: Canvas, config: HeartConfig, progress: Float, sx: Float, sy: Float
    ) {
        // Transform: interpolated between keyframes 0% → 46% → 100%
        val tx: Float
        val ty: Float
        val scale: Float
        if (progress <= 0.46f) {
            val bt = HEART_BEZIER.getInterpolation(progress / 0.46f)
            tx = config.shiftX * 0.35f * bt
            ty = -7.36f * bt
            scale = config.scale + 0.1f * bt
        } else {
            val bt = HEART_BEZIER.getInterpolation((progress - 0.46f) / 0.54f)
            tx = config.shiftX * 0.35f + config.shiftX * 0.65f * bt
            ty = -7.36f + (-19.2f + 7.36f) * bt
            scale = config.scale + 0.1f + 0.1f * bt
        }

        // Opacity: interpolated between keyframes 0% → 18% → 46% → 100%
        val alpha: Float = when {
            progress <= 0.18f -> {
                // 0 → 1, with bezier
                HEART_BEZIER.getInterpolation(progress / 0.18f)
            }
            progress <= 0.46f -> {
                // 1 → 1 (no change)
                1f
            }
            else -> {
                // 1 → 0, with bezier
                1f - HEART_BEZIER.getInterpolation((progress - 0.46f) / 0.54f)
            }
        }

        if (alpha <= 0f) return

        val cx = (config.x + tx) * sx
        val cy = (config.y + ty) * sy
        val size = HEART_SIZE * scale * minOf(sx, sy)
        val half = size / 2f

        canvas.save()
        canvas.translate(cx, cy)
        canvas.rotate(45f)

        heartPaint.alpha = (alpha * 255).toInt()
        heartPaint.shader = LinearGradient(
            0f, -size * 0.75f, 0f, size * 0.75f,
            0xFFFF7A9F.toInt(), 0xFFFF3A62.toInt(),
            Shader.TileMode.CLAMP
        )

        heartPath.reset()
        heartPath.addRect(-half, -half, half, half, Path.Direction.CW)
        heartPath.addCircle(0f, -half, half, Path.Direction.CW)
        heartPath.addCircle(-half, 0f, half, Path.Direction.CW)
        canvas.drawPath(heartPath, heartPaint)

        canvas.restore()
    }

    /**
     * sparkFlash: ease-out = cubic-bezier(0, 0, 0.58, 1) per-keyframe-interval
     * Keyframes: 0% → 45% → 100%
     */
    private fun drawSpark(
        canvas: Canvas, config: SparkConfig, progress: Float, sx: Float, sy: Float
    ) {
        val alpha: Float
        val scale: Float

        if (progress <= 0.45f) {
            val bt = SPARK_BEZIER.getInterpolation(progress / 0.45f)
            alpha = bt
            scale = 0.3f + 0.85f * bt
        } else {
            val bt = SPARK_BEZIER.getInterpolation((progress - 0.45f) / 0.55f)
            alpha = 1f - bt
            scale = 1.15f - 0.75f * bt
        }

        if (alpha <= 0f) return

        val cx = config.x * sx
        val cy = config.y * sy
        val r = (SPARK_SIZE / 2f * scale * minOf(sx, sy)).coerceAtLeast(0.1f)

        sparkPaint.alpha = (alpha * 255).toInt()
        sparkPaint.shader = RadialGradient(
            cx, cy, r,
            Color.argb((alpha * 242).toInt(), 255, 131, 162),
            Color.argb(0, 255, 131, 162),
            Shader.TileMode.CLAMP
        )
        canvas.drawCircle(cx, cy, r, sparkPaint)

        sparkPaint.shader = RadialGradient(
            cx - r * 0.2f, cy - r * 0.2f, (r * 0.7f).coerceAtLeast(0.1f),
            Color.argb((alpha * 230).toInt(), 255, 255, 255),
            Color.argb(0, 255, 255, 255),
            Shader.TileMode.CLAMP
        )
        canvas.drawCircle(cx, cy, r, sparkPaint)
    }

    private fun onEnd(block: () -> Unit) = object : AnimatorListenerAdapter() {
        override fun onAnimationEnd(animation: Animator) = block()
    }
}
