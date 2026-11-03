package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.os.SystemClock
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * The row that stands in for the Agent's answer until it arrives: the spinning top and the step the Agent is on, in
 * the Agent gradient, laid out as an incoming bubble without its fill. Each step shows for at least 1.2 s before the
 * next one replaces it.
 */
@SuppressLint("ViewConstructor")
class AgentTypingIndicatorView(context: Context) : FrameLayout(context) {
    private val spinningTop = AgentSpinningTopView(context).apply { isTouchInteractive = true }
    private val status = AgentStatusTextView(
        context,
        labelTextSize = TEXT_SIZE,
        labelFont = WFont.Medium,
        labelLineHeight = LINE_HEIGHT,
        labelMaxLines = MAX_LINES
    )
    private var shownAtMs = 0L
    private var pendingText: String? = null
    private val applyPendingText = Runnable {
        pendingText?.let { show(it, isAnimated = true) }
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

    /** The first status of a row focuses in from a blur */
    fun revealStatus() {
        if (!WGlobalStorage.getAreAnimationsActive()) return
        AgentBlurTransition.animateIn(status, REVEAL_DURATION_MS)
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
    }
}
