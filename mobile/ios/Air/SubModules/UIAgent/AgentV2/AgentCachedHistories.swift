import Foundation
import WalletCore

/// A thread's latest messages that a chat shows until its history loads
struct AgentCachedHistory: Equatable {
    let thread: ApiAgentV2ThreadSummary
    let messages: [ApiAgentV2PersistedMessage]
}

/// The SDK's cached histories of the threads at the top of the list, read ahead of their chats so a chat opens with its
/// messages in its first frame. A history that loads in a chat takes the place of its thread's copy.
@MainActor
final class AgentCachedHistories {
    /// As many threads as the SDK keeps the histories of
    private static let threadLimit = 10

    private struct Summary: Equatable {
        let revision: Int
        let updatedAt: String
        let messageCount: Int

        init(_ thread: ApiAgentV2ThreadSummary) {
            revision = thread.revision
            updatedAt = thread.updatedAt
            messageCount = thread.messageCount
        }
    }

    private let client: AgentV2Client
    private var histories: [String: AgentCachedHistory] = [:]
    /// Threads with a history, the most recently stored last
    private var order: [String] = []
    /// The summary each thread's copy was read for, which a list with the same summary doesn't read again
    private var readSummaries: [String: Summary] = [:]
    /// The threads of the latest prefetch, in the list's order, which keep their histories over other threads
    private var prefetchedThreadIds: [String] = []
    private var pendingThreads: [ApiAgentV2ThreadSummary]?
    private var readTask: Task<Void, Never>?
    private var readingThreadId: String?
    private var hasReadingThreadChanged = false
    private var generation = 0

    init(client: AgentV2Client) {
        self.client = client
    }

    func getHistory(threadId: String) -> AgentCachedHistory? {
        histories[threadId]
    }

    /// Reads, one at a time, the copies of the list's top threads with messages, except for news and digest discussions
    /// and the threads read for the same summary before
    func prefetch(_ threads: [ApiAgentV2ThreadSummary]) {
        let threads = Array(threads.filter { $0.messageCount > 0 && $0.news == nil && $0.digest == nil }.prefix(Self.threadLimit))
        pendingThreads = threads
        prefetchedThreadIds = threads.map(\.id)
        guard readTask == nil else { return }
        readTask = Task { [weak self] in
            await self?.readPendingThreads()
        }
    }

    func store(_ history: AgentCachedHistory) {
        let threadId = history.thread.id
        if threadId == readingThreadId { hasReadingThreadChanged = true }
        readSummaries[threadId] = Summary(history.thread)
        histories[threadId] = history
        order.removeAll { $0 == threadId }
        order.append(threadId)
        while order.count > Self.threadLimit {
            evictHistory(keeping: threadId)
        }
    }

    func remove(threadId: String) {
        if threadId == readingThreadId { hasReadingThreadChanged = true }
        readSummaries.removeValue(forKey: threadId)
        histories.removeValue(forKey: threadId)
        order.removeAll { $0 == threadId }
    }

    func removeAll() {
        generation += 1
        pendingThreads = nil
        prefetchedThreadIds.removeAll()
        readSummaries.removeAll()
        histories.removeAll()
        order.removeAll()
    }

    private func readPendingThreads() async {
        while let threads = pendingThreads {
            pendingThreads = nil
            let readGeneration = generation
            for thread in threads where readSummaries[thread.id] != Summary(thread) {
                readingThreadId = thread.id
                hasReadingThreadChanged = false
                let cached = await client.cachedMessages(threadId: thread.id)
                readingThreadId = nil
                guard readGeneration == generation else { break }
                // The chat stored or removed the thread's history while it was read
                guard !hasReadingThreadChanged else { continue }
                if let cached, cached.thread.id == thread.id, !cached.messages.isEmpty {
                    store(AgentCachedHistory(thread: cached.thread, messages: cached.messages))
                } else {
                    remove(threadId: thread.id)
                }
                readSummaries[thread.id] = Summary(thread)
            }
        }
        readTask = nil
    }

    /// Drops the oldest history outside the latest prefetch, else the lowest in the list, and forgets its read, so the
    /// next prefetch reads it again
    private func evictHistory(keeping threadId: String) {
        let candidates = order.filter { $0 != threadId }
        let outsideList = candidates.first { !prefetchedThreadIds.contains($0) }
        let lowestInList = candidates.max {
            (prefetchedThreadIds.firstIndex(of: $0) ?? 0) < (prefetchedThreadIds.firstIndex(of: $1) ?? 0)
        }
        guard let evicted = outsideList ?? lowestInList else { return }
        order.removeAll { $0 == evicted }
        histories.removeValue(forKey: evicted)
        readSummaries.removeValue(forKey: evicted)
    }
}
