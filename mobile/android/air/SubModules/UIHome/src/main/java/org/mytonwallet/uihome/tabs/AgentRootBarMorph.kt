package org.mytonwallet.uihome.tabs

import android.view.Choreographer
import android.view.View
import androidx.core.view.isInvisible
import androidx.core.view.updateLayoutParams
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.uihome.tabs.views.HomeSearchField

/**
 * The root toolbar turning into the Agent chat list's question bar as paging commits to the Agent tab, and back.
 *
 * The search field shrinks into a search circle at its leading edge, the "+" button shrinks away where the bar's
 * microphone appears, and the list's field grows in beside the circle; all of them swell mid-way. The circle stays
 * at its leading anchor while it fades under a chat or a question being written, as the list's field widens over it.
 */
internal class AgentRootBarMorph(
    private val searchView: HomeSearchField,
    private val actionsButton: View,
    private val actionsIcon: View,
    private val circleButton: View,
    /** The search field's width as the toolbar lays it out on the other tabs */
    private val fullSearchWidth: () -> Int,
    private val onProgress: (Float) -> Unit,
    private val applyTextAlpha: (Float) -> Unit,
    /** Called when the springs come to rest, when the toolbar may hide or show */
    private val onSettled: () -> Unit
) {
    private val paging = Spring()
    private val away = Spring()
    private val dissolve = Spring()
    private val springs = arrayOf(paging, away, dissolve)
    private var lastFrameNanos = 0L
    private var isRunning = false

    /** Whether the toolbar is now the list's bar, or on its way */
    val isEngaged: Boolean
        get() = paging.value > 0f || paging.target > 0f

    /** The toolbar stays on screen for the bar: on the Agent tab, unless a chat has sent it away */
    val shouldKeepToolbar: Boolean
        get() = isEngaged && !(away.target == 1f && away.isSettled)

    /**
     * The search circle takes taps on its way into and at the list's bar, while no chat covers the list and no
     * question is written; the toolbar's own field then takes none
     */
    val isCircleInteractive: Boolean
        get() = paging.target == 1f && away.target == 0f && dissolve.target == 0f

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            val deltaSeconds = if (lastFrameNanos == 0L) {
                1 / 60f
            } else {
                ((frameTimeNanos - lastFrameNanos) / 1_000_000_000f).coerceIn(0f, MAX_FRAME)
            }
            lastFrameNanos = frameTimeNanos
            var isMoving = false
            for (spring in springs) {
                if (spring.step(deltaSeconds)) isMoving = true
            }
            apply()
            if (isMoving) {
                Choreographer.getInstance().postFrameCallback(this)
            } else {
                isRunning = false
                lastFrameNanos = 0L
                onSettled()
            }
        }
    }

    /**
     * [isAgent] when paging has committed to the Agent tab with its list on top, [isCovered] while a chat is over the
     * list, [isComposing] while a question is written in the list's bar
     */
    fun setTargets(
        isAgent: Boolean,
        isCovered: Boolean,
        isComposing: Boolean,
        isAnimated: Boolean
    ) {
        paging.target = if (isAgent) 1f else 0f
        away.target = if (isAgent && isCovered) 1f else 0f
        dissolve.target = if (isAgent && isComposing && !isCovered) 1f else 0f
        val shouldAnimate = isAnimated && WGlobalStorage.getAreAnimationsActive() &&
            searchView.isAttachedToWindow
        if (!shouldAnimate) {
            for (spring in springs) spring.jump()
            stop()
            apply()
            onSettled()
            return
        }
        if (!isRunning && springs.any { !it.isSettled }) {
            isRunning = true
            lastFrameNanos = 0L
            Choreographer.getInstance().postFrameCallback(frameCallback)
        }
    }

    fun stop() {
        if (!isRunning) return
        isRunning = false
        lastFrameNanos = 0L
        Choreographer.getInstance().removeFrameCallback(frameCallback)
    }

    /** Lays the pieces out for the progress shown now */
    fun apply() {
        if (searchView.layoutParams == null) return
        val progress = paging.value
        val clamped = progress.coerceIn(0f, 1f)
        val swell = (1 + SWELL * 4 * progress * (1 - progress)).coerceIn(0.9f, 1.2f)
        // The field shrinks into the circle ahead of its leading edge, so they part in the second half
        val collapse = 1 - (1 - clamped).pow(COLLAPSE_POWER)
        val circle = CIRCLE.dp
        val width = if (clamped <= 0f) {
            0
        } else {
            (fullSearchWidth() + (circle - fullSearchWidth()) * collapse).roundToInt()
                .coerceAtLeast(circle)
        }
        if (searchView.layoutParams.width != width) {
            searchView.updateLayoutParams { this.width = width }
        }
        // The placeholder keeps to one line while the field narrows
        searchView.editText.isHintSingleLine = clamped > 0f
        // The placeholder is gone before the field gets narrower than it
        val textFade = 1 - (clamped / TEXT_FADE_END).coerceIn(0f, 1f)
        applyTextAlpha(textFade * textFade)
        // The circle keeps its anchor through navigation and interrupted transitions.
        val awayValue = away.value.coerceIn(0f, 1f)
        val dissolveValue = dissolve.value.coerceIn(0f, 1f)
        val circleScale = 1 + (DISSOLVE_SCALE - 1) * dissolveValue
        searchView.translationX = 0f
        searchView.scaleX = swell * circleScale
        searchView.scaleY = swell * circleScale
        searchView.alpha = (1 - dissolveValue) * (1 - awayValue)
        // The plus shrinks away and turns over the first third, where the bar's microphone appears
        val fold = (clamped / PLUS_FOLD_END).coerceIn(0f, 1f)
        actionsIcon.scaleX = 1 - (1 - PLUS_MIN_SCALE) * fold
        actionsIcon.scaleY = actionsIcon.scaleX
        actionsIcon.alpha = 1 - fold
        actionsIcon.rotation = (45f * maxOf(clamped, searchView.focusProgress))
        actionsButton.scaleX = swell
        actionsButton.scaleY = swell
        actionsButton.alpha = 1 - smoothstep(PLUS_FOLD_END, BUTTON_GONE, clamped)
        actionsButton.isClickable = clamped < 0.5f
        // Bound for the list's bar, the toolbar's own field and button take no touches and are not read out
        val isBound = paging.target == 1f
        // Until the list's field appears where the toolbar's still is, a tap there does nothing at all
        searchView.touchMode = when {
            !isBound -> HomeSearchField.TouchMode.FIELD
            paging.value < FIELD_APPEARS -> HomeSearchField.TouchMode.SWALLOW
            else -> HomeSearchField.TouchMode.PASS_THROUGH
        }
        val accessibility = if (isBound) {
            View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        } else {
            View.IMPORTANT_FOR_ACCESSIBILITY_AUTO
        }
        searchView.importantForAccessibility = accessibility
        actionsButton.importantForAccessibility = accessibility
        if (searchView.visibility != View.GONE) {
            searchView.isInvisible = dissolve.target == 1f && dissolve.isSettled
        }
        if (actionsButton.visibility != View.GONE) {
            actionsButton.isInvisible = isBound && clamped >= 1f && paging.isSettled
        }
        circleButton.translationX = searchView.translationX
        circleButton.isInvisible = !isCircleInteractive
        onProgress(progress)
    }

    // A critically damped or bouncy spring toward its target, integrated per frame
    private class Spring {
        var value = 0f
        var velocity = 0f
        var target = 0f

        val isSettled: Boolean
            get() = abs(target - value) < SETTLE && abs(velocity) < SETTLE

        fun jump() {
            value = target
            velocity = 0f
        }

        /** Returns whether it still moves */
        fun step(deltaSeconds: Float): Boolean {
            if (isSettled) {
                jump()
                return false
            }
            val substep = deltaSeconds / SUBSTEPS
            repeat(SUBSTEPS) {
                val force = STIFFNESS * (target - value) - DAMPING * velocity
                velocity += force * substep
                value += velocity * substep
            }
            return true
        }
    }

    private companion object {
        // The glass transition spring: response 0.416 s, damping 0.75
        val OMEGA = 2 * PI.toFloat() / 0.416f
        val STIFFNESS = OMEGA * OMEGA
        val DAMPING = 2 * 0.75f * OMEGA
        const val SUBSTEPS = 4
        const val MAX_FRAME = 1 / 30f
        const val SETTLE = 0.001f

        const val CIRCLE = 48
        const val SWELL = 0.2f
        const val COLLAPSE_POWER = 3.5f
        const val TEXT_FADE_END = 0.2f
        const val PLUS_FOLD_END = 0.35f
        const val PLUS_MIN_SCALE = 0.2f
        const val BUTTON_GONE = 0.7f
        const val DISSOLVE_SCALE = 1.2f

        // Where the list's field starts to appear (the list's `BAR_APPEAR_START`)
        const val FIELD_APPEARS = 0.45f

        fun smoothstep(start: Float, end: Float, value: Float): Float {
            val fraction = ((value - start) / (end - start)).coerceIn(0f, 1f)
            return fraction * fraction * (3 - 2 * fraction)
        }
    }
}
