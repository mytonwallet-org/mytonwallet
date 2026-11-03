import Foundation
import WalletContext
import WalletCore

@MainActor
protocol AgentNewsFeedClient: AnyObject {
    func getNewsFeed(lang: String, cursor: String?) async throws -> ApiAgentV2NewsFeedPage
}

@MainActor
final class LiveAgentNewsFeedClient: AgentNewsFeedClient {
    func getNewsFeed(lang: String, cursor: String?) async throws -> ApiAgentV2NewsFeedPage {
        try await Api.getAgentV2NewsFeed(lang: lang, cursor: cursor)
    }
}

@MainActor
final class AgentNewsReadState {
    private static let readThroughKey = "agent-mypulse-read-through"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    var readThrough: String? {
        userDefaults.string(forKey: Self.readThroughKey)
    }

    func initializeIfNeeded(items: [ApiAgentV2NewsFeedItem]) {
        guard readThrough == nil else { return }
        markRead(items: items)
    }

    func markRead(items: [ApiAgentV2NewsFeedItem]) {
        guard let newest = AgentNewsFeedModel.merged(items).last else { return }
        if let readThrough,
           AgentV2DateParser.date(readThrough) >= AgentV2DateParser.date(newest.deliveredAt) {
            return
        }
        userDefaults.set(newest.deliveredAt, forKey: Self.readThroughKey)
    }

    func unreadCount(items: [ApiAgentV2NewsFeedItem]) -> Int {
        guard let readThrough else { return 0 }
        let date = AgentV2DateParser.date(readThrough)
        return AgentNewsFeedModel.merged(items).filter { AgentV2DateParser.date($0.deliveredAt) > date }.count
    }
}

@MainActor
final class AgentNewsFeedModel {
    private(set) var items: [ApiAgentV2NewsFeedItem] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: Error?
    private(set) var unreadEventId: Int?
    private(set) var locale: String?
    let findThread: (String) -> ApiAgentV2ThreadSummary?

    var onChange: (() -> Void)?

    private let client: AgentNewsFeedClient
    private let readState: AgentNewsReadState
    private let language: () -> String
    private var generation = 0
    private var hasOpened = false
    private var feedLanguage: String?
    private var unreadCutoff: Date?
    private var requestedCursors: Set<String> = []
    private var localDiscussions: [Int: ApiAgentV2NewsFeedItem.Discussion] = [:]

    /// `cachedPage` is a first page loaded elsewhere, which the feed shows at once while it refreshes
    init(
        client: AgentNewsFeedClient? = nil,
        readState: AgentNewsReadState,
        language: @escaping () -> String = { LocalizationSupport.shared.langCode },
        findThread: @escaping (String) -> ApiAgentV2ThreadSummary? = { _ in nil },
        cachedPage: (page: ApiAgentV2NewsFeedPage, language: String)? = nil
    ) {
        self.client = client ?? LiveAgentNewsFeedClient()
        self.readState = readState
        self.language = language
        self.findThread = findThread
        if let cachedPage, !cachedPage.page.items.isEmpty {
            applyFirstPage(cachedPage.page, requestLanguage: cachedPage.language)
        }
    }

    func refresh() async {
        generation += 1
        let requestGeneration = generation
        isLoading = true
        isLoadingMore = false
        error = nil
        onChange?()
        defer {
            if requestGeneration == generation {
                isLoading = false
                onChange?()
            }
        }
        do {
            let requestLanguage = language()
            let page = try await client.getNewsFeed(lang: requestLanguage, cursor: nil)
            guard requestGeneration == generation, !Task.isCancelled else { return }
            applyFirstPage(page, requestLanguage: requestLanguage)
        } catch {
            // With news shown, the feed keeps them and shows the failure under them
            guard requestGeneration == generation, !(error is CancellationError), !Task.isCancelled else { return }
            self.error = error
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, nextCursor != nil else { return }
        let requestGeneration = generation
        isLoadingMore = true
        onChange?()
        defer {
            if requestGeneration == generation {
                isLoadingMore = false
                onChange?()
            }
        }
        let originalCount = items.count
        do {
            repeat {
                guard let cursor = nextCursor, !requestedCursors.contains(cursor) else {
                    nextCursor = nil
                    break
                }
                let page = try await client.getNewsFeed(lang: feedLanguage ?? language(), cursor: cursor)
                guard requestGeneration == generation, !Task.isCancelled else { return }
                guard page.locale == locale else { break }
                requestedCursors.insert(cursor)
                mergePageItems(page.items)
                updateUnreadBoundary()
                readState.markRead(items: items)
                nextCursor = page.nextCursor.flatMap { requestedCursors.contains($0) ? nil : $0 }
            } while items.count == originalCount && nextCursor != nil
        } catch {
            // Keep the cursor so the next scroll can retry the older page.
        }
    }

    func markDiscussion(eventId: Int, thread: ApiAgentV2ThreadSummary) {
        localDiscussions[eventId] = .init(threadId: thread.id, icon: thread.icon)
        items = applyingLocalDiscussions(to: items)
        onChange?()
    }

    func removeDiscussion(threadId: String) {
        localDiscussions = localDiscussions.filter { $0.value.threadId != threadId }
        items = items.map { item in
            guard item.discussion?.threadId == threadId else { return item }
            return ApiAgentV2NewsFeedItem(
                eventId: item.eventId,
                deliveredAt: item.deliveredAt,
                headline: item.headline,
                body: item.body,
                imageUrl: item.imageUrl,
                sources: item.sources
            )
        }
        onChange?()
    }

    private func applyFirstPage(_ page: ApiAgentV2NewsFeedPage, requestLanguage: String) {
        if locale != nil, locale != page.locale {
            items = []
            localDiscussions = [:]
            hasOpened = false
        }
        locale = page.locale
        feedLanguage = requestLanguage
        mergePageItems(page.items)
        if !hasOpened {
            readState.initializeIfNeeded(items: page.items)
            unreadCutoff = readState.readThrough.map(AgentV2DateParser.date)
            hasOpened = true
        }
        updateUnreadBoundary()
        readState.markRead(items: items)
        nextCursor = page.nextCursor
        requestedCursors = []
    }

    private func mergePageItems(_ pageItems: [ApiAgentV2NewsFeedItem]) {
        for item in pageItems {
            guard let discussion = localDiscussions[item.eventId], item.discussion?.threadId == discussion.threadId,
                  let icon = item.discussion?.icon?.nilIfEmpty else { continue }
            localDiscussions[item.eventId] = .init(threadId: discussion.threadId, icon: icon)
        }
        items = applyingLocalDiscussions(to: Self.merged(items + pageItems))
    }

    private func applyingLocalDiscussions(to items: [ApiAgentV2NewsFeedItem]) -> [ApiAgentV2NewsFeedItem] {
        items.map { item in
            guard let discussion = localDiscussions[item.eventId] else { return item }
            return ApiAgentV2NewsFeedItem(
                eventId: item.eventId,
                deliveredAt: item.deliveredAt,
                headline: item.headline,
                body: item.body,
                imageUrl: item.imageUrl,
                sources: item.sources,
                discussion: discussion
            )
        }
    }

    private func updateUnreadBoundary() {
        unreadEventId = unreadCutoff.flatMap { cutoff in
            items.first { AgentV2DateParser.date($0.deliveredAt) > cutoff }?.eventId
        }
    }

    static func merged(_ items: [ApiAgentV2NewsFeedItem]) -> [ApiAgentV2NewsFeedItem] {
        var byId: [Int: ApiAgentV2NewsFeedItem] = [:]
        for item in items {
            if let previous = byId[item.eventId],
               AgentV2DateParser.date(previous.deliveredAt) > AgentV2DateParser.date(item.deliveredAt) {
                continue
            }
            byId[item.eventId] = item
        }
        return byId.values.sorted {
            let lhs = AgentV2DateParser.date($0.deliveredAt)
            let rhs = AgentV2DateParser.date($1.deliveredAt)
            return lhs == rhs ? $0.eventId < $1.eventId : lhs < rhs
        }
    }
}
