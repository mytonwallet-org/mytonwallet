package org.mytonwallet.app_air.uiagent.viewControllers.agent

internal class AgentStreamRenderer(
    private val postFrame: (Runnable) -> Unit,
    private val cancelFrame: (Runnable) -> Unit,
    private val renderMessages: (List<String>) -> Unit
) {
    private val pendingMessageIds = linkedSetOf<String>()
    private var isFrameScheduled = false
    var isActive = false
        private set
    val hasPendingUpdates: Boolean
        get() = pendingMessageIds.isNotEmpty()

    private val frame = Runnable {
        isFrameScheduled = false
        if (!isActive) return@Runnable
        val messageIds = pendingMessageIds.toList()
        pendingMessageIds.clear()
        renderMessages(messageIds)
    }

    fun enqueue(messageId: String) {
        pendingMessageIds.add(messageId)
        scheduleFrame()
    }

    fun setActive(active: Boolean) {
        isActive = active
        if (active) {
            scheduleFrame()
        } else {
            cancelPendingFrame()
        }
    }

    fun clear() {
        cancelPendingFrame()
        pendingMessageIds.clear()
    }

    private fun scheduleFrame() {
        if (!isActive || isFrameScheduled || pendingMessageIds.isEmpty()) return
        isFrameScheduled = true
        postFrame(frame)
    }

    private fun cancelPendingFrame() {
        if (!isFrameScheduled) return
        isFrameScheduled = false
        cancelFrame(frame)
    }
}
