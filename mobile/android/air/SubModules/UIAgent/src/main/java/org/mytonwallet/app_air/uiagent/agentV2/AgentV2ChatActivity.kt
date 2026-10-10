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
    private val setChatActive: suspend (Boolean) -> Unit
) {
    private var isVisible = false
    private var hasConsent = false
    private var isInBackground = false
    private var isActive = false
    private var isStopped = false
    private var lastCall: Job? = null

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
        val previous = lastCall
        // Calls stay in order, so the SDK ends with the latest state.
        lastCall = scope.launch {
            previous?.join()
            try {
                setChatActive(active)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                // The next state change or SDK runtime start sends the state again.
            }
        }
    }
}
