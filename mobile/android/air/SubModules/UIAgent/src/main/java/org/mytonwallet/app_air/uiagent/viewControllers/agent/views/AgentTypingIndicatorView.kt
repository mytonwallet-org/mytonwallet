package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.animation.Animator
import android.annotation.SuppressLint
import android.content.Context
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * How long the row of an answer stopped before it showed stays, the top taking the Stop, before the chat removes it
 */
internal const val AGENT_STOPPED_ANSWER_DURATION_MS = 1600L

/**
 * Whether the row of an answer stopped before it showed stays and fades out, or goes at once: it stays with animations
 * on, except in debug builds while system animations are off, to keep E2E runs fast
 */
internal val isAgentStoppedAnswerAnimated: Boolean
    get() = WGlobalStorage.getAreAnimationsActive() &&
        AgentDebugAnimations.areSystemAnimationsOn(ApplicationContextHolder.applicationContext)

/**
 * The row that stands in for the Agent's answer until it arrives: the spinning top and the step the Agent is on, in
 * the Agent gradient, laid out as an incoming bubble without its fill. Each step shows for at least 1.2 s before the
 * next one replaces it, and a glint of light crosses each step once as it comes into focus.
 */
@SuppressLint("ViewConstructor")
class AgentTypingIndicatorView(context: Context) : FrameLayout(context) {
    // The row shows while the Agent thinks
    private val spinningTop = AgentSpinningTopView(context).apply {
        isTouchInteractive = true
        agentState = AgentSpinningTopView.AgentState.THINKING
    }
    private val status = AgentStatusTextView(
        context,
        labelTextSize = TEXT_SIZE,
        labelFont = WFont.Medium,
        labelLineHeight = LINE_HEIGHT,
        labelMaxLines = MAX_LINES,
        hasGlint = true
    )
    private var statusReveal: Animator? = null
    private var shownAtMs = 0L
    private var isStopped = false
    private var pendingText: String? = null

    /** The spinning top and the step, which an answer taking the row's place turns out of */
    internal val spinningTopView: View
        get() = spinningTop
    internal val statusView: View
        get() = status

    private val applyPendingText = Runnable {
        pendingText?.let { show(it, isAnimated = true) }
    }

    // A stopped answer's row fades out by the time the chat removes it
    private val fadeOutStopped = Runnable {
        animate().alpha(0f).setDuration(STOPPED_FADE_OUT_MS).start()
    }

    init {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
        minimumHeight = MIN_HEIGHT.dp
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        addView(
            spinningTop,
            LayoutParams(TOP_SIZE.dp, TOP_SIZE.dp).apply {
                gravity = Gravity.START or Gravity.TOP
                marginStart = TOP_START.dp
                topMargin = TOP_TOP.dp
            }
        )
        addView(
            status,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.TOP
                marginStart = TEXT_START.dp
                marginEnd = TEXT_END.dp
                topMargin = TEXT_VERTICAL_PADDING.dp
                bottomMargin = TEXT_VERTICAL_PADDING.dp
            }
        )
    }

    /** Shows the step; a step that comes sooner than 1.2 s after the last waits for its turn */
    fun setStatus(text: String, isAnimated: Boolean) {
        if (text == status.text?.toString()) {
            pendingText = null
            removeCallbacks(applyPendingText)
            return
        }
        val waitMs = shownAtMs + MIN_STATUS_DURATION_MS - SystemClock.elapsedRealtime()
        if (!isAnimated || status.text.isNullOrEmpty() || waitMs <= 0) {
            show(text, isAnimated)
            return
        }
        pendingText = text
        removeCallbacks(applyPendingText)
        postDelayed(applyPendingText, waitMs)
    }

    /**
     * The first status of a row focuses in from a blur, a glint crossing it as it does; a stopped row's status stays
     * gone
     */
    fun revealStatus() {
        if (isStopped || !WGlobalStorage.getAreAnimationsActive()) return
        finishStatusReveal()
        statusReveal = AgentBlurTransition.animateIn(status, REVEAL_DURATION_MS) {
            statusReveal = null
        }
        status.startGlint()
    }

    /** Ends the first status's blur-in where it would end, as the status starts moving on */
    fun finishStatusReveal() {
        statusReveal?.end()
    }

    /**
     * An answer stopped before it showed: the top takes the Stop and stops spinning, as the web's indicator does, and
     * the step fades out
     */
    fun setStopped(isStopped: Boolean) {
        if (this.isStopped == isStopped) return
        this.isStopped = isStopped
        spinningTop.agentState = if (isStopped) {
            AgentSpinningTopView.AgentState.STOPPED
        } else {
            AgentSpinningTopView.AgentState.THINKING
        }
        val alpha = if (isStopped) 0f else 1f
        status.animate().cancel()
        removeCallbacks(fadeOutStopped)
        animate().cancel()
        this.alpha = 1f
        if (isStopped && isAttachedToWindow && isAgentStoppedAnswerAnimated) {
            status.animate().alpha(alpha).setDuration(STOPPED_STATUS_FADE_MS).start()
            postDelayed(fadeOutStopped, AGENT_STOPPED_ANSWER_DURATION_MS - STOPPED_FADE_OUT_MS)
        } else {
            status.alpha = alpha
        }
    }

    fun setRenderingActive(isActive: Boolean) {
        spinningTop.isAnimationPaused = !isActive
        status.isAnimationPaused = !isActive
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        removeCallbacks(applyPendingText)
        pendingText?.let { show(it, isAnimated = false) }
    }

    private fun show(text: String, isAnimated: Boolean) {
        pendingText = null
        removeCallbacks(applyPendingText)
        status.setText(text, isAnimated && isAttachedToWindow)
        shownAtMs = SystemClock.elapsedRealtime()
        contentDescription = text
    }

    private companion object {
        const val MIN_HEIGHT = 42
        const val TOP_SIZE = 24
        const val TOP_START = 12
        const val TOP_TOP = 9
        const val TEXT_START = 40
        const val TEXT_END = 14
        const val TEXT_VERTICAL_PADDING = 10
        const val TEXT_SIZE = 17f
        const val LINE_HEIGHT = 22f
        const val MAX_LINES = 3
        const val MIN_STATUS_DURATION_MS = 1200L
        const val REVEAL_DURATION_MS = 400L
        const val STOPPED_STATUS_FADE_MS = 150L
        const val STOPPED_FADE_OUT_MS = 250L
    }
}
