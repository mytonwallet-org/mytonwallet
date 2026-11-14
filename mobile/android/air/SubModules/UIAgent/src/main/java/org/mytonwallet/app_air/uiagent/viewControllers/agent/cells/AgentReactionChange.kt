package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import kotlin.math.abs
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentAnswerFeedback
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessageRole

/** The reaction an answer's bubble carries: only an answer's bubble has one */
internal val AgentMessage.shownReaction: AgentAnswerFeedback?
    get() = feedback.takeIf { role == AgentMessageRole.ASSISTANT && !newsPost && hasVisibleBubble }

/** How a message's corner emoji moves from the reaction it shows to the next one */
internal enum class AgentReactionChange {
    /** Nothing changes */
    NONE,

    /** The next reaction, or none, shows at once */
    SHOW,

    /** Without motion, the next reaction fades in, or the emoji fades out */
    FADE,

    /** The chosen reaction is on its way from the cloud; the emoji gives way to it as it lands */
    AWAIT_LANDING,

    /** The emoji gives way to the next reaction, which plays Telegram's center icon from its start */
    SWAP,

    /** The withdrawn reaction's emoji shrinks and fades away */
    WITHDRAW
}

/**
 * How the corner emoji goes from [shown] to [next]. Another message, or one off the screen, shows [next] at once;
 * Reduce Motion, [canAnimate] false, fades; [flying] is the reaction on its way to the corner from the cloud.
 */
internal fun agentReactionChange(
    shown: AgentAnswerFeedback?,
    next: AgentAnswerFeedback?,
    isSameMessage: Boolean,
    isOnScreen: Boolean,
    canAnimate: Boolean,
    flying: AgentAnswerFeedback?
): AgentReactionChange = when {
    !isSameMessage || !isOnScreen -> AgentReactionChange.SHOW
    next == shown -> AgentReactionChange.NONE
    !canAnimate -> AgentReactionChange.FADE
    next == null -> AgentReactionChange.WITHDRAW
    next == flying -> AgentReactionChange.AWAIT_LANDING
    else -> AgentReactionChange.SWAP
}

/**
 * A chosen reaction's flight from its place in the cloud to the answer's corner emoji, as Telegram's: over
 * [DURATION_MS] at a constant pace along a parabola that rises [ELEVATION] dp above its start halfway across and then
 * drops onto the corner, straight when its ends lie within [STRAIGHT_DISTANCE] dp of each other. The icon shrinks
 * from the cloud's size to the emoji's and fades from the cloud's still into the emoji's first drawing on the way.
 * The burst around the corner starts [BURST_DELAY_MS] in. On the corner, the emoji takes its place.
 */
internal object AgentReactionFlight {
    const val DURATION_MS = 200L
    const val BURST_DELAY_MS = 150L
    const val ELEVATION = 30f
    const val STRAIGHT_DISTANCE = 5f

    /**
     * Where the icon is [progress] of the way, from 0 to 1, from [startX], [startY] to [endX], [endY], in px with
     * [density] px per dp: on the parabola through the start, the point [ELEVATION] above the start halfway across,
     * and the end
     */
    fun point(
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
        progress: Float,
        density: Float
    ): Pair<Float, Float> {
        val x = startX + (endX - startX) * progress
        val straight = STRAIGHT_DISTANCE * density
        if (abs(endX - startX) < straight && abs(endY - startY) < straight) {
            return x to startY + (endY - startY) * progress
        }
        // The quadratic through the start at 0, the top at a half and the end at 1
        val top = startY - ELEVATION * density
        val t = progress
        val fromStart = startY * 2 * (t - 0.5f) * (t - 1)
        val fromTop = -top * 4 * t * (t - 1)
        val fromEnd = endY * 2 * t * (t - 0.5f)
        return x to fromStart + fromTop + fromEnd
    }

    /** The icon's size [progress] of the way, from the cloud's [from] to the corner emoji's [to] */
    fun size(from: Float, to: Float, progress: Float): Float = from + (to - from) * progress

    /** Whether the burst around the corner is due [elapsedMs] into the flight */
    fun isBurstDue(elapsedMs: Long): Boolean = elapsedMs >= BURST_DELAY_MS
}

/** The withdrawn or replaced corner emoji shrinks to [SCALE] and fades over [DURATION_MS], as Telegram's swap */
internal object AgentReactionEmojiSwap {
    const val DURATION_MS = 120L
    const val SCALE = 0.2f

    /** The leaving emoji's scale and alpha [progress] of the way out */
    fun leaving(progress: Float): Pair<Float, Float> {
        val p = progress.coerceIn(0f, 1f)
        return 1f + (SCALE - 1f) * p to 1f - p
    }
}

/**
 * The toast after the user's first like and dislike on this install, once each for agent and operator replies,
 * whichever account or chat it is in: [isShown] and [markShown] keep which have shown
 */
internal class AgentReactionToasts(
    private val isShown: (AgentAnswerFeedback, isOperator: Boolean) -> Boolean,
    private val markShown: (AgentAnswerFeedback, isOperator: Boolean) -> Unit
) {
    // The toast each answer's latest choice waits for, by the answer's id
    private val awaited = mutableMapOf<String, Awaited>()

    /**
     * The toast that [chosen], a reaction the user chose in the cloud for the answer [messageId], waits for, which
     * [show] shows with its string key: none once that kind's toast has shown, and none for a withdrawal. A later
     * choice on the answer drops it.
     */
    fun await(
        messageId: String,
        chosen: AgentAnswerFeedback?,
        isOperator: Boolean = false,
        show: (AgentAnswerFeedback, key: String) -> Unit
    ): Awaited? {
        awaited.remove(messageId)
        if (chosen == null || isShown(chosen, isOperator)) return null
        return Awaited(messageId, chosen, isOperator, show).also { awaited[messageId] = it }
    }

    /**
     * A first reaction's toast: it shows, marked as shown, once the reaction has both landed on the answer and been
     * saved, whichever comes later, and goes with a save that fails
     */
    inner class Awaited(
        private val messageId: String,
        private val feedback: AgentAnswerFeedback,
        private val isOperator: Boolean,
        private val show: (AgentAnswerFeedback, key: String) -> Unit
    ) {
        private var isLanded = false
        private var isSaved = false

        fun land() {
            isLanded = true
            showIfDue()
        }

        fun confirmSave() {
            isSaved = true
            showIfDue()
        }

        fun cancel() {
            if (awaited[messageId] === this) awaited.remove(messageId)
        }

        private fun showIfDue() {
            if (!isLanded || !isSaved || awaited[messageId] !== this) return
            awaited.remove(messageId)
            if (isShown(feedback, isOperator)) return
            markShown(feedback, isOperator)
            show(
                feedback,
                if (isOperator) {
                    when (feedback) {
                        AgentAnswerFeedback.LIKE -> "\$agent_feedback_support_liked_toast"
                        AgentAnswerFeedback.DISLIKE -> "\$agent_feedback_support_disliked_toast"
                    }
                } else {
                    when (feedback) {
                        AgentAnswerFeedback.LIKE -> "\$agent_feedback_liked_toast"
                        AgentAnswerFeedback.DISLIKE -> "\$agent_feedback_disliked_toast"
                    }
                }
            )
        }
    }
}

/** How long a chat bulletin stays up: a copy's confirmation for a moment, a reaction's toast as long as iOS's */
internal object AgentBulletinDurations {
    const val COPY_MS = 1500L
    const val REACTION_MS = 3000L
}

/**
 * A reaction's animations: Telegram's as the cloud opens, while it is pressed and as the answer's corner emoji, and our
 * own burst around the corner as a chosen one lands, in the frame and timing of Telegram's
 */
internal enum class AgentReactionAnimation { APPEAR, SELECT, CENTER, BURST }

/**
 * What a cloud's place plays as the growing capsule reaches it: the appear animation, with motion. Otherwise it shows
 * the still, select's first frame, at once.
 */
internal fun agentReactionSlotAppearance(canAnimate: Boolean): AgentReactionAnimation? =
    AgentReactionAnimation.APPEAR.takeIf { canAnimate }

/** What a pressed icon in the cloud plays: select, with motion */
internal fun agentReactionPressAnimation(canAnimate: Boolean): AgentReactionAnimation? =
    AgentReactionAnimation.SELECT.takeIf { canAnimate }
