package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.animation.LinearInterpolator
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.widgets.particles.ParticleConfig
import org.mytonwallet.app_air.uicomponents.widgets.particles.ParticleView
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

@SuppressLint("ClickableViewAccessibility")
class WSpeedingDiamondView(context: Context) : WAnimationView(context) {

    private val slowdownHandler = Handler(Looper.getMainLooper())
    private var slowdownRunnable: Runnable? = null
    private var slowdownAnimator: ValueAnimator? = null
    private var lastBurstAtMs = 0L

    private var particleHost: ParticleView? = null
    private var burstColorPair: Array<FloatArray> =
        ParticleConfig.Companion.PARTICLE_COLORS.PURPLE_GRADIENT
    private var burstCenterShift: FloatArray = floatArrayOf(0f, -36f)

    init {
        speed = MIN_SPEED

        setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    v.animate().scaleX(SCALE_PRESSED).scaleY(SCALE_PRESSED)
                        .setDuration(SCALE_DURATION_MS).start()
                    onMove()
                }

                MotionEvent.ACTION_MOVE -> onMove()
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    v.animate().scaleX(1f).scaleY(1f)
                        .setDuration(SCALE_DURATION_MS).start()
                }
            }
            true
        }
    }

    fun start(onStart: (() -> Unit)? = null) {
        play(R.raw.diamond, repeat = true, onStart = onStart)
    }

    fun bindParticleHost(
        host: ParticleView?,
        colorPair: Array<FloatArray> = ParticleConfig.Companion.PARTICLE_COLORS.PURPLE_GRADIENT,
        centerShift: FloatArray = floatArrayOf(0f, -36f),
    ) {
        particleHost = host
        burstColorPair = colorPair
        burstCenterShift = centerShift
    }

    private fun onMove() {
        slowdownAnimator?.cancel()
        slowdownAnimator = null
        speed = MAX_SPEED

        slowdownRunnable?.let { slowdownHandler.removeCallbacks(it) }
        slowdownRunnable = Runnable { startSlowdown() }.also {
            slowdownHandler.postDelayed(it, SLOWDOWN_DELAY_MS)
        }

        triggerSparkleBurst()
    }

    private fun startSlowdown() {
        slowdownAnimator?.cancel()
        slowdownAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = SLOWDOWN_DURATION_MS
            interpolator = LinearInterpolator()
            addUpdateListener { anim ->
                val t = anim.animatedValue as Float
                val eased = WInterpolator.easeOutQuad(t)
                speed = MIN_SPEED + (MAX_SPEED - MIN_SPEED) * (1f - eased)
            }
            start()
        }
    }

    private fun triggerSparkleBurst() {
        val host = particleHost ?: return
        val now = System.currentTimeMillis()
        if (now - lastBurstAtMs < BURST_MIN_INTERVAL_MS) return
        lastBurstAtMs = now
        host.addParticleSystem(
            ParticleConfig.interactiveSparkleBurstParams(
                burstColorPair,
                centerShift = burstCenterShift,
            )
        )
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (!isAnimating) playAnimation()
    }

    override fun onVisibilityChanged(changedView: android.view.View, visibility: Int) {
        super.onVisibilityChanged(changedView, visibility)
        if (visibility == VISIBLE && !isAnimating) {
            resumeAnimation()
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        slowdownRunnable?.let { slowdownHandler.removeCallbacks(it) }
        slowdownAnimator?.cancel()
        slowdownAnimator = null
        cancelAnimation()
    }

    companion object {
        private const val MIN_SPEED = 1f
        private const val MAX_SPEED = 5f
        private const val SLOWDOWN_DELAY_MS = 300L
        private const val SLOWDOWN_DURATION_MS = 1500L
        private const val BURST_MIN_INTERVAL_MS = 8L
        private const val SCALE_PRESSED = 1.1f
        private const val SCALE_DURATION_MS = 250L
    }
}
