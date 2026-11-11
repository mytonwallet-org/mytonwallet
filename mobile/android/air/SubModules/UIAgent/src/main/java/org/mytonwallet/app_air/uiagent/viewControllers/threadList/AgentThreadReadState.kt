package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

/**
 * Which chats hold an answer the user hasn't seen, for the list's unread dot.
 *
 * An answer that completes while its chat is off screen marks the chat, and so does a chat whose message count grows
 * past the count of settled messages the chat showed as the user left it, or that the list saw after that. Showing the
 * chat clears both. Operator replies stay unread until their latest loaded history has shown on screen. A chat
 * without operator replies that the device has never shown counts as read.
 */
internal class AgentThreadReadState(
    private val read: () -> String? = WGlobalStorage::getAgentThreadReadState,
    private val write: (String) -> Unit = WGlobalStorage::setAgentThreadReadState
) {
    private data class Record(
        // Settled messages shown on leaving, or the count the list saw once answering stopped
        val seenMessageCount: Int?,
        // Left without a count, and the list hasn't yet seen it settled
        val isBaselinePending: Boolean,
        val isMarkedUnread: Boolean,
        val seenOperatorMessageAt: Long? = null
    )

    // Insertion order is the order the records last changed, oldest first
    private val records = LinkedHashMap<String, Record>()
    private val visibleCounts = mutableMapOf<String, Int>()
    private val listeners = mutableListOf<() -> Unit>()

    init {
        decode(read().orEmpty())
    }

    fun addListener(listener: () -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: () -> Unit) {
        listeners.remove(listener)
    }

    fun isUnread(thread: AgentV2ThreadSummary): Boolean {
        val record = records[thread.id]
        val lastOperatorMessageAt = thread.support?.lastOperatorMessageAt
            ?.let(::parseAgentV2Timestamp)?.time
        val seenOperatorMessageAt = record?.seenOperatorMessageAt
        if (lastOperatorMessageAt != null &&
            (seenOperatorMessageAt == null || lastOperatorMessageAt > seenOperatorMessageAt)
        ) {
            return true
        }
        if (visibleCounts.containsKey(thread.id)) return false
        if (record == null) return false
        if (record.isMarkedUnread) return true
        val seen = record.seenMessageCount
        return !record.isBaselinePending && seen != null && thread.messageCount > seen
    }

    fun getSeenMessageCountIfUnread(thread: AgentV2ThreadSummary): Int? {
        if (!isUnread(thread)) return null
        val seen = records[thread.id]?.seenMessageCount ?: return null
        return seen.takeIf { it < thread.messageCount }
    }

    /** Showing a chat clears its unread agent answers */
    fun onChatAppeared(threadId: String) {
        visibleCounts[threadId] = (visibleCounts[threadId] ?: 0) + 1
        markSeen(threadId)
    }

    fun onChatDisappeared(threadId: String, seenMessageCount: Int? = null) {
        val count = visibleCounts[threadId]
        if (count != null) {
            if (count > 1) visibleCounts[threadId] = count - 1 else visibleCounts.remove(threadId)
        }
        markSeen(threadId, seenMessageCount)
    }

    /** Acknowledge only the support timestamp from the latest loaded history shown in the chat */
    fun markSupportSeen(threadId: String, loadedOperatorMessageAt: String?) {
        val timestamp = loadedOperatorMessageAt?.let(::parseAgentV2Timestamp)?.time ?: return
        val record = records[threadId]
            ?: Record(null, isBaselinePending = true, isMarkedUnread = false)
        if (record.seenOperatorMessageAt?.let { it >= timestamp } == true) return
        store(threadId, record.copy(seenOperatorMessageAt = timestamp))
        save(shouldNotify = true)
    }

    /** An answer completed in the chat; off screen, the chat gets the dot */
    fun onAnswerCompleted(threadId: String) {
        if (visibleCounts.containsKey(threadId) || records[threadId]?.isMarkedUnread == true) return
        val record = records[threadId]
        store(
            threadId,
            record?.copy(isMarkedUnread = true)
                ?: Record(null, isBaselinePending = false, isMarkedUnread = true)
        )
        save(shouldNotify = true)
    }

    /**
     * Takes the list's counts as seen for chats the user has left and that no longer answer, and for chats the list
     * shows for the first time, so only what arrives later marks them
     */
    fun observe(threads: List<AgentV2ThreadSummary>, answeringThreadIds: Set<String>) {
        var hasChanged = false
        for (thread in threads) {
            if (thread.id in answeringThreadIds || visibleCounts.containsKey(thread.id)) continue
            val record = records[thread.id]
                ?: Record(null, isBaselinePending = true, isMarkedUnread = false)
            if (!record.isBaselinePending) continue
            store(
                thread.id,
                record.copy(seenMessageCount = thread.messageCount, isBaselinePending = false)
            )
            hasChanged = true
        }
        if (hasChanged) save(shouldNotify = false)
    }

    fun remove(threadId: String) {
        if (records.remove(threadId) == null) return
        save(shouldNotify = true)
    }

    private fun markSeen(threadId: String, seenMessageCount: Int? = null) {
        val record = Record(
            seenMessageCount ?: records[threadId]?.seenMessageCount,
            isBaselinePending = seenMessageCount == null,
            isMarkedUnread = false,
            seenOperatorMessageAt = records[threadId]?.seenOperatorMessageAt
        )
        if (records[threadId] == record) return
        store(threadId, record)
        save(shouldNotify = true)
    }

    private fun store(threadId: String, record: Record) {
        records.remove(threadId)
        records[threadId] = record
        val iterator = records.keys.iterator()
        while (records.size > RECORD_LIMIT && iterator.hasNext()) {
            iterator.next()
            iterator.remove()
        }
    }

    private fun save(shouldNotify: Boolean) {
        write(encode())
        if (shouldNotify) listeners.toList().forEach { it() }
    }

    private fun encode(): String = records.entries.joinToString(LINE_SEPARATOR) { (id, record) ->
        listOf(
            id,
            record.seenMessageCount?.toString().orEmpty(),
            if (record.isBaselinePending) "1" else "0",
            if (record.isMarkedUnread) "1" else "0",
            record.seenOperatorMessageAt?.toString().orEmpty()
        ).joinToString(FIELD_SEPARATOR)
    }

    private fun decode(value: String) {
        for (line in value.split(LINE_SEPARATOR)) {
            val fields = line.split(FIELD_SEPARATOR)
            if (fields.size !in 4..5 || fields[0].isEmpty()) continue
            store(
                fields[0],
                Record(
                    fields[1].toIntOrNull(),
                    isBaselinePending = fields[2] == "1",
                    isMarkedUnread = fields[3] == "1",
                    seenOperatorMessageAt = fields.getOrNull(4)?.toLongOrNull()
                )
            )
        }
    }

    companion object {
        val shared by lazy { AgentThreadReadState() }

        // Records beyond this many, the oldest first, are dropped
        private const val RECORD_LIMIT = 500
        private const val LINE_SEPARATOR = "\n"
        private const val FIELD_SEPARATOR = "\t"
    }
}
