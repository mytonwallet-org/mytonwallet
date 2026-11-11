import Foundation
import WalletContext
import WalletCore

@MainActor
protocol AgentNewsFeedClient: AnyObject {
    func getNewsFeed(lang: String, cursor: String?, digestHour: Int, timeZone: String) async throws -> ApiAgentV2NewsFeedPage
}

@MainActor
final class LiveAgentNewsFeedClient: AgentNewsFeedClient {
    func getNewsFeed(lang: String, cursor: String?, digestHour: Int, timeZone: String) async throws -> ApiAgentV2NewsFeedPage {
        try await Api.getAgentV2NewsFeed(lang: lang, cursor: cursor, digestHour: digestHour, timeZone: timeZone)
    }
}

/// The digest hour and time zone a page of the feed was requested with, which the page's digests follow
struct AgentNewsDigestSchedule: Equatable {
    let hour: Int
    let timeZone: String
}

/// A first page of the feed loaded elsewhere, with what it was requested with
struct AgentNewsCachedPage {
    let page: ApiAgentV2NewsFeedPage
    let language: String
    let schedule: AgentNewsDigestSchedule
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
    enum Entry: Equatable {
        case news(ApiAgentV2NewsFeedItem)
        case digest(ApiAgentV2NewsFeedDigest)

        var deliveredAt: String {
            switch self {
            case .news(let item): item.deliveredAt
            case .digest(let digest): digest.deliveredAt
            }
        }
    }

    var entries: [Entry] {
        (items.map(Entry.news) + digests.map(Entry.digest)).sorted {
            AgentV2DateParser.date($0.deliveredAt) < AgentV2DateParser.date($1.deliveredAt)
        }
    }

    private(set) var digests: [ApiAgentV2NewsFeedDigest] = []
    let requestedDigestId: String?

    /// Older pages may still bring the digest the feed was opened for: it hasn't come, older pages remain, and the
    /// loaded entries reach back no further than its window's end, which its ID carries after the locale
    var canLoadRequestedDigest: Bool {
        guard let requestedDigestId, nextCursor != nil,
              !digests.contains(where: { $0.id == requestedDigestId }) else { return false }
        let windowEnd = AgentV2DateParser.date(String(requestedDigestId.drop { $0 != ":" }.dropFirst()))
        // An ID without a readable time can't be placed among the pages, so the digest counts as not found
        guard windowEnd != .distantPast else { return false }
        guard let oldest = entries.first else { return true }
        return AgentV2DateParser.date(oldest.deliveredAt) >= windowEnd
    }

    private(set) var items: [ApiAgentV2NewsFeedItem] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var error: Error?
    /// A first page has come: until then a feed without news is still loading them
    private(set) var hasLoaded = false
    private(set) var unreadEventId: Int?
    private(set) var locale: String?
    let findThread: (String) -> ApiAgentV2ThreadSummary?

    var onChange: (() -> Void)?

    private let client: AgentNewsFeedClient
    private let readState: AgentNewsReadState
    private let language: () -> String
    /// The device's digest hour, whose changes reload the digests
    let digestSettings: AgentNewsNotificationSettings
    private let timeZone: () -> String
    /// The schedule the loaded digests were requested with
    private var digestSchedule: AgentNewsDigestSchedule?
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
        cachedPage: AgentNewsCachedPage? = nil,
        requestedDigestId: String? = nil,
        digestSettings: AgentNewsNotificationSettings = .shared,
        timeZone: @escaping () -> String = { TimeZone.current.identifier }
    ) {
        self.client = client ?? LiveAgentNewsFeedClient()
        self.readState = readState
        self.language = language
        self.findThread = findThread
        self.requestedDigestId = requestedDigestId
        self.digestSettings = digestSettings
        self.timeZone = timeZone
        if let cachedPage, !cachedPage.page.items.isEmpty || cachedPage.page.digests?.isEmpty == false {
            // A page of another digest schedule shows its news alone, without its digests and the pages after it
            let schedule = currentDigestSchedule
            let page = cachedPage.schedule == schedule
                ? cachedPage.page
                : ApiAgentV2NewsFeedPage(locale: cachedPage.page.locale, items: cachedPage.page.items)
            digestSchedule = schedule
            applyFirstPage(page, requestLanguage: cachedPage.language)
        }
    }

    var currentDigestSchedule: AgentNewsDigestSchedule {
        AgentNewsDigestSchedule(hour: digestSettings.digestHour, timeZone: timeZone())
    }

    func refresh() async {
        generation += 1
        let requestGeneration = generation
        isLoading = true
        isLoadingMore = false
        error = nil
        let schedule = currentDigestSchedule
        resetDigestsIfNeeded(for: schedule)
        onChange?()
        defer {
            if requestGeneration == generation {
                isLoading = false
                onChange?()
            }
        }
        do {
            let requestLanguage = language()
            let page = try await client.getNewsFeed(
                lang: requestLanguage, cursor: nil, digestHour: schedule.hour, timeZone: schedule.timeZone
            )
            guard requestGeneration == generation, !Task.isCancelled else { return }
            applyFirstPage(page, requestLanguage: requestLanguage)
        } catch {
            // With news shown, the feed keeps them and shows the failure under them
            guard requestGeneration == generation, !(error is CancellationError), !Task.isCancelled else { return }
            self.error = error
        }
    }

    func loadMore() async {
        // Pages of another digest schedule wait for the refresh that its change starts
        guard !isLoading, !isLoadingMore, nextCursor != nil, let schedule = digestSchedule,
              schedule == currentDigestSchedule else { return }
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
                let page = try await client.getNewsFeed(
                    lang: feedLanguage ?? language(), cursor: cursor, digestHour: schedule.hour, timeZone: schedule.timeZone
                )
                guard requestGeneration == generation, !Task.isCancelled else { return }
                guard page.locale == locale else { break }
                requestedCursors.insert(cursor)
                mergePage(page)
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

    /// Digests of another hour or time zone go, with the pages they came on, and the news stay until the refresh brings
    /// the new schedule's
    private func resetDigestsIfNeeded(for schedule: AgentNewsDigestSchedule) {
        defer { digestSchedule = schedule }
        guard let digestSchedule, digestSchedule != schedule else { return }
        digests = []
        nextCursor = nil
        requestedCursors = []
    }

    private func applyFirstPage(_ page: ApiAgentV2NewsFeedPage, requestLanguage: String) {
        if locale != nil, locale != page.locale {
            items = []
            digests = []
            localDiscussions = [:]
            hasOpened = false
        }
        locale = page.locale
        feedLanguage = requestLanguage
        hasLoaded = true
        mergePage(page)
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

    private func mergePage(_ page: ApiAgentV2NewsFeedPage) {
        var digestsById = Dictionary(uniqueKeysWithValues: digests.map { ($0.id, $0) })
        for digest in page.digests ?? [] { digestsById[digest.id] = digest }
        digests = digestsById.values.sorted { $0.id < $1.id }
        let pageItems = page.items
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
