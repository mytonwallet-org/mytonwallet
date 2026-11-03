package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import android.view.View
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import org.mytonwallet.app_air.uicomponents.extensions.dp

/**
 * Blur-in and blur-out transitions: opacity, a Gaussian blur of up to 8 dp where the system supports it, and a drift
 * on y. Coming in eases out; going out eases in.
 */
internal object AgentBlurTransition {
    private const val MAX_BLUR_DP = 8f

    fun animateIn(
        view: View,
        durationMs: Long,
        delayMs: Long = 0,
        fromOffsetDp: Float = 0f,
        onEnd: (() -> Unit)? = null
    ): Animator = run(
        view,
        durationMs,
        delayMs,
        DecelerateInterpolator(),
        fromOffsetDp.dp,
        0f,
        isAppearing = true,
        onEnd = onEnd
    )

    fun animateOut(
        view: View,
        durationMs: Long,
        toOffsetDp: Float = 0f,
        onEnd: (() -> Unit)? = null
    ): Animator = run(
        view,
        durationMs,
        0,
        AccelerateInterpolator(),
        0f,
        toOffsetDp.dp,
        isAppearing = false,
        onEnd = onEnd
    )

    private fun run(
        view: View,
        durationMs: Long,
        delayMs: Long,
        interpolator: TimeInterpolator,
        fromOffset: Float,
        toOffset: Float,
        isAppearing: Boolean,
        onEnd: (() -> Unit)?
    ): Animator {
        applyFrame(view, if (isAppearing) 0f else 1f, fromOffset, isBlurred = true)
        return ValueAnimator.ofFloat(0f, 1f).apply {
            duration = durationMs
            startDelay = delayMs
            this.interpolator = interpolator
            addUpdateListener {
                val fraction = it.animatedValue as Float
                val visibility = if (isAppearing) fraction else 1 - fraction
                val offset = fromOffset + (toOffset - fromOffset) * fraction
                applyFrame(view, visibility, offset, isBlurred = true)
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (isAppearing) applyFrame(view, 1f, 0f, isBlurred = false)
                    onEnd?.invoke()
                }
            })
            start()
        }
    }

    private fun applyFrame(view: View, visibility: Float, offset: Float, isBlurred: Boolean) {
        view.alpha = visibility
        view.translationY = offset
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val radius = if (isBlurred) (1 - visibility) * MAX_BLUR_DP.dp else 0f
        view.setRenderEffect(
            if (radius < 0.5f) {
                null
            } else {
                RenderEffect.createBlurEffect(radius, radius, Shader.TileMode.DECAL)
            }
        )
    }
}
