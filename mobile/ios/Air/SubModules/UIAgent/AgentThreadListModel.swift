import Foundation
import WalletContext
import WalletCore

@MainActor
protocol AgentThreadListClient: AnyObject {
    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse
    /// The SDK's copy of the first page; `nil` when it has none or cannot read it
    func cachedThreads() async -> [ApiAgentV2ThreadListItem]?
    func updateThread(id: String, update: ApiAgentV2ThreadUpdate) async throws -> ApiAgentV2ThreadUpdateResponse
    func deleteThread(id: String) async throws -> ApiAgentV2ThreadDeleteResponse
}

@MainActor
private final class LiveAgentThreadListClient: AgentThreadListClient {
    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse {
        try await Api.listAgentV2Threads(cursor: cursor, limit: limit, query: query)
    }

    func cachedThreads() async -> [ApiAgentV2ThreadListItem]? {
        await Api.getAgentV2CachedThreads()
    }

    func updateThread(id: String, update: ApiAgentV2ThreadUpdate) async throws -> ApiAgentV2ThreadUpdateResponse {
        try await Api.updateAgentV2Thread(threadId: id, update: update)
    }

    func deleteThread(id: String) async throws -> ApiAgentV2ThreadDeleteResponse {
        try await Api.deleteAgentV2Thread(threadId: id)
    }
}

@MainActor
final class AgentThreadListModel {
    private(set) var items: [ApiAgentV2ThreadListItem] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    /// The first page of chats has loaded, or failed to: until then the list has nothing to say about them
    private(set) var hasLoaded = false
    /// The latest load of the first page failed while the list had no chats to show
    private(set) var hasLoadFailed = false
    /// The next page failed to load: the list ends with a line that loads it again
    private(set) var hasPageLoadFailed = false
    /// The rows are the SDK's copy of the first page, shown until the first page loads
    private(set) var isShowingCachedThreads = false
    private(set) var newsItems: [ApiAgentV2NewsFeedItem] = []
    /// The digests on the latest first page of the feed's view
    private(set) var newsDigests: [ApiAgentV2NewsFeedDigest] = []
    private var newsPage: AgentNewsCachedPage?
    private var newsDigestsPage: AgentNewsCachedPage?

    /// The feed's view, which the News row shows the latest of
    var newsView: ApiAgentV2NewsFeedView { getNewsView() }
    var latestNews: ApiAgentV2NewsFeedItem? {
        newsItems.max { AgentV2DateParser.date($0.deliveredAt) < AgentV2DateParser.date($1.deliveredAt) }
    }
    var latestDigest: ApiAgentV2NewsFeedDigest? {
        newsDigests.max { AgentV2DateParser.date($0.deliveredAt) < AgentV2DateParser.date($1.deliveredAt) }
    }
    var newsUnreadCount: Int {
        newsView == .digests ? readState.unreadDigestCount(newsDigests) : readState.unreadCount(items: newsItems)
    }

    var onChange: (() -> Void)?
    var onError: ((DisplayError) -> Void)?
    var onActivityChange: ((Set<String>) -> Void)?

    private let client: AgentThreadListClient
    private let newsClient: AgentNewsFeedClient
    let readState: AgentNewsReadState
    let threadReadState: AgentThreadReadState
    private let language: () -> String
    private let getNewsView: @MainActor () -> ApiAgentV2NewsFeedView
    private let preloader: AgentPreloader
    private let now: () -> Date
    private var requestGeneration = 0
    private var mutatingThreadIds: Set<String> = []
    private var activityTracker = AgentThreadActivityTracker()
    /// Threads whose answer completed while their row's preview still is the question: the row keeps the answer's
    /// last status until a list load brings the answer's preview, so the question doesn't show again in between. A
    /// load brings it when it started after the completion, or when it has the thread past the revision its run
    /// started at.
    private var heldActivities: [String: (text: String, loadCount: Int, runRevision: Int?)] = [:]
    /// The thread's revision when its latest run started, with the question; the answer moves it further
    private var runRevisions: [String: Int] = [:]
    /// Loads started so far, for telling a load that knows a completed answer from one already under way
    private var startedLoadCount = 0
    /// The first-page load whose page has not arrived yet, which the SDK's copy of the page may stand in for
    private var cacheableLoadCount: Int?
    /// A first page has loaded since the list started, after which the SDK's copy of it is older than what was shown
    private var hasLoadedFirstPage = false
    /// The latest load of the first page failed
    private var hasFirstPageLoadFailed = false
    private static let activityHoldLimit: Duration = .seconds(5)
    /// How long a reported thread missing from the first page stays in the list, as the server may not have stored a
    /// chat just created yet
    private static let missingReportedThreadLimit: TimeInterval = 60
    /// Threads as the SDK reported them, with the time of the report, kept through loads that don't have them yet or
    /// have them at an older revision, as one the server answers before it has a chat just created
    private var reportedThreads: [String: (item: ApiAgentV2ThreadListItem, reportedAt: Date)] = [:]
    /// Threads the SDK reported out of the list, as a chat cleared of its messages, with the revision that took them out:
    /// a load the server answers with an older or the same revision doesn't bring them back
    private var leftThreadRevisions: [String: Int] = [:]

    init(
        client: AgentThreadListClient? = nil,
        newsClient: AgentNewsFeedClient? = nil,
        readState: AgentNewsReadState? = nil,
        threadReadState: AgentThreadReadState? = nil,
        language: @escaping () -> String = { LocalizationSupport.shared.langCode },
        newsView: @escaping @MainActor () -> ApiAgentV2NewsFeedView = {
            AgentNewsNotificationSettings.shared.newsFeedView
        },
        preloader: AgentPreloader = .shared,
        now: @escaping () -> Date = { .now }
    ) {
        self.client = client ?? LiveAgentThreadListClient()
        self.newsClient = newsClient ?? LiveAgentNewsFeedClient()
        self.readState = readState ?? AgentNewsReadState(userDefaults: .standard)
        self.threadReadState = threadReadState ?? .shared
        self.language = language
        getNewsView = newsView
        self.preloader = preloader
        self.now = now
    }

    /// The server's chats as a choice made from them stands: loaded, still on their way, or failed to load. The SDK's
    /// copy of the list stands in for neither.
    enum ServerListState {
        case loading
        case loaded
        case failed
    }

    var serverListState: ServerListState {
        if hasLoadedFirstPage, !isShowingCachedThreads { return .loaded }
        return hasFirstPageLoadFailed && !isLoading ? .failed : .loading
    }

    /// The chat support has that was active last, of those the server's list has
    var supportThread: ApiAgentV2ThreadSummary? {
        AgentSupportRequest.findSupportThread(in: items.map(\.thread))
    }

    func refresh() async {
        syncActivitiesWithLoadedChats()
        requestGeneration += 1
        await load(cursor: nil, generation: requestGeneration, minimumCount: isShowingCachedThreads ? 0 : items.count)
    }

    func loadMore() async {
        guard !isLoading, let nextCursor else { return }
        await load(cursor: nextCursor, generation: requestGeneration)
    }

    /// Loads the first page of the feed's view, whose latest news, or digest in the Digests view, the News row shows
    func refreshNews() async {
        do {
            let requestLanguage = language()
            let schedule = AgentNewsDigestSchedule.current
            let view = newsView
            let page = try await newsClient.getNewsFeed(
                lang: requestLanguage, cursor: nil, schedule: schedule, view: view
            )
            guard !Task.isCancelled else { return }
            let cachedPage = AgentNewsCachedPage(page: page, language: requestLanguage, schedule: schedule)
            switch view {
            case .all:
                newsPage = cachedPage
                newsItems = page.items
                readState.initializeIfNeeded(items: newsItems)
            case .digests:
                newsDigestsPage = cachedPage
            }
            newsDigests = page.digests ?? []
            readState.initializeDigestsIfNeeded(newsDigests)
            onChange?()
        } catch {
            // The permanent row keeps its last successful preview when refreshing fails.
        }
    }

    /// The feed opens with the pages behind the News row while it loads the latest: in either view its cards are laid
    /// out before it slides in
    func makeNewsFeedModel(requestedDigestId: String? = nil) -> AgentNewsFeedModel {
        AgentNewsFeedModel(client: newsClient, readState: readState, language: language, findThread: { [weak self] threadId in
            self?.items.first { $0.thread.id == threadId }?.thread
        }, cachedPage: newsPage, cachedDigestsPage: newsDigestsPage, requestedDigestId: requestedDigestId)
    }

    // MARK: - Answering status

    /// What the Agent is doing in the thread while it answers, or `nil` when it is not answering there
    func getActivityText(threadId: String) -> String? {
        activityTracker.getText(threadId: threadId) ?? heldActivities[threadId]?.text
    }

    func handleAgentUpdate(_ update: ApiAgentV2ClientUpdate) {
        switch update {
        case .messageCompleted(let bound, _, _):
            holdActivity(threadId: bound.threadId)
        case .runStarted(let bound, let threadRevision, _):
            heldActivities.removeValue(forKey: bound.threadId)
            runRevisions[bound.threadId] = threadRevision
        default:
            break
        }
        notifyActivityChange(activityTracker.handle(update, now: now()))
        if case .messageCompleted(let bound, _, let finishReason) = update,
           finishReason != "delivered_to_support" {
            threadReadState.answerDidComplete(threadId: bound.threadId)
        }
    }

    private func holdActivity(threadId: String) {
        guard let text = activityTracker.getText(threadId: threadId) else { return }
        let loadCount = startedLoadCount
        heldActivities[threadId] = (text, loadCount, runRevisions[threadId])
        Task { [weak self] in
            try? await Task.sleep(for: Self.activityHoldLimit)
            guard let self, self.heldActivities[threadId]?.loadCount == loadCount else { return }
            self.releaseHeldActivities([threadId])
        }
    }

    /// Ends the held statuses of the threads, once their rows show the answer's preview or it took too long
    private func releaseHeldActivities(_ threadIds: Set<String>) {
        notifyActivityChange(takeHeldActivities(threadIds))
    }

    /// Ends the held statuses of the threads, returning those whose status changed
    private func takeHeldActivities(_ threadIds: Set<String>) -> Set<String> {
        let released = threadIds.filter { heldActivities.removeValue(forKey: $0) != nil }
        return Set(released).filter { activityTracker.getText(threadId: $0) == nil }
    }

    /// Whether the thread holds an answer the user hasn't seen
    func isUnread(_ thread: ApiAgentV2ThreadSummary) -> Bool {
        threadReadState.isUnread(thread)
    }

    func removeActivity(threadId: String) {
        runRevisions.removeValue(forKey: threadId)
        let hasRemovedHeldActivity = heldActivities.removeValue(forKey: threadId) != nil
        notifyActivityChange(activityTracker.remove(threadId: threadId).union(hasRemovedHeldActivity ? [threadId] : []))
    }

    func handleAccountsReset() {
        hasLoadedFirstPage = false
        removeAllActivities()
        reportedThreads.removeAll()
        leftThreadRevisions.removeAll()
    }

    private func removeAllActivities() {
        runRevisions.removeAll()
        let held = Set(heldActivities.keys)
        heldActivities.removeAll()
        notifyActivityChange(activityTracker.removeAll().union(held))
    }

    /// Loaded chats know whether they are answering, so they show runs that began before the list saw their updates and
    /// end runs whose last update the list missed
    func syncActivitiesWithLoadedChats() {
        let chats = preloader.getLoadedModels().compactMap { model -> AgentThreadActivityTracker.LoadedChat? in
            guard let threadId = model.threadId else { return nil }
            return AgentThreadActivityTracker.LoadedChat(
                threadId: threadId,
                isAnswering: model.hasActiveRun,
                text: Self.getAnsweringText(of: model)
            )
        }
        notifyActivityChange(activityTracker.sync(with: chats, now: now()))
    }

    /// The status a loaded chat shows while it answers: its typing row's step, or that it is writing while the answer
    /// streams. A chat whose answer has arrived shows none.
    static func getAnsweringText(of model: BaseAgentModel) -> String? {
        guard let id = model.itemIDs.last, let item = model.item(for: id) else {
            return AgentThreadActivityTracker.analyzingText
        }
        switch item {
        case .typingIndicator:
            return model.typingIndicatorStatusText?.nilIfEmpty ?? AgentThreadActivityTracker.analyzingText
        case .message(let message):
            switch message.role {
            case .user:
                return AgentThreadActivityTracker.analyzingText
            case .assistant:
                return message.isStreaming ? AgentThreadActivityTracker.writingText : nil
            case .system:
                return nil
            }
        }
    }

    private func notifyActivityChange(_ threadIds: Set<String>) {
        guard !threadIds.isEmpty else { return }
        onActivityChange?(threadIds)
    }

    // MARK: - Thread actions

    /// Moves the thread at once, as Telegram does, and back if the server refuses
    func setPinned(_ thread: ApiAgentV2ThreadSummary, isPinned: Bool) async {
        guard !mutatingThreadIds.contains(thread.id) else { return }
        replace(thread.makeCopy(isPinned: isPinned))
        let isUpdated = await update(thread, update: .init(isPinned: isPinned))
        if !isUpdated, let currentThread = items.first(where: { $0.thread.id == thread.id })?.thread {
            replace(currentThread.makeCopy(isPinned: thread.isPinned == true))
        }
    }

    private func replace(_ thread: ApiAgentV2ThreadSummary) {
        guard let index = items.firstIndex(where: { $0.thread.id == thread.id }) else { return }
        invalidateLoads()
        items[index] = ApiAgentV2ThreadListItem(thread: thread, preview: items[index].preview)
        items = sorted(items)
        onChange?()
    }

    func rename(_ thread: ApiAgentV2ThreadSummary, title: String) async {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        await update(thread, update: .init(title: title.isEmpty ? nil : title))
    }

    func delete(_ thread: ApiAgentV2ThreadSummary) async {
        guard mutatingThreadIds.insert(thread.id).inserted else { return }
        defer { mutatingThreadIds.remove(thread.id) }
        let model = preloader.getLoadedModels().first { $0.threadId == thread.id }
        model?.holdQueuedQuestions()
        do {
            let response = try await client.deleteThread(id: thread.id)
            model?.dropQueuedQuestions()
            preloader.deleteThread(id: response.threadId)
            removeThread(id: response.threadId)
            AgentSearchProvider.shared.notifyConversationChanged()
        } catch {
            model?.releaseQueuedQuestions()
            if let error = AgentV2Copy.displayError(error) {
                onError?(error)
            }
        }
    }

    /// A thread the SDK reports changed, as by a new message, a new title, its creation or its clearing: the list takes it
    /// at once, before a load brings it with the server's preview, so a list off screen is current when it shows again.
    /// As the SDK's list does, the list has a thread once the user has written in it and while it has messages, with
    /// the preview its chat shows: a chat cleared of its messages, or a news discussion nobody has written in, leaves it.
    func applyThreadChange(_ thread: ApiAgentV2ThreadSummary) {
        guard !mutatingThreadIds.contains(thread.id), !preloader.isThreadDeleted(thread.id) else { return }
        let listedIndex = items.firstIndex(where: { $0.thread.id == thread.id })
        if let listedIndex, thread.revision < items[listedIndex].thread.revision { return }
        // A report older than the one that took the thread out of the list
        if let leftRevision = leftThreadRevisions[thread.id], thread.revision < leftRevision { return }
        guard thread.isStarted, thread.messageCount > 0 else {
            leftThreadRevisions[thread.id] = max(thread.revision, leftThreadRevisions[thread.id] ?? thread.revision)
            reportedThreads.removeValue(forKey: thread.id)
            guard let listedIndex else { return }
            items.remove(at: listedIndex)
            onChange?()
            return
        }
        leftThreadRevisions.removeValue(forKey: thread.id)
        let preview = getLoadedChatPreview(threadId: thread.id)
        if let index = listedIndex {
            let item = items[index]
            guard thread != item.thread || preview != nil && preview != item.preview else { return }
            items[index] = ApiAgentV2ThreadListItem(thread: thread, preview: preview ?? item.preview)
            reportedThreads[thread.id] = (items[index], now())
        } else {
            let item = ApiAgentV2ThreadListItem(thread: thread, preview: preview)
            items.append(item)
            reportedThreads[thread.id] = (item, now())
        }
        items = sorted(items)
        onChange?()
    }

    /// The text of the latest message a loaded chat of the thread shows, the list's preview of it
    private func getLoadedChatPreview(threadId: String) -> String? {
        guard let model = preloader.model(threadId: threadId) else { return nil }
        for id in model.itemIDs.reversed() {
            guard case .message(let message)? = model.item(for: id), message.role != .system else { continue }
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return nil
    }

    func removeThread(id: String) {
        invalidateLoads()
        reportedThreads.removeValue(forKey: id)
        leftThreadRevisions.removeValue(forKey: id)
        let previousCount = items.count
        items.removeAll { $0.thread.id == id }
        removeActivity(threadId: id)
        threadReadState.remove(threadId: id)
        if items.count != previousCount { onChange?() }
    }

    func sections(
        relativeTo now: Date = .now,
        calendar: Calendar = LocalizationSupport.shared.calendar,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> [AgentThreadListSection] {
        var result = [AgentThreadListSection(id: .news, title: "", items: [])]
        for item in sorted(items) {
            let id: AgentThreadListSection.ID = item.thread.isPinned == true
                ? .pinned
                : .day(calendar.startOfDay(for: AgentV2DateParser.date(item.thread.lastActivityAt)))
            if let index = result.firstIndex(where: { $0.id == id }) {
                result[index].items.append(item)
            } else {
                let title: String
                switch id {
                case .news, .pageFailure:
                    title = ""
                case .pinned:
                    title = lang("Pinned")
                case .day(let date):
                    title = AgentThreadDateFormatting.headerText(for: date, relativeTo: now, calendar: calendar, locale: locale)
                }
                result.append(AgentThreadListSection(id: id, title: title, items: [item]))
            }
        }
        if hasPageLoadFailed, !items.isEmpty {
            result.append(AgentThreadListSection(id: .pageFailure, title: "", items: []))
        }
        return result
    }

    private func load(cursor: String?, generation: Int, minimumCount: Int = 0) async {
        startedLoadCount += 1
        let loadCount = startedLoadCount
        isLoading = true
        if cursor != nil {
            hasPageLoadFailed = false
        } else {
            hasFirstPageLoadFailed = false
            if items.isEmpty, !hasLoadedFirstPage {
                showCachedThreads(generation: generation, loadCount: loadCount)
            }
        }
        onChange?()
        do {
            var merged = cursor == nil ? [] : items
            var pageCursor = cursor
            var requestedCursors: Set<String> = []
            repeat {
                if let pageCursor { requestedCursors.insert(pageCursor) }
                let response = try await client.listThreads(cursor: pageCursor, limit: 30, query: nil)
                guard generation == requestGeneration else { return }
                for item in response.threads {
                    if let index = merged.firstIndex(where: { $0.thread.id == item.thread.id }) {
                        merged[index] = item
                    } else {
                        merged.append(item)
                    }
                }
                pageCursor = response.nextCursor.flatMap { requestedCursors.contains($0) ? nil : $0 }
            } while merged.count < minimumCount && pageCursor != nil
            // A thread that left the list stays out of it until the server has it past the change that took it out
            merged.removeAll { item in
                guard let leftRevision = leftThreadRevisions[item.thread.id] else { return false }
                guard item.thread.revision > leftRevision else { return true }
                leftThreadRevisions.removeValue(forKey: item.thread.id)
                return false
            }
            let loadedAt = now()
            for (id, reported) in reportedThreads {
                if let index = merged.firstIndex(where: { $0.thread.id == id }) {
                    if merged[index].thread.revision >= reported.item.thread.revision {
                        reportedThreads.removeValue(forKey: id)
                    } else {
                        merged[index] = reported.item
                    }
                } else if cursor == nil {
                    if loadedAt.timeIntervalSince(reported.reportedAt) <= Self.missingReportedThreadLimit {
                        merged.append(reported.item)
                    } else {
                        reportedThreads.removeValue(forKey: id)
                    }
                }
            }
            items = sorted(merged)
            if cursor == nil {
                cacheableLoadCount = nil
                isShowingCachedThreads = false
                hasLoadedFirstPage = true
                preloader.prefetchCachedHistories(of: items.map(\.thread))
            }
            nextCursor = pageCursor
            isLoading = false
            hasLoaded = true
            hasLoadFailed = false
            hasPageLoadFailed = false
            threadReadState.observe(items.map(\.thread), answeringThreadIds: Set(activityTracker.entries.keys))
            for item in items {
                guard let model = preloader.model(threadId: item.thread.id),
                      item.thread.support != model.thread?.support else { continue }
                model.refreshThreadIfNeeded(item.thread)
            }
            // The rows now have the previews of the answers that completed before this load started, and of those
            // the load has past their run's revision. Their statuses end in the change that brings the previews,
            // which also moves the rows.
            let revisions = Dictionary(items.map { ($0.thread.id, $0.thread.revision) }, uniquingKeysWith: max)
            let answered = heldActivities.filter { threadId, hold in
                if hold.loadCount < loadCount { return true }
                guard let runRevision = hold.runRevision, let revision = revisions[threadId] else { return false }
                return revision > runRevision
            }
            let released = takeHeldActivities(Set(answered.keys))
            onChange?()
            notifyActivityChange(released)
        } catch {
            guard generation == requestGeneration else { return }
            isLoading = false
            hasLoaded = true
            // A failed refresh keeps the chats shown without a word, and the SDK's copy no longer stands in for it
            if cursor == nil {
                cacheableLoadCount = nil
                hasLoadFailed = items.isEmpty
                hasFirstPageLoadFailed = true
            } else {
                hasPageLoadFailed = true
            }
            onChange?()
        }
    }

    /// Shows the SDK's copy of the first page while the first page loads. The copy leaves unread counts, held statuses
    /// and pagination alone, and a failed load keeps it on screen.
    private func showCachedThreads(generation: Int, loadCount: Int) {
        cacheableLoadCount = loadCount
        Task { [weak self, client] in
            let threads = await client.cachedThreads()
            guard let self, let threads, !threads.isEmpty,
                  generation == self.requestGeneration,
                  self.cacheableLoadCount == loadCount,
                  self.items.isEmpty else { return }
            self.items = self.sorted(threads)
            self.nextCursor = nil
            self.isShowingCachedThreads = true
            self.hasLoaded = true
            self.hasLoadFailed = false
            self.preloader.prefetchCachedHistories(of: self.items.map(\.thread))
            self.onChange?()
        }
    }

    @discardableResult
    private func update(_ thread: ApiAgentV2ThreadSummary, update: ApiAgentV2ThreadUpdate) async -> Bool {
        guard mutatingThreadIds.insert(thread.id).inserted else { return false }
        defer { mutatingThreadIds.remove(thread.id) }
        do {
            let response = try await client.updateThread(id: thread.id, update: update)
            invalidateLoads()
            if let index = items.firstIndex(where: { $0.thread.id == response.thread.id }) {
                items[index] = ApiAgentV2ThreadListItem(thread: response.thread, preview: items[index].preview)
                items = sorted(items)
            }
            onChange?()
            AgentSearchProvider.shared.notifyConversationChanged()
            return true
        } catch {
            if let error = AgentV2Copy.displayError(error) {
                onError?(error)
            }
            return false
        }
    }

    private func invalidateLoads() {
        requestGeneration += 1
        isLoading = false
    }

    private func sorted(_ items: [ApiAgentV2ThreadListItem]) -> [ApiAgentV2ThreadListItem] {
        items.sorted { lhs, rhs in
            if (lhs.thread.isPinned == true) != (rhs.thread.isPinned == true) {
                return lhs.thread.isPinned == true
            }
            let lhsDate = AgentV2DateParser.date(lhs.thread.lastActivityAt)
            let rhsDate = AgentV2DateParser.date(rhs.thread.lastActivityAt)
            return lhsDate == rhsDate ? lhs.thread.id < rhs.thread.id : lhsDate > rhsDate
        }
    }
}

struct AgentThreadListSection {
    static let newsItemId = "agent:mypulse"
    static let pageFailureItemId = "agent:page-failure"

    enum ID: Hashable {
        case news
        case pinned
        case day(Date)
        /// The line at the list's end that loads a page that failed to load again
        case pageFailure
    }

    let id: ID
    let title: String
    var items: [ApiAgentV2ThreadListItem]

    var itemIdentifiers: [String] {
        switch id {
        case .news:
            [Self.newsItemId]
        case .pageFailure:
            [Self.pageFailureItemId]
        case .pinned, .day:
            items.map { $0.thread.id }
        }
    }
}

/// What the Agent is doing in each thread while it answers, from the SDK's run updates: the analysis until its first
/// step, each step the backend reports, then the writing of the answer until it completes or the run ends
struct AgentThreadActivityTracker {
    struct Entry: Equatable {
        var runId: String?
        var text: String
        var updatedAt: Date
    }

    /// A loaded chat's own account of its answer
    struct LoadedChat: Equatable {
        let threadId: String
        let isAnswering: Bool
        let text: String?
    }

    /// A thread without updates for this long and without a loaded chat to vouch for its run is no longer shown answering
    static let staleInterval: TimeInterval = 3 * 60
    private static let finishedRunLimit = 64

    static var analyzingText: String { lang("$agent_activity_analyzing_request") }
    static var writingText: String { lang("$agent_activity_writing") }

    private(set) var entries: [String: Entry] = [:]
    /// Runs whose answer completed or that ended, oldest first: their late step updates are ignored
    private var finishedRunIds: [String] = []

    func getText(threadId: String) -> String? {
        entries[threadId]?.text
    }

    /// Applies a run update and returns the threads whose status changed
    mutating func handle(_ update: ApiAgentV2ClientUpdate, now: Date) -> Set<String> {
        switch update {
        case .runStarted(let bound, _, _):
            finishedRunIds.removeAll { $0 == bound.runId }
            return set(bound.threadId, runId: bound.runId, text: Self.analyzingText, now: now)
        case .runActivityChanged(let bound, let event):
            guard event.runId == bound.runId, !finishedRunIds.contains(bound.runId) else { return [] }
            return set(bound.threadId, runId: bound.runId, text: AgentV2Copy.runActivity(event), now: now)
        case .messageStarted(let bound, _, _, _):
            // A run that goes on to another message is answering again
            finishedRunIds.removeAll { $0 == bound.runId }
            return []
        case .textDelta(let bound, _, _), .semanticContentAvailable(let bound, _, _):
            finishedRunIds.removeAll { $0 == bound.runId }
            return set(bound.threadId, runId: bound.runId, text: Self.writingText, now: now)
        case .messageCompleted(let bound, _, _), .runCancelled(let bound):
            return finish(threadId: bound.threadId, runId: bound.runId)
        case .runFailed(let bound, _, let threadId, _, _, _, _):
            guard let target = bound?.threadId ?? threadId else { return [] }
            return finish(threadId: target, runId: bound?.runId)
        case .walletAuthorityChanged(let threadId, let preservesActiveRuns):
            // Losing the wallet's authority without a thread ends every run
            return threadId == nil && !preservesActiveRuns ? removeAll() : []
        default:
            return []
        }
    }

    /// Takes each loaded chat's word on whether it is answering, and drops threads that went quiet without one
    mutating func sync(with chats: [LoadedChat], now: Date) -> Set<String> {
        var changed = Set<String>()
        var loadedThreadIds = Set<String>()
        for chat in chats {
            loadedThreadIds.insert(chat.threadId)
            if !chat.isAnswering {
                if entries.removeValue(forKey: chat.threadId) != nil {
                    changed.insert(chat.threadId)
                }
            } else if entries[chat.threadId] == nil, let text = chat.text?.nilIfEmpty {
                entries[chat.threadId] = Entry(runId: nil, text: text, updatedAt: now)
                changed.insert(chat.threadId)
            }
        }
        for (threadId, entry) in entries
        where !loadedThreadIds.contains(threadId) && now.timeIntervalSince(entry.updatedAt) > Self.staleInterval {
            entries.removeValue(forKey: threadId)
            changed.insert(threadId)
        }
        return changed
    }

    mutating func remove(threadId: String) -> Set<String> {
        entries.removeValue(forKey: threadId) == nil ? [] : [threadId]
    }

    mutating func removeAll() -> Set<String> {
        let threadIds = Set(entries.keys)
        entries.removeAll()
        return threadIds
    }

    private mutating func set(_ threadId: String, runId: String, text: String, now: Date) -> Set<String> {
        let previous = entries[threadId]
        entries[threadId] = Entry(runId: runId, text: text, updatedAt: now)
        return previous?.text == text ? [] : [threadId]
    }

    private mutating func finish(threadId: String, runId: String?) -> Set<String> {
        if let runId, !finishedRunIds.contains(runId) {
            finishedRunIds.append(runId)
            if finishedRunIds.count > Self.finishedRunLimit {
                finishedRunIds.removeFirst(finishedRunIds.count - Self.finishedRunLimit)
            }
        }
        // A newer run of the thread keeps its status
        guard let entry = entries[threadId], runId == nil || entry.runId == nil || entry.runId == runId else { return [] }
        entries.removeValue(forKey: threadId)
        return [threadId]
    }
}

enum AgentThreadDateFormatting {
    /// A pinned row of an earlier day fewer than this many days back names its weekday, and one of a day further back its
    /// date
    private static let weekdayRowDayCount = 7

    enum DayGroup: Equatable {
        case today
        case yesterday
        case weekday
        case date
    }

    static func dayGroup(for date: Date, relativeTo now: Date, calendar: Calendar = LocalizationSupport.shared.calendar) -> DayGroup {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch daysAgo {
        // A time later than now, as a server clock running ahead stamps it, is today's, as on Android
        case ...0: return .today
        case 1: return .yesterday
        case 2...6: return .weekday
        default: return .date
        }
    }

    static func headerText(
        for date: Date,
        relativeTo now: Date = .now,
        calendar: Calendar = LocalizationSupport.shared.calendar,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> String {
        switch dayGroup(for: date, relativeTo: now, calendar: calendar) {
        case .today:
            return lang("Today")
        case .yesterday:
            return lang("Yesterday")
        case .weekday:
            // A header starts with a capital, as Today and Yesterday do, though the weekday's name is lowercase
            let text = formatted(date, template: "EEEE", calendar: calendar, locale: locale)
            return capitalizeFirstLetter(text, locale: locale)
        case .date:
            let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
            let text = formatted(date, template: sameYear ? "MMMMd" : "yMMMMd", calendar: calendar, locale: locale)
            return capitalizeFirstLetter(text, locale: locale)
        }
    }

    /// The day and month of `date`, with the year when it isn't this year's, as "November 10", without "Today"
    static func formatDayText(
        for date: Date,
        relativeTo now: Date = .now,
        calendar: Calendar = LocalizationSupport.shared.calendar,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> String {
        let isSameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        let formatter = makeFormatter(template: isSameYear ? "MMMMd" : "yMMMMd", calendar: calendar, locale: locale)
        removeYearWord(from: formatter)
        return capitalizeFirstLetter(formatter.string(from: date), locale: locale)
    }

    /// The day a chat's date line and a News day capsule name, the same on every platform: "Today", "Yesterday", then the
    /// day and the month, with the year for another year. No weekdays.
    static func formatDay(
        for date: Date,
        relativeTo now: Date = .now,
        calendar: Calendar = LocalizationSupport.shared.calendar,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> String {
        switch dayGroup(for: date, relativeTo: now, calendar: calendar) {
        case .today:
            return lang("Today")
        case .yesterday:
            return lang("Yesterday")
        case .weekday, .date:
            return formatDayText(for: date, relativeTo: now, calendar: calendar, locale: locale)
        }
    }

    private static func capitalizeFirstLetter(_ text: String, locale: Locale) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: locale) + text.dropFirst()
    }

    /// The time label of a list row, in the format all platforms share.
    ///
    /// Rows sit under day headers, so they show the time of the last message. Rows that stay at the top regardless of
    /// their date (pinned chats and News) show the time for today, the short weekday within the last week, the day and
    /// the short month within the year, and the numeric date with the year before it. Time and the numeric date follow
    /// the device's 24-hour setting and day/month order.
    static func formatRowTimestamp(
        for timestamp: String,
        shouldShowDateWhenNotToday: Bool,
        relativeTo now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = LocalizationSupport.shared.locale
    ) -> String {
        formatRowTimestamp(
            for: AgentV2DateParser.date(timestamp),
            shouldShowDateWhenNotToday: shouldShowDateWhenNotToday,
            relativeTo: now,
            calendar: calendar,
            locale: locale
        )
    }

    static func formatRowTimestamp(
        for date: Date,
        shouldShowDateWhenNotToday: Bool,
        relativeTo now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = LocalizationSupport.shared.locale,
        deviceFormat: DeviceDateTimeFormat = .current
    ) -> String {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        let timeText = deviceFormat.formatTime(hour: time.hour ?? 0, minute: time.minute ?? 0)
        guard shouldShowDateWhenNotToday else { return timeText }
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        if daysAgo <= 0 {
            return timeText
        }
        if daysAgo < weekdayRowDayCount {
            return formatted(date, template: "EEE", calendar: calendar, locale: locale)
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return makeDotlessFormatter(template: "MMMd", calendar: calendar, locale: locale).string(from: date)
        }
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return deviceFormat.formatDate(day: components.day ?? 1, month: components.month ?? 1, year: components.year)
    }

    /// The time and numeric date conventions of the device, as Telegram derives them from the system settings
    struct DeviceDateTimeFormat: Equatable {
        enum DateOrder: Equatable {
            case dayFirst
            case monthFirst
        }

        var isUsing24HourTime: Bool
        var dateOrder: DateOrder
        var dateSeparator: String
        var dateSuffix: String
        var isFullYearRequired: Bool

        static var current: DeviceDateTimeFormat {
            let locale = Locale.autoupdatingCurrent
            let timeFormatter = DateFormatter()
            timeFormatter.locale = locale
            timeFormatter.dateStyle = .none
            timeFormatter.timeStyle = .medium
            let timeText = timeFormatter.string(from: Date())
            let isUsing24HourTime = !timeText.contains(timeFormatter.amSymbol) && !timeText.contains(timeFormatter.pmSymbol)

            var order = DateOrder.dayFirst
            var separator = "."
            var suffix = ""
            var isFullYearRequired = false
            if let format = DateFormatter.dateFormat(fromTemplate: "MdY", options: 0, locale: locale) {
                for candidate in [". ", ".", "/", "-"] where format.contains(candidate) {
                    if candidate == ". " {
                        separator = "."
                        suffix = "."
                        isFullYearRequired = true
                    } else {
                        separator = candidate
                    }
                    break
                }
                if let monthIndex = format.firstIndex(of: "M"), let dayIndex = format.firstIndex(of: "d") {
                    order = monthIndex < dayIndex ? .monthFirst : .dayFirst
                }
            }
            return DeviceDateTimeFormat(
                isUsing24HourTime: isUsing24HourTime,
                dateOrder: order,
                dateSeparator: separator,
                dateSuffix: suffix,
                isFullYearRequired: isFullYearRequired
            )
        }

        func formatTime(hour: Int, minute: Int) -> String {
            if isUsing24HourTime {
                return String(format: "%02d:%02d", hour, minute)
            }
            let hour12 = hour % 12 == 0 ? 12 : hour % 12
            return String(format: "%d:%02d\u{00a0}%@", hour12, minute, hour < 12 ? "AM" : "PM")
        }

        func formatDate(day: Int, month: Int, year: Int?) -> String {
            let first = dateOrder == .dayFirst ? day : month
            let second = dateOrder == .dayFirst ? month : day
            var text = String(format: "%02d%@%02d", first, dateSeparator, second)
            if let year {
                let yearText = isFullYearRequired ? String(format: "%04d", year) : String(format: "%02d", year % 100)
                text += dateSeparator + yearText
            }
            return text + dateSuffix
        }
    }

    /// Russian abbreviates every month to three letters, as Telegram does: "7 ноя", "4 сен"
    private static let russianShortMonthSymbols = [
        "янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек",
    ]

    /// A formatter of `template` whose abbreviated months go without their trailing dot and years without their
    /// abbreviated word, as Telegram writes dates, as in "Nov 7", "7 ноя" and "7 ноя 2025". Russian months are cut to
    /// three letters, where the system writes "нояб." and "сент.". A month with dots inside, as "ต.ค.", keeps them all.
    static func makeDotlessFormatter(template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = makeFormatter(template: template, calendar: calendar, locale: locale)
        removeYearWord(from: formatter)
        if locale.language.languageCode == .russian && calendar.identifier == .gregorian {
            formatter.shortMonthSymbols = russianShortMonthSymbols
            formatter.shortStandaloneMonthSymbols = russianShortMonthSymbols
            return formatter
        }
        func removeDots(_ symbols: [String]) -> [String] {
            symbols.map { $0.hasSuffix(".") && !$0.dropLast().contains(".") ? String($0.dropLast()) : $0 }
        }
        formatter.shortMonthSymbols = removeDots(formatter.shortMonthSymbols)
        formatter.shortStandaloneMonthSymbols = removeDots(formatter.shortStandaloneMonthSymbols)
        return formatter
    }

    /// Leaves out the abbreviated word after a year, as Russian's "г." in "d MMMM y 'г'.", from the formatter's format.
    /// The dot tells it from a word that joins the year to the time, as English's "at".
    private static func removeYearWord(from formatter: DateFormatter) {
        formatter.dateFormat = formatter.dateFormat.replacingOccurrences(
            of: "(?<=y)\\s*'\\p{L}+'\\.",
            with: "",
            options: .regularExpression
        )
    }

    private static func formatted(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        makeFormatter(template: template, calendar: calendar, locale: locale).string(from: date)
    }

    private static func makeFormatter(template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
