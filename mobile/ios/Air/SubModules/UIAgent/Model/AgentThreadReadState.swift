import Foundation
import WalletCore

/// Which chats hold an answer the user hasn't seen, for the list's unread dot.
///
/// An answer that completes while its chat is off screen marks the chat, and so does a chat whose message count grows
/// past the completed-message count the chat showed when the user left it. Showing the chat clears both.
/// Operator replies stay unread until their history is shown. Message counts alone leave chats this device has never
/// shown read.
@MainActor
final class AgentThreadReadState {
    static let shared = AgentThreadReadState(userDefaults: .standard)
    static let didChangeNotification = Notification.Name("AgentThreadReadStateDidChange")

    private struct Record: Codable, Equatable {
        /// The chat's message count excluding an answer that is still streaming
        var seenMessageCount: Int?
        var seenOperatorMessageAt: String?
        /// The next settled list count establishes the read baseline
        var isBaselineNeeded = false
        var isMarkedUnread = false

        private enum CodingKeys: String, CodingKey {
            case seenMessageCount, seenOperatorMessageAt, isBaselineNeeded = "needsBaseline", isMarkedUnread
        }
    }

    private static let storageKey = "agent-thread-read-state"
    /// Records beyond this many, the oldest first, are dropped: those chats count as read again
    private static let recordLimit = 500

    private let userDefaults: UserDefaults
    private var records: [String: Record]
    /// Thread IDs in the order their records last changed, oldest first
    private var order: [String]
    private var visibleCounts: [String: Int] = [:]

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        let stored = userDefaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        records = stored?.records ?? [:]
        order = stored?.order.filter { stored?.records[$0] != nil } ?? []
    }

    func isUnread(_ thread: ApiAgentV2ThreadSummary) -> Bool {
        let seenOperatorMessageAt = (records[thread.id]?.seenOperatorMessageAt).map(AgentV2DateParser.date) ?? .distantPast
        if let operatorMessageAt = thread.support?.lastOperatorMessageAt,
           AgentV2DateParser.date(operatorMessageAt) > seenOperatorMessageAt {
            return true
        }
        guard visibleCounts[thread.id] == nil, let record = records[thread.id] else { return false }
        if record.isMarkedUnread { return true }
        guard !record.isBaselineNeeded, let seen = record.seenMessageCount else { return false }
        return thread.messageCount > seen
    }

    /// How many of the chat's messages the user has seen, for a chat with messages after them. The chat opens at the
    /// first of those, under the "New" divider.
    func getSeenMessageCount(ifUnread thread: ApiAgentV2ThreadSummary) -> Int? {
        guard isUnread(thread), let seen = records[thread.id]?.seenMessageCount, seen < thread.messageCount else { return nil }
        return seen
    }

    /// Call as a chat comes on screen; operator replies are acknowledged from loaded history separately
    func chatDidAppear(threadId: String) {
        visibleCounts[threadId, default: 0] += 1
        markSeen(threadId: threadId)
    }

    func chatDidDisappear(threadId: String, seenMessageCount: Int? = nil) {
        if let count = visibleCounts[threadId] {
            visibleCounts[threadId] = count > 1 ? count - 1 : nil
        }
        markSeen(threadId: threadId, seenMessageCount: seenMessageCount)
    }

    /// An answer completed in the chat; off screen, the chat gets the dot
    func answerDidComplete(threadId: String) {
        guard visibleCounts[threadId] == nil, records[threadId]?.isMarkedUnread != true else { return }
        update(threadId) { $0.isMarkedUnread = true }
    }

    func markOperatorMessagesSeen(threadId: String, loadedOperatorMessageAt: String) {
        let seenOperatorMessageAt = (records[threadId]?.seenOperatorMessageAt).map(AgentV2DateParser.date) ?? .distantPast
        guard AgentV2DateParser.date(loadedOperatorMessageAt) > seenOperatorMessageAt else { return }
        update(threadId) { $0.seenOperatorMessageAt = loadedOperatorMessageAt }
    }

    /// Establishes pending read baselines once a chat is off screen and no longer answering
    func observe(_ threads: [ApiAgentV2ThreadSummary], answeringThreadIds: Set<String>) {
        var hasChanged = false
        for thread in threads where !answeringThreadIds.contains(thread.id) && visibleCounts[thread.id] == nil {
            var record = records[thread.id] ?? Record(isBaselineNeeded: true)
            guard record.isBaselineNeeded else { continue }
            record.isBaselineNeeded = false
            record.seenMessageCount = thread.messageCount
            store(record, for: thread.id)
            hasChanged = true
        }
        if hasChanged { save(shouldNotify: false) }
    }

    func remove(threadId: String) {
        guard records.removeValue(forKey: threadId) != nil else { return }
        order.removeAll { $0 == threadId }
        save(shouldNotify: true)
    }

    private func markSeen(threadId: String, seenMessageCount: Int? = nil) {
        let seen = seenMessageCount ?? records[threadId]?.seenMessageCount
        let record = Record(
            seenMessageCount: seen,
            seenOperatorMessageAt: records[threadId]?.seenOperatorMessageAt,
            isBaselineNeeded: seenMessageCount == nil,
            isMarkedUnread: false
        )
        store(record, for: threadId)
        save(shouldNotify: true)
    }

    private func update(_ threadId: String, _ change: (inout Record) -> Void) {
        var record = records[threadId] ?? Record()
        change(&record)
        store(record, for: threadId)
        save(shouldNotify: true)
    }

    private func store(_ record: Record, for threadId: String) {
        records[threadId] = record
        order.removeAll { $0 == threadId }
        order.append(threadId)
        if order.count > Self.recordLimit {
            for dropped in order.prefix(order.count - Self.recordLimit) {
                records.removeValue(forKey: dropped)
            }
            order.removeFirst(order.count - Self.recordLimit)
        }
    }

    private func save(shouldNotify: Bool) {
        if let data = try? JSONEncoder().encode(Stored(records: records, order: order)) {
            userDefaults.set(data, forKey: Self.storageKey)
        }
        if shouldNotify {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    private struct Stored: Codable {
        let records: [String: Record]
        let order: [String]
    }
}
