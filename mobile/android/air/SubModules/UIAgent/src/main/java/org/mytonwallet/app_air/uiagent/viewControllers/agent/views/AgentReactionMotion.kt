package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import kotlin.math.PI
import kotlin.math.ln
import kotlin.math.roundToLong
import kotlin.math.sqrt
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

/** The reaction cloud's and corner emoji's motion; springs are given as iOS gives them, by response and damping */
internal object AgentReactionMotion {
    // The cloud: its Ø8 dot, then its Ø16 bump, then its capsule, each this much after the one before
    const val CLOUD_STAGGER_MS = 40L
    const val CLOUD_DOT_RESPONSE = 0.3f
    const val CLOUD_DOT_DAMPING = 0.6f
    const val CLOUD_CAPSULE_RESPONSE = 0.35f
    const val CLOUD_CAPSULE_DAMPING = 0.72f

    /** The capsule starts as a circle this big at its trailing end */
    const val CLOUD_CAPSULE_START_SCALE = 0.5f

    /** The icons appear as the capsule passes them, at least this far apart */
    const val ICON_STAGGER_MS = 40L

    /**
     * The selection circle appears as Telegram's does: it grows from a dot on Telegram's spring and fades in over the
     * first half of that
     */
    const val SELECTION_GROW_MS = 400L
    const val SELECTION_FADE_MS = 200L
    const val SELECTION_START_SCALE = 0.01f

    const val PRESSED_SCALE = 0.85f
    const val PRESS_MS = 100L
    const val RELEASE_RESPONSE = 0.25f
    const val RELEASE_DAMPING = 0.6f

    /** The cloud shrinks back toward its tail's dot */
    const val CLOUD_OUT_MS = 180L
    const val CLOUD_OUT_SCALE = 0.3f
    const val FADE_MS = 150L

    /** What is left of a spring's swing when its animator ends */
    private const val SETTLED_AMPLITUDE = 0.002

    // Telegram's spring: mass 1, stiffness 555 and damping 47
    private const val TELEGRAM_SPRING_STIFFNESS = 555.0
    private const val TELEGRAM_SPRING_DAMPING = 47.0

    /** Telegram's spring over [durationMs], nearly critically damped */
    fun telegramSpring(durationMs: Long): TimeInterpolator {
        val omega = sqrt(TELEGRAM_SPRING_STIFFNESS)
        return WInterpolator.spring(
            dampingRatio = (TELEGRAM_SPRING_DAMPING / (2 * omega)).toFloat(),
            stiffness = (omega * durationMs / 1000).toFloat()
        )
    }

    /** An animator from 0 to 1 along a spring of [response] seconds and [damping], lasting until it settles */
    fun spring(response: Float, damping: Float): ValueAnimator {
        val omega = 2 * PI / response
        val seconds = ln(1 / SETTLED_AMPLITUDE) / (damping * omega)
        return ValueAnimator.ofFloat(0f, 1f).apply {
            duration = (seconds * 1000).roundToLong()
            interpolator = WInterpolator.spring(
                dampingRatio = damping,
                stiffness = (omega * seconds).toFloat()
            )
        }
    }
}
