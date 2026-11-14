package org.mytonwallet.app_air.uiagent.viewControllers.agent

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * What the user does that would send something to the Agent, held until they allow it. Once the Agent is allowed, an
 * action runs at once. Otherwise [askForConsent] shows the consent sheet: Allow runs the action once, and closing the
 * sheet drops it and runs its `onDeclined`, so the next action asks again. One sheet asks at a time; actions while it
 * shows are dropped.
 *
 * [knownConsent] is the consent as last learned, null until then, when [readConsent] reads it. [onAllowed] learns that
 * the Agent is allowed, read so or allowed in the sheet, before the action runs.
 */
internal class AgentConsentGate(
    private val knownConsent: () -> Boolean?,
    private val readConsent: suspend () -> Boolean,
    private val askForConsent: (onAllowed: () -> Unit, onDeclined: () -> Unit) -> Unit,
    private val onAllowed: () -> Unit
) {
    private var isAsking = false

    suspend fun request(onDeclined: () -> Unit = {}, action: () -> Unit) {
        if (knownConsent() == true) return action()
        if (isAsking) return
        isAsking = true
        if (knownConsent() == null && readConsent()) {
            isAsking = false
            onAllowed()
            return action()
        }
        askForConsent(
            {
                isAsking = false
                onAllowed()
                action()
            },
            {
                isAsking = false
                onDeclined()
            }
        )
    }
}

/**
 * The gate of a discussion, whose model, kept by `AgentSession`, may hold the refusal it read before the user
 * allowed the Agent elsewhere: the gate reads the consent again before the sheet asks, and a consent given reaches the
 * model as one given in the sheet does.
 */
internal fun createDiscussionConsentGate(
    model: () -> AgentVM?,
    askForConsent: (onAllowed: () -> Unit, onDeclined: () -> Unit) -> Unit,
    opening: () -> AgentChatOpening? = { null }
) = AgentConsentGate(
    knownConsent = { (model()?.hasConsent ?: opening()?.hasConsent)?.takeIf { it } },
    readConsent = {
        model()?.readConsent() ?: run {
            opening()?.readConsent()
            opening()?.hasConsent == true
        }
    },
    askForConsent = askForConsent,
    onAllowed = { model()?.acceptConsent() ?: opening()?.markConsentAccepted() }
)

internal fun AgentConsentGate.requestDiscussionConsent(
    scope: CoroutineScope,
    opening: () -> AgentChatOpening?,
    onDeclined: () -> Unit = {},
    action: () -> Unit
) {
    scope.launch {
        request(onDeclined) {
            val pendingOpening = opening()
            if (pendingOpening?.isDeferredDiscussion == true) {
                scope.launch {
                    if (pendingOpening.prepareDiscussionSubmission()) action()
                }
            } else {
                action()
            }
        }
    }
}

/**
 * The recording a microphone press holds until the user allows the Agent, owned by that press. A press while one is
 * held holds the same recording, as the consent asked for it is still on its way; closing the sheet and the screen
 * going drop it.
 */
internal class AgentHeldDictation {
    class Press

    private var heldPress: Press? = null

    fun hold(): Press = heldPress ?: Press().also { heldPress = it }

    // Whether [press] still held the recording, which it now gives up
    fun release(press: Press): Boolean {
        if (heldPress !== press) return false
        heldPress = null
        return true
    }

    fun drop() {
        heldPress = null
    }
}

/**
 * What the microphone of a chat waiting for the user's consent does when pressed: while [isAwaitingConsent], it asks
 * with [askForConsent] and holds the recording in [heldDictation], which Allow starts with [startDictation] while the
 * press still holds it, and closing the sheet drops. The result is the composer's `shouldHoldDictation`.
 */
internal fun holdDictationForConsent(
    isAwaitingConsent: () -> Boolean,
    heldDictation: AgentHeldDictation,
    askForConsent: (onAllowed: () -> Unit, onDeclined: () -> Unit) -> Unit,
    startDictation: () -> Unit
): () -> Boolean = {
    isAwaitingConsent() && run {
        val press = heldDictation.hold()
        askForConsent(
            { if (heldDictation.release(press)) startDictation() },
            { heldDictation.release(press) }
        )
        true
    }
}
