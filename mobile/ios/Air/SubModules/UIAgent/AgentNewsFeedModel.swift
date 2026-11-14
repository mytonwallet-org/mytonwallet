import Foundation
import WalletContext
import WalletCore

@MainActor
protocol AgentNewsFeedClient: AnyObject {
    func getNewsFeed(lang: String, cursor: String?, schedule: AgentNewsDigestSchedule, view: ApiAgentV2NewsFeedView) async throws -> ApiAgentV2NewsFeedPage
}

@MainActor
final class LiveAgentNewsFeedClient: AgentNewsFeedClient {
    func getNewsFeed(lang: String, cursor: String?, schedule: AgentNewsDigestSchedule, view: ApiAgentV2NewsFeedView = .all) async throws -> ApiAgentV2NewsFeedPage {
        try await Api.getAgentV2NewsFeed(
            lang: lang, cursor: cursor, digestHour: schedule.hour, digestMinute: schedule.minute, timeZone: schedule.timeZone, view: view
        )
    }
}

/// The digest time and time zone a page of the feed was requested with, which the page's digests follow
struct AgentNewsDigestSchedule: Equatable {
    let hour: Int
    let minute: Int
    let timeZone: String

    /// The device's digest time in the current time zone
    @MainActor
    static var current: AgentNewsDigestSchedule {
        let settings = AgentNewsNotificationSettings.shared
        return AgentNewsDigestSchedule(hour: settings.digestHour, minute: settings.digestMinute, timeZone: TimeZone.current.identifier)
    }
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
    private static let digestsReadThroughKey = "agent-mypulse-digests-read-through"
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

    /// The delivery time of the latest digest the feed has shown, in either view
    var digestsReadThrough: String? {
        userDefaults.string(forKey: Self.digestsReadThroughKey)
    }

    func initializeDigestsIfNeeded(_ digests: [ApiAgentV2NewsFeedDigest]) {
        guard digestsReadThrough == nil else { return }
        markDigestsRead(digests)
    }

    func markDigestsRead(_ digests: [ApiAgentV2NewsFeedDigest]) {
        let newest = digests.max { AgentV2DateParser.date($0.deliveredAt) < AgentV2DateParser.date($1.deliveredAt) }
        guard let newest else { return }
        if let digestsReadThrough,
           AgentV2DateParser.date(digestsReadThrough) >= AgentV2DateParser.date(newest.deliveredAt) {
            return
        }
        userDefaults.set(newest.deliveredAt, forKey: Self.digestsReadThroughKey)
    }

    func unreadDigestCount(_ digests: [ApiAgentV2NewsFeedDigest]) -> Int {
        guard let digestsReadThrough else { return 0 }
        let date = AgentV2DateParser.date(digestsReadThrough)
        return digests.filter { AgentV2DateParser.date($0.deliveredAt) > date }.count
    }
}

@MainActor
final class AgentNewsFeedModel {
    private static let PREFETCH_INTERVAL: TimeInterval = 48 * 60 * 60

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
        if view == .digests { return digestView.digests.map(Entry.digest) }
        return (items.map(Entry.news) + allDigests.map(Entry.digest)).sorted {
            AgentV2DateParser.date($0.deliveredAt) < AgentV2DateParser.date($1.deliveredAt)
        }
    }

    private struct DigestViewState {
        var digests: [ApiAgentV2NewsFeedDigest] = []
        var nextCursor: String?
        var isLoading = false
        var isLoadingMore = false
        var error: Error?
        var hasLoaded = false
        var locale: String?
        var language: String?
        var schedule: AgentNewsDigestSchedule?
        var requestedCursors: Set<String> = []
    }

    private var digestView = DigestViewState()
    private var digestGeneration = 0
    private var hasOpenedDigests = false
    private var digestUnreadCutoff: Date?
    private var digestUnreadId: String?
    private(set) var view: ApiAgentV2NewsFeedView
    var digests: [ApiAgentV2NewsFeedDigest] { view == .digests ? digestView.digests : allDigests }
    var nextCursor: String? { view == .digests ? digestView.nextCursor : allNextCursor }
    var isLoading: Bool { view == .digests ? digestView.isLoading : isAllLoading }
    var isLoadingMore: Bool { view == .digests ? digestView.isLoadingMore : isAllLoadingMore }
    var error: Error? { view == .digests ? digestView.error : allError }
    var hasLoaded: Bool { view == .digests ? digestView.hasLoaded : hasAllLoaded }
    var locale: String? { view == .digests ? digestView.locale : allLocale }
    var unreadEventId: Int? { view == .all ? allUnreadEventId : nil }
    var unreadDigestId: String? { view == .digests ? digestUnreadId : nil }

    private var allDigests: [ApiAgentV2NewsFeedDigest] = []
    private(set) var reachedDigestId: String?
    let requestedDigestId: String?
    private(set) var isSeekingRequestedDigest: Bool

    /// Older pages may still bring the digest the feed was opened for: it hasn't come, older pages remain, and the
    /// loaded entries reach back no further than its window's end, which its ID carries after the locale
    var canLoadRequestedDigest: Bool {
        guard isSeekingRequestedDigest, let requestedDigestId, nextCursor != nil,
              !digests.contains(where: { $0.id == requestedDigestId }) else { return false }
        let windowEnd = AgentV2DateParser.date(String(requestedDigestId.drop { $0 != ":" }.dropFirst()))
        // An ID without a readable time can't be placed among the pages, so the digest counts as not found
        guard windowEnd != .distantPast else { return false }
        guard let oldest = entries.first(where: { entry in
            if view == .digests { return true }
            switch entry {
            case .news(let item): return prefetchEventIds.contains(item.eventId)
            case .digest(let digest): return prefetchDigestIds.contains(digest.id)
            }
        }) else { return true }
        return AgentV2DateParser.date(oldest.deliveredAt) >= windowEnd
    }

    private(set) var items: [ApiAgentV2NewsFeedItem] = []
    private var allNextCursor: String?
    private var isAllLoading = false
    private var isAllLoadingMore = false
    private var allError: Error?
    /// A first page has come: until then a feed without news is still loading them
    private var hasAllLoaded = false
    private var allUnreadEventId: Int?
    private var allLocale: String?
    let findThread: (String) -> ApiAgentV2ThreadSummary?

    var onChange: (() -> Void)?

    private let client: AgentNewsFeedClient
    private let readState: AgentNewsReadState
    private let language: () -> String
    /// The device's digest time, whose changes reload the digests
    let digestSettings: AgentNewsNotificationSettings
    private let timeZone: () -> String
    /// The schedule the loaded digests were requested with
    private var digestSchedule: AgentNewsDigestSchedule?
    /// The digests shown are another schedule's: they stay until the new schedule's first page replaces them, so the
    /// cards and the pinned bar don't blink out and back while it loads
    private var isDigestResetPending = false
    private var generation = 0
    private var hasOpened = false
    private var feedLanguage: String?
    private var unreadCutoff: Date?
    private var requestedCursors: Set<String> = []
    private var hasReachedHistoryEnd = false
    private var prefetchEventIds: Set<Int> = []
    private var prefetchDigestIds: Set<String> = []
    private var localDiscussions: [Int: ApiAgentV2NewsFeedItem.Discussion] = [:]
    private var localDigestDiscussions: [String: ApiAgentV2NewsFeedItem.Discussion] = [:]
    private(set) var prefetchTask: Task<Void, Never>?
    private var olderPageTask: Task<Bool, Never>?
    private var olderPageGeneration: Int?

    /// `cachedPage` and `cachedDigestsPage` are first pages of the All and Digests views loaded elsewhere, which the
    /// feed shows at once while it refreshes
    init(
        client: AgentNewsFeedClient? = nil,
        readState: AgentNewsReadState,
        language: @escaping () -> String = { LocalizationSupport.shared.langCode },
        findThread: @escaping (String) -> ApiAgentV2ThreadSummary? = { _ in nil },
        cachedPage: AgentNewsCachedPage? = nil,
        cachedDigestsPage: AgentNewsCachedPage? = nil,
        requestedDigestId: String? = nil,
        digestSettings: AgentNewsNotificationSettings = .shared,
        timeZone: @escaping () -> String = { TimeZone.current.identifier }
    ) {
        self.client = client ?? LiveAgentNewsFeedClient()
        self.readState = readState
        self.language = language
        self.findThread = findThread
        self.requestedDigestId = requestedDigestId
        isSeekingRequestedDigest = requestedDigestId != nil
        self.digestSettings = digestSettings
        view = digestSettings.newsFeedView
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
        // Digests of another schedule aren't the ones the feed would show, so it loads them behind the skeleton
        if let cached = cachedDigestsPage, cached.page.digests?.isEmpty == false, cached.schedule == currentDigestSchedule {
            applyFirstDigestsPage(cached.page, schedule: cached.schedule, requestLanguage: cached.language)
            if view == .digests { markDigestsShown() }
        }
    }

    var currentDigestSchedule: AgentNewsDigestSchedule {
        AgentNewsDigestSchedule(hour: digestSettings.digestHour, minute: digestSettings.digestMinute, timeZone: timeZone())
    }

    func setView(_ view: ApiAgentV2NewsFeedView) {
        digestSettings.setNewsFeedView(view)
        guard self.view != view else { return }
        cancelPrefetch()
        generation += 1
        digestGeneration += 1
        isAllLoading = false
        digestView.isLoading = false
        digestView.isLoadingMore = false
        self.view = view
        if view == .all, hasAllLoaded {
            if !hasOpened {
                readState.initializeIfNeeded(items: items)
                unreadCutoff = readState.readThrough.map(AgentV2DateParser.date)
                hasOpened = true
            }
            updateUnreadBoundary()
            markAllViewRead()
        }
        if view == .digests, digestView.hasLoaded {
            markDigestsShown()
        }
        onChange?()
    }

    func refresh() async {
        prefetchTask?.cancel()
        prefetchTask = nil
        generation += 1
        if view == .digests {
            await refreshDigests()
            return
        }
        let requestGeneration = generation
        isAllLoading = true
        allError = nil
        let schedule = currentDigestSchedule
        resetDigestsIfNeeded(for: schedule)
        onChange?()
        defer {
            if requestGeneration == generation {
                isAllLoading = false
                onChange?()
            }
        }
        do {
            let requestLanguage = language()
            let page = try await client.getNewsFeed(
                lang: requestLanguage, cursor: nil, schedule: schedule, view: .all
            )
            guard requestGeneration == generation, !Task.isCancelled else { return }
            dropDigestsOfAnotherSchedule()
            applyFirstPage(page, requestLanguage: requestLanguage)
            startPrefetch()
        } catch {
            // With news shown, the feed keeps them and shows the failure under them
            guard requestGeneration == generation, !(error is CancellationError), !Task.isCancelled else { return }
            dropDigestsOfAnotherSchedule()
            self.allError = error
        }
    }

    func loadMore() async {
        if view == .digests {
            await loadOlderDigests()
            startPrefetch()
            return
        }
        let originalCount = items.count
        repeat {
            guard await loadOlderPage() else { return }
        } while items.count == originalCount && allNextCursor != nil
        startPrefetch()
    }

    func cancelPrefetch() {
        prefetchTask?.cancel()
    }

    private func refreshDigests() async {
        digestGeneration += 1
        let requestGeneration = digestGeneration
        let schedule = currentDigestSchedule
        let requestLanguage = language()
        digestView.isLoading = true
        digestView.isLoadingMore = false
        digestView.error = nil
        onChange?()
        defer {
            if requestGeneration == digestGeneration {
                digestView.isLoading = false
                onChange?()
            }
        }
        do {
            let page = try await client.getNewsFeed(
                lang: requestLanguage, cursor: nil, schedule: schedule, view: .digests
            )
            guard requestGeneration == digestGeneration, !Task.isCancelled else { return }
            applyFirstDigestsPage(page, schedule: schedule, requestLanguage: requestLanguage)
            markDigestsShown()
            startPrefetch()
        } catch {
            guard requestGeneration == digestGeneration, !(error is CancellationError), !Task.isCancelled else { return }
            digestView.error = error
        }
    }

    private func loadOlderDigests() async {
        guard !digestView.isLoading, !digestView.isLoadingMore,
              let cursor = digestView.nextCursor, !digestView.requestedCursors.contains(cursor),
              let schedule = digestView.schedule, schedule == currentDigestSchedule, !Task.isCancelled else { return }
        let requestGeneration = digestGeneration
        digestView.isLoadingMore = true
        onChange?()
        defer {
            if requestGeneration == digestGeneration {
                digestView.isLoadingMore = false
                onChange?()
            }
        }
        do {
            let page = try await client.getNewsFeed(
                lang: digestView.language ?? language(), cursor: cursor, schedule: schedule, view: .digests
            )
            guard requestGeneration == digestGeneration, !Task.isCancelled, page.locale == digestView.locale else { return }
            mergeDigestsPage(page)
            updateDigestUnreadBoundary()
            digestView.requestedCursors.insert(cursor)
            digestView.nextCursor = page.nextCursor.flatMap { digestView.requestedCursors.contains($0) ? nil : $0 }
        } catch {
            // Keep the cursor so the next scroll can retry the older page
        }
    }

    private func applyFirstDigestsPage(
        _ page: ApiAgentV2NewsFeedPage, schedule: AgentNewsDigestSchedule, requestLanguage: String
    ) {
        if digestView.schedule != schedule || digestView.locale != page.locale {
            digestView.digests = []
        }
        mergeDigestsPage(page)
        digestView.schedule = schedule
        digestView.language = requestLanguage
        digestView.locale = page.locale
        digestView.hasLoaded = true
        digestView.nextCursor = page.nextCursor
        digestView.requestedCursors = []
    }

    private func mergeDigestsPage(_ page: ApiAgentV2NewsFeedPage) {
        updateLocalDigestDiscussions(from: page.digests ?? [])
        var digestsById = Dictionary(uniqueKeysWithValues: digestView.digests.map { ($0.id, $0) })
        for digest in page.digests ?? [] { digestsById[digest.id] = digest }
        digestView.digests = applyingLocalDiscussions(to: digestsById.values.sorted {
            AgentV2DateParser.date($0.deliveredAt) < AgentV2DateParser.date($1.deliveredAt)
        })
    }

    func finishRequestedDigestSearch() {
        isSeekingRequestedDigest = false
    }

    private func loadOlderPage() async -> Bool {
        if view == .digests {
            let cursor = digestView.nextCursor
            await loadOlderDigests()
            return digestView.nextCursor != cursor
        }
        if let olderPageTask {
            return await withTaskCancellationHandler {
                await olderPageTask.value
            } onCancel: {
                olderPageTask.cancel()
            }
        }
        // Pages of another digest schedule wait for the refresh that its change starts
        guard !isAllLoading, allNextCursor != nil, let schedule = digestSchedule,
              schedule == currentDigestSchedule, !Task.isCancelled else { return false }
        let requestGeneration = generation
        let task = Task { await fetchOlderPage(schedule: schedule, requestGeneration: requestGeneration) }
        olderPageTask = task
        olderPageGeneration = requestGeneration
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func fetchOlderPage(schedule: AgentNewsDigestSchedule, requestGeneration: Int) async -> Bool {
        isAllLoadingMore = true
        onChange?()
        defer {
            olderPageTask = nil
            olderPageGeneration = nil
            isAllLoadingMore = false
            onChange?()
        }
        guard requestGeneration == generation, !Task.isCancelled else { return false }
        do {
            guard let cursor = allNextCursor, !requestedCursors.contains(cursor) else {
                allNextCursor = nil
                return false
            }
            let page = try await client.getNewsFeed(
                lang: feedLanguage ?? language(), cursor: cursor, schedule: schedule, view: .all
            )
            guard requestGeneration == generation, !Task.isCancelled else { return false }
            guard page.locale == allLocale else { return false }
            requestedCursors.insert(cursor)
            if page.nextCursor == nil { hasReachedHistoryEnd = true }
            mergePage(page)
            updateUnreadBoundary()
            if view == .all { markAllViewRead() }
            allNextCursor = page.nextCursor.flatMap { requestedCursors.contains($0) ? nil : $0 }
        } catch {
            // Keep the cursor so the next scroll can retry the older page
            guard requestGeneration == generation, !(error is CancellationError), !Task.isCancelled else { return false }
            finishRequestedDigestSearch()
            return false
        }
        return true
    }

    func markDigestReached(_ id: String) {
        guard view == .all else { return }
        guard let digest = allDigests.first(where: { $0.id == id }) else { return }
        if let reachedDigestId, let reached = allDigests.first(where: { $0.id == reachedDigestId }),
           AgentV2DateParser.date(reached.deliveredAt) <= AgentV2DateParser.date(digest.deliveredAt) {
            return
        }
        reachedDigestId = id
        startPrefetch()
    }

    private var shouldPrefetch: Bool {
        guard view == .all, allNextCursor != nil else { return false }
        let reached = allDigests.first { $0.id == reachedDigestId }
        let reference = reached.map { AgentV2DateParser.date($0.deliveredAt) }
        let olderDigests = allDigests.filter { digest in
            prefetchDigestIds.contains(digest.id)
                && (reference.map { AgentV2DateParser.date(digest.deliveredAt) < $0 } ?? true)
        }
        guard olderDigests.count < 2 else { return false }
        let prefetchItems = items.filter { prefetchEventIds.contains($0.eventId) }
        if let oldest = prefetchItems.first, let newest = prefetchItems.last {
            let referenceDate = reference ?? AgentV2DateParser.date(newest.deliveredAt)
            return referenceDate.timeIntervalSince(AgentV2DateParser.date(oldest.deliveredAt)) < Self.PREFETCH_INTERVAL
        }
        return true
    }

    private func startPrefetch() {
        guard prefetchTask == nil, view == .all ? !hasReachedHistoryEnd : canLoadRequestedDigest else { return }
        let requestGeneration = generation
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if requestGeneration == generation { prefetchTask = nil }
            }
            if let olderPageTask, olderPageGeneration != requestGeneration {
                _ = await olderPageTask.value
            }
            while !Task.isCancelled, requestGeneration == generation, shouldPrefetch || canLoadRequestedDigest {
                guard await loadOlderPage() else { return }
                await Task.yield()
            }
        }
    }

    func markDiscussion(eventId: Int, thread: ApiAgentV2ThreadSummary) {
        localDiscussions[eventId] = .init(threadId: thread.id, icon: thread.icon)
        items = applyingLocalDiscussions(to: items)
        onChange?()
    }

    func markDigestDiscussion(id: String, thread: ApiAgentV2ThreadSummary) {
        localDigestDiscussions[id] = .init(threadId: thread.id, icon: thread.icon)
        allDigests = applyingLocalDiscussions(to: allDigests)
        digestView.digests = applyingLocalDiscussions(to: digestView.digests)
        onChange?()
    }

    func removeDiscussion(threadId: String) {
        localDiscussions = localDiscussions.filter { $0.value.threadId != threadId }
        localDigestDiscussions = localDigestDiscussions.filter { $0.value.threadId != threadId }
        allDigests = removeDigestDiscussion(threadId: threadId, from: allDigests)
        digestView.digests = removeDigestDiscussion(threadId: threadId, from: digestView.digests)
        items = items.map { item in
            guard item.discussion?.threadId == threadId else { return item }
            return ApiAgentV2NewsFeedItem(
                eventId: item.eventId,
                deliveredAt: item.deliveredAt,
                headline: item.headline,
                body: item.body,
                imageUrl: item.imageUrl,
                sources: item.sources,
                discussionNaming: item.discussionNaming
            )
        }
        onChange?()
    }

    private func removeDigestDiscussion(threadId: String, from digests: [ApiAgentV2NewsFeedDigest]) -> [ApiAgentV2NewsFeedDigest] {
        digests.map { digest in
            guard digest.discussion?.threadId == threadId else { return digest }
            return ApiAgentV2NewsFeedDigest(
                id: digest.id, deliveredAt: digest.deliveredAt, top: digest.top, total: digest.total,
                discussionNaming: digest.discussionNaming
            )
        }
    }

    /// The pages of another hour or time zone go at once. Its digests go as the refresh brings the new schedule's first
    /// page, or fails; the news stay until the refresh brings the new schedule's
    private func resetDigestsIfNeeded(for schedule: AgentNewsDigestSchedule) {
        defer { digestSchedule = schedule }
        guard let digestSchedule, digestSchedule != schedule else { return }
        isDigestResetPending = true
        reachedDigestId = nil
        hasReachedHistoryEnd = false
        prefetchEventIds = []
        prefetchDigestIds = []
        allNextCursor = nil
        requestedCursors = []
    }

    private func dropDigestsOfAnotherSchedule() {
        guard isDigestResetPending else { return }
        isDigestResetPending = false
        allDigests = []
    }

    private func applyFirstPage(_ page: ApiAgentV2NewsFeedPage, requestLanguage: String) {
        if allLocale != nil, allLocale != page.locale {
            items = []
            allDigests = []
            reachedDigestId = nil
            hasReachedHistoryEnd = false
            prefetchEventIds = []
            prefetchDigestIds = []
            localDiscussions = [:]
            localDigestDiscussions = [:]
            hasOpened = false
        }
        allLocale = page.locale
        feedLanguage = requestLanguage
        hasAllLoaded = true
        let hasOverlap = page.items.contains { prefetchEventIds.contains($0.eventId) }
            || (page.digests ?? []).contains { prefetchDigestIds.contains($0.id) }
        if !hasOverlap {
            reachedDigestId = nil
            prefetchEventIds = []
            prefetchDigestIds = []
            hasReachedHistoryEnd = false
        }
        mergePage(page)
        if !hasOpened, view == .all {
            readState.initializeIfNeeded(items: page.items)
            unreadCutoff = readState.readThrough.map(AgentV2DateParser.date)
            hasOpened = true
        }
        updateUnreadBoundary()
        if view == .all { markAllViewRead() }
        allNextCursor = page.nextCursor
        requestedCursors = []
    }

    private func mergePage(_ page: ApiAgentV2NewsFeedPage) {
        prefetchEventIds.formUnion(page.items.map(\.eventId))
        prefetchDigestIds.formUnion((page.digests ?? []).map(\.id))
        updateLocalDigestDiscussions(from: page.digests ?? [])
        var digestsById = Dictionary(uniqueKeysWithValues: allDigests.map { ($0.id, $0) })
        for digest in page.digests ?? [] { digestsById[digest.id] = digest }
        allDigests = applyingLocalDiscussions(to: digestsById.values.sorted { $0.id < $1.id })
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
                discussion: discussion,
                discussionNaming: item.discussionNaming
            )
        }
    }

    /// A digest's discussion created in the feed takes the icon a page brings for its thread
    private func updateLocalDigestDiscussions(from digests: [ApiAgentV2NewsFeedDigest]) {
        for digest in digests {
            guard let discussion = localDigestDiscussions[digest.id], digest.discussion?.threadId == discussion.threadId,
                  let icon = digest.discussion?.icon?.nilIfEmpty else { continue }
            localDigestDiscussions[digest.id] = .init(threadId: discussion.threadId, icon: icon)
        }
    }

    private func applyingLocalDiscussions(to digests: [ApiAgentV2NewsFeedDigest]) -> [ApiAgentV2NewsFeedDigest] {
        digests.map { digest in
            guard let discussion = localDigestDiscussions[digest.id] else { return digest }
            return ApiAgentV2NewsFeedDigest(
                id: digest.id, deliveredAt: digest.deliveredAt, top: digest.top, total: digest.total,
                discussion: discussion, discussionNaming: digest.discussionNaming
            )
        }
    }

    private func updateUnreadBoundary() {
        allUnreadEventId = unreadCutoff.flatMap { cutoff in
            items.first { AgentV2DateParser.date($0.deliveredAt) > cutoff }?.eventId
        }
    }

    /// The news and digests the All view has loaded are read
    private func markAllViewRead() {
        readState.markRead(items: items)
        readState.markDigestsRead(allDigests)
    }

    /// The digests delivered after the ones read before the Digests view first showed them stay new while the feed is
    /// open, and the ones it has loaded are read
    private func markDigestsShown() {
        if !hasOpenedDigests {
            readState.initializeDigestsIfNeeded(digestView.digests)
            digestUnreadCutoff = readState.digestsReadThrough.map(AgentV2DateParser.date)
            hasOpenedDigests = true
        }
        updateDigestUnreadBoundary()
        readState.markDigestsRead(digestView.digests)
    }

    private func updateDigestUnreadBoundary() {
        digestUnreadId = digestUnreadCutoff.flatMap { cutoff in
            digestView.digests.first { AgentV2DateParser.date($0.deliveredAt) > cutoff }?.id
        }
    }

    /// The feed's language for an app language, as the SDK picks it for a feed request: Russian for Russian, English for
    /// the rest
    nonisolated static func getLocale(langCode: String) -> String {
        langCode.hasPrefix("ru") ? "ru" : "en"
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
