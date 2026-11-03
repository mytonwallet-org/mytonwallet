package org.mytonwallet.app_air.uiagent.agentV2

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Tells the SDK whether the chat is on screen in the foreground after consent; only then
 * the SDK keeps the server's copy of the wallet snapshot current.
 */
internal class AgentV2ChatActivity(
    private val scope: CoroutineScope,
    private val group: AgentV2ChatActivityGroup = AgentV2ChatActivityGroup(),
    private val setChatActive: suspend (Boolean) -> Unit
) {
    private var isVisible = false
    private var hasConsent = false
    private var isInBackground = false
    private var isActive = false
    private var isStopped = false

    fun setVisible(visible: Boolean) {
        isVisible = visible
        update()
    }

    fun setConsentAccepted(accepted: Boolean) {
        hasConsent = accepted
        update()
    }

    fun setInBackground(inBackground: Boolean) {
        isInBackground = inBackground
        update()
    }

    /** A new SDK runtime starts with the chat inactive. */
    fun onRuntimeReady() {
        update(resending = true)
    }

    fun stop() {
        if (isStopped) return
        isVisible = false
        update()
        isStopped = true
    }

    private fun update(resending: Boolean = false) {
        if (isStopped) return
        val active = isVisible && hasConsent && !isInBackground
        if (active == isActive && !(resending && active)) return
        isActive = active
        group.update(this, active, resending, scope, setChatActive)
    }
}

internal class AgentV2ChatActivityGroup {
    private val activeChats = mutableSetOf<AgentV2ChatActivity>()
    private var lastCall: Job? = null

    fun update(
        chat: AgentV2ChatActivity,
        isActive: Boolean,
        shouldResend: Boolean,
        scope: CoroutineScope,
        setChatActive: suspend (Boolean) -> Unit
    ) {
        val wasActive = activeChats.isNotEmpty()
        if (isActive) activeChats.add(chat) else activeChats.remove(chat)
        val isAnyChatActive = activeChats.isNotEmpty()
        if (wasActive == isAnyChatActive && !(shouldResend && isAnyChatActive)) return
        val previous = lastCall
        // Calls from all thread sessions stay in order, so the SDK ends with the latest state
        lastCall = scope.launch {
            previous?.join()
            try {
                setChatActive(isAnyChatActive)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // The next state change or SDK runtime start sends the state again.
            }
        }
    }
}
