package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.Animator
import android.content.Context
import android.os.Build
import com.airbnb.lottie.LottieAnimationView
import com.airbnb.lottie.LottieDrawable
import com.airbnb.lottie.RenderMode

class WAnimationView(context: Context) : LottieAnimationView(context) {
    init {
        id = generateViewId()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            // Using RenderMode.SOFTWARE seems to be much smoother on pre-pie devices.
            renderMode = RenderMode.SOFTWARE
        }
        scaleType = ScaleType.CENTER_CROP

        setFailureListener { throwable ->
            visibility = GONE
        }
    }

    fun play(animation: Int, repeat: Boolean = true, onStart: () -> Unit) {
        try {
            setAnimatorListener(onStart)
            if (repeat) repeatCount = LottieDrawable.INFINITE
            setAnimation(animation)
            playAnimation()
        } catch (_: Exception) {
            visibility = GONE
        }
    }

    fun playFromUrl(url: String, repeat: Boolean = true, play: Boolean, onStart: () -> Unit) {
        try {
            setAnimatorListener(onStart)
            if (repeat) repeatCount = LottieDrawable.INFINITE
            setAnimationFromUrl(url)
            if (play)
                playAnimation()
        } catch (_: Exception) {
            visibility = GONE
        }
    }

    private fun setAnimatorListener(onStart: () -> Unit) {
        addAnimatorListener(object : Animator.AnimatorListener {
            override fun onAnimationStart(animation: Animator) {
                onStart()
            }

            override fun onAnimationEnd(animation: Animator) {}
            override fun onAnimationCancel(animation: Animator) {}
            override fun onAnimationRepeat(animation: Animator) {}
        })
    }
}
