package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.graphics.Outline
import android.graphics.PointF
import android.view.View
import android.view.ViewOutlineProvider
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

private const val MORPH_DURATION_MS = 400L

// The spinning top ends this small, this far toward the leading edge and up
private const val TOP_END_SCALE = 0.2f
private const val TOP_TRAVEL_X = -14f
private const val TOP_TRAVEL_Y = -10f
private const val TOP_DURATION_MS = 300f
private const val STATUS_DISSOLVE_MS = 300f

// The answer's text comes into focus a moment after the status starts dissolving
private const val CONTENT_DELAY_MS = 60f
private const val BUBBLE_FADE_MS = 200f

// The row's frame reaches this far beyond its spinning top and its status
private const val ROW_CONTENT_INSET = 12f

// The mask ends this far outside the bubble, its corners concentric with the bubble's, so the
// bubble's own shape shows by then
private const val MASK_OUTSET = 8f

/**
 * The typing row turns into the answer that takes its place rather than swapping for it, as on iOS:
 * the spinning top shrinks as it moves away, the status dissolves into the answer's first
 * characters as it moves onto them, and the answer's bubble grows out of the row's frame into its
 * own, following the bubble as the answer streams in, on Telegram's 0.4 s curve. [row] and [bubble]
 * lie in [cell]; [content] shows the answer's text in the bubble, whose first characters stand
 * [textInset] from the bubble's leading top corner.
 */
internal class AgentTypingAnswerMorph(
    private val cell: View,
    private val row: AgentTypingIndicatorView,
    private val bubble: View,
    private val content: View,
    private val textInset: PointF,
    private val onEnd: () -> Unit
) : AgentMorphClock(cell, MORPH_DURATION_MS) {
    private val direction = if (LocaleController.isRTL) -1f else 1f
    private val bubbleOutline = bubble.outlineProvider
    private var rowFrame: AgentRevealFrame? = null
    private var statusShift: PointF? = null
    private var mask: AgentTypingMorphMask? = null

    init {
        row.finishStatusReveal()
        bubble.alpha = 0f
        content.alpha = 0f
        bubble.outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                val mask = mask
                if (mask == null) {
                    outline.setRect(0, 0, view.width, view.height)
                    return
                }
                outline.setRoundRect(
                    mask.frame.left.roundToInt(),
                    mask.frame.top.roundToInt(),
                    mask.frame.right.roundToInt(),
                    mask.frame.bottom.roundToInt(),
                    mask.radius
                )
            }
        }
        bubble.clipToOutline = true
        start()
    }

    override fun step(elapsedMs: Long) {
        val time = elapsedMs.toFloat()
        val top = row.spinningTopView
        val status = row.statusView
        val away = AGENT_TELEGRAM_CURVE.getInterpolation((time / TOP_DURATION_MS).coerceIn(0f, 1f))
        top.translationX = TOP_TRAVEL_X.dp * direction * away
        top.translationY = TOP_TRAVEL_Y.dp * away
        top.scaleX = interpolate(1f, TOP_END_SCALE, away)
        top.scaleY = top.scaleX
        top.alpha = 1f - away
        val dissolve = AGENT_EASE_IN.getInterpolation((time / STATUS_DISSOLVE_MS).coerceIn(0f, 1f))
        status.alpha = 1f - dissolve
        AgentBlurTransition.setBlur(status, AgentBlurTransition.RADIUS_DP.dp * dissolve)
        bubble.alpha = AGENT_EASE_OUT.getInterpolation((time / BUBBLE_FADE_MS).coerceIn(0f, 1f))
        val focus = AGENT_EASE_OUT.getInterpolation(
            ((time - CONTENT_DELAY_MS) / STATUS_DISSOLVE_MS).coerceIn(0f, 1f)
        )
        content.alpha = focus
        AgentBlurTransition.setBlur(content, AgentBlurTransition.RADIUS_DP.dp * (1f - focus))

        if (rowFrame == null) prepare()
        val rowFrame = rowFrame ?: return
        val progress = AGENT_TELEGRAM_CURVE.getInterpolation(time / MORPH_DURATION_MS)
        statusShift?.let {
            status.translationX = it.x * progress
            status.translationY = it.y * progress
        }
        // The growth keeps up with an answer that streams in meanwhile
        mask = calculateAgentTypingMorphMask(
            rowFrame,
            AgentRevealFrame(0f, 0f, bubble.width.toFloat(), bubble.height.toFloat()),
            progress,
            AGENT_BUBBLE_RADIUS.dp,
            MASK_OUTSET.dp
        )
        bubble.invalidateOutline()
    }

    // Where the row stood in the bubble, and how far the status goes to stand on the answer's first
    // characters, once the cell has laid the answer out
    private fun prepare() {
        if (!cell.isLaidOut || cell.isLayoutRequested || bubble.width <= 0) return
        val top = row.spinningTopView
        val status = row.statusView
        val rowOffset = getAgentLaidOutOffset(row, cell) ?: return
        val bubbleOffset = getAgentLaidOutOffset(bubble, cell) ?: return
        val left = min(top.left, status.left) - ROW_CONTENT_INSET.dp
        val right = maxOf(top.right, status.right) + ROW_CONTENT_INSET.dp
        val dx = rowOffset.x - bubbleOffset.x
        val dy = rowOffset.y - bubbleOffset.y
        rowFrame = AgentRevealFrame(left + dx, dy, right + dx, row.height + dy)
        val textStartX = if (LocaleController.isRTL) {
            bubbleOffset.x + bubble.width - textInset.x
        } else {
            bubbleOffset.x + textInset.x
        }
        val statusStartX = rowOffset.x + if (LocaleController.isRTL) status.right else status.left
        statusShift = PointF(
            textStartX - statusStartX,
            bubbleOffset.y + textInset.y - rowOffset.y - status.top
        )
    }

    override fun onFinish() {
        for (view in arrayOf(row.spinningTopView, row.statusView)) {
            view.translationX = 0f
            view.translationY = 0f
            view.scaleX = 1f
            view.scaleY = 1f
            view.alpha = 1f
            AgentBlurTransition.setBlur(view, 0f)
        }
        bubble.alpha = 1f
        bubble.clipToOutline = false
        bubble.outlineProvider = bubbleOutline
        content.alpha = 1f
        AgentBlurTransition.setBlur(content, 0f)
        onEnd()
    }
}

/** The part of the bubble that shows, a rounded rectangle in the bubble */
internal class AgentTypingMorphMask(val frame: AgentRevealFrame, val radius: Float)

/**
 * The bubble shows within the row's frame, [rowFrame], at first, which grows at [progress] along
 * its curve to [outset] beyond the bubble's [bounds], its corners from the bubble's [radius] to
 * ones concentric with them
 */
internal fun calculateAgentTypingMorphMask(
    rowFrame: AgentRevealFrame,
    bounds: AgentRevealFrame,
    progress: Float,
    radius: Float,
    outset: Float
): AgentTypingMorphMask {
    val end = AgentRevealFrame(
        bounds.left - outset,
        bounds.top - outset,
        bounds.right + outset,
        bounds.bottom + outset
    )
    val frame = agentRevealMorphFrame(rowFrame, end, progress)
    return AgentTypingMorphMask(
        frame,
        minOf(radius + outset * progress, frame.width / 2, frame.height / 2).coerceAtLeast(0f)
    )
}
