package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.Animator
import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * The Agent's status in its gradient. A new status replaces the old one with the blur transition: the old text goes
 * up and out, the new one comes in from below, as Telegram's typing status does.
 */
@SuppressLint("ViewConstructor")
class AgentStatusTextView(
    context: Context,
    private val labelTextSize: Float,
    private val labelFont: WFont,
    private val labelLineHeight: Float,
    private val labelMaxLines: Int = 1
) : FrameLayout(context) {
    private var current = makeLabel(null)
    private val transitions = mutableListOf<Animator>()

    val text: CharSequence? get() = current.text

    /** Holds the gradient's sweep still */
    var isAnimationPaused = false
        set(value) {
            if (field == value) return
            field = value
            for (index in 0 until childCount) {
                (getChildAt(index) as? AgentGradientLabel)?.isAnimationPaused = value
            }
        }

    init {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
        addView(current, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    fun setText(text: String, isAnimated: Boolean) {
        if (current.text?.toString() == text) return
        contentDescription = text
        transitions.removeAll { !it.isStarted }
        if (!isAnimated || current.text.isNullOrEmpty() ||
            !WGlobalStorage.getAreAnimationsActive()
        ) {
            finishTransitions()
            current.text = text
            return
        }
        val outgoing = current
        val incoming = makeLabel(text)
        addView(incoming, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        current = incoming
        transitions += AgentBlurTransition.animateOut(
            outgoing,
            OUT_DURATION_MS,
            toOffsetDp = -DRIFT_DP
        ) { removeView(outgoing) }
        transitions += AgentBlurTransition.animateIn(
            incoming,
            IN_DURATION_MS,
            delayMs = IN_DELAY_MS,
            fromOffsetDp = DRIFT_DP
        )
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        finishTransitions()
    }

    // Ends the transitions at their last frame: outgoing labels leave, the current one shows sharp
    private fun finishTransitions() {
        val running = transitions.toList()
        transitions.clear()
        running.forEach { it.end() }
        for (index in childCount - 1 downTo 0) {
            val child = getChildAt(index)
            if (child !== current) removeView(child)
        }
    }

    private fun makeLabel(text: String?) = AgentGradientLabel(context).apply {
        isAnimationPaused = this@AgentStatusTextView.isAnimationPaused
        setStyle(labelTextSize, labelFont)
        setLineHeight(labelLineHeight)
        maxLines = labelMaxLines
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.START or Gravity.CENTER_VERTICAL
        textAlignment = TEXT_ALIGNMENT_VIEW_START
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        this.text = text
    }

    private companion object {
        const val OUT_DURATION_MS = 250L
        const val IN_DURATION_MS = 350L
        const val IN_DELAY_MS = 50L
        const val DRIFT_DP = 5f
    }
}
