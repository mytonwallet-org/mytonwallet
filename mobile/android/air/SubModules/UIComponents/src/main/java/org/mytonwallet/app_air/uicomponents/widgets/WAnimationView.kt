package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.Animator
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.airbnb.lottie.LottieAnimationView
import com.airbnb.lottie.LottieDrawable
import com.airbnb.lottie.RenderMode

open class WAnimationView(context: Context) : LottieAnimationView(context) {
    companion object {
        private const val START_FALLBACK_MS = 3000L
    }

    private var pendingOnStart: (() -> Unit)? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val startFallbackRunnable = Runnable { firePendingOnStart() }

    init {
        id = generateViewId()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            // Using RenderMode.SOFTWARE seems to be much smoother on pre-pie devices.
            renderMode = RenderMode.SOFTWARE
        }
        scaleType = ScaleType.CENTER_CROP

        setFailureListener { _ ->
            firePendingOnStart()
            visibility = GONE
        }
    }

    fun play(animation: Int, repeat: Boolean = true, onStart: (() -> Unit)?) {
        try {
            setAnimatorListener(onStart)
            if (repeat) repeatCount = LottieDrawable.INFINITE
            setAnimation(animation)
            playAnimation()
        } catch (_: Exception) {
            setAnimatorListener(null)
            onStart?.invoke()
            visibility = GONE
        }
    }

    fun playFromUrl(url: String, repeat: Boolean = true, play: Boolean, onStart: (() -> Unit)?) {
        try {
            setAnimatorListener(onStart)
            if (repeat) repeatCount = LottieDrawable.INFINITE
            setAnimationFromUrl(url)
            if (play)
                playAnimation()
        } catch (_: Exception) {
            setAnimatorListener(null)
            onStart?.invoke()
            visibility = GONE
        }
    }

    private fun firePendingOnStart() {
        mainHandler.removeCallbacks(startFallbackRunnable)
        val cb = pendingOnStart ?: return
        pendingOnStart = null
        removeAllAnimatorListeners()
        cb()
    }

    private fun setAnimatorListener(onStart: (() -> Unit)?) {
        mainHandler.removeCallbacks(startFallbackRunnable)
        pendingOnStart = onStart
        removeAllAnimatorListeners()
        if (onStart == null)
            return
        addAnimatorListener(object : Animator.AnimatorListener {
            override fun onAnimationStart(animation: Animator) {
                firePendingOnStart()
            }

            override fun onAnimationEnd(animation: Animator) {}
            override fun onAnimationCancel(animation: Animator) {}
            override fun onAnimationRepeat(animation: Animator) {}
        })
        mainHandler.postDelayed(startFallbackRunnable, START_FALLBACK_MS)
    }
}
