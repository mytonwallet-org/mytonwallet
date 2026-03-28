import Foundation

/// In-memory per-conversation chat history.
actor ChatHistory {
    /// Max message pairs per conversation.
    private let maxPairs: Int
    private var store: [String: [ChatMessage]] = [:]

    init(maxPairs: Int = 3) {
        self.maxPairs = maxPairs
    }

    /// Get history for a conversation.
    func get(_ conversationId: String) -> [ChatMessage] {
        store[conversationId] ?? []
    }

    /// Append a message and trim to the last `maxPairs` pairs.
    func add(_ conversationId: String, role: ChatMessage.Role, content: String) {
        var messages = store[conversationId] ?? []
        messages.append(ChatMessage(role: role, content: content))
        store[conversationId] = trimmed(messages)
    }

    func replace(_ conversationId: String, with messages: [ChatMessage]) {
        let trimmedMessages = trimmed(messages)
        if trimmedMessages.isEmpty {
            store.removeValue(forKey: conversationId)
        } else {
            store[conversationId] = trimmedMessages
        }
    }

    /// Clear history for a conversation.
    func clear(_ conversationId: String) {
        store.removeValue(forKey: conversationId)
    }

    /// Clear all history.
    func clearAll() {
        store.removeAll()
    }

    private func trimmed(_ messages: [ChatMessage]) -> [ChatMessage] {
        let limit = maxPairs * 2
        guard messages.count > limit else { return messages }
        return Array(messages.suffix(limit))
    }
}
