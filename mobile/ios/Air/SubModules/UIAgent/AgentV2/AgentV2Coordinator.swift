import Foundation
import WalletContext
import WalletCore

private let log = Log("AgentV2Coordinator")

@MainActor
enum AgentV2CoordinatorChange: Equatable {
    case reload
    /// A missing account id marks an account reset
    case walletSelectionChanged(accountId: String?)
    case messagesHydrated
    case messageIdReconciled(localId: String, canonicalId: String)
    case messageUpdated(id: String)
    case runTerminated(ApiAgentV2RunResultState)
}

@MainActor
protocol AgentV2CoordinatorObserver: AnyObject {
    func agentV2CoordinatorDidChange(_ coordinator: AgentV2Coordinator, change: AgentV2CoordinatorChange)
}

@MainActor
final class AgentV2Coordinator: WalletCoreData.EventsObserver, @unchecked Sendable {
    private static let initialHostContextMaxAttempts = 3
    static let defaultSupportPollingInterval: TimeInterval = 15
    private static let maxSupportHistoryPages = 10

    private final class WeakObserver {
        weak var value: AgentV2CoordinatorObserver?
        init(_ value: AgentV2CoordinatorObserver) { self.value = value }
    }

    struct RunState: Equatable, Sendable {
        let generation: Int
        /// The client chooses the id before it starts the run, so every update and result of the run carries it
        let clientRunId: String
        /// The runtime has reported the run, so a retry resumes it rather than sending the input again
        var isConfirmed: Bool
        var runId: String?
        let threadId: String
        var localInputMessageId: String?
        var isRunning: Bool
        var isSupportAppend = false
        /// The run asks for a support operator, which a limit never holds back for Retry
        var isSupportRequest = false
        var isUnsubmittedDiscussionSupportRequest = false
        var discussionSupportAccountId: String?
        /// The answers the run has started, which a stop ends whether or not their text is still coming
        var answerMessageIds: Set<String> = []
    }

    struct ResolvedAction: Sendable {
        let value: ApiAgentV2ResolvedAction
        let accountId: String
    }

    struct LimitRetry: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case rateLimit
            case userQuota
        }

        let kind: Kind
        let clientRunId: String
        let threadId: String
        let resetAt: Double?
        /// The wallet the question was asked for: a switch to another one drops it, while the same wallet's authority
        /// published again keeps it
        let accountId: String?
        /// Sent to support, which takes it on Retry, while a question asked before support took the chat has none there
        let isSupportAppend: Bool
        /// The bubble of a message sent to support, which stays while the limit holds it back
        let localInputMessageId: String?
    }

    /// A support request the server didn't take, which shows with its failure until the next question
    struct FailedSupportRequest: Equatable, Sendable {
        let clientRunId: String
        let message: AgentV2NativeMessage
        let code: ApiAgentV2ErrorCode?
    }

    private enum ErrorSource {
        case agentUnavailable
        case newsUnavailable
        case digestUnavailable
        case failedToLoadChat(ApiAgentV2ErrorCode?)
        case run(ApiAgentV2ErrorCode)
    }

    private enum RunUpdateDisposition: Equatable {
        case active
        case retiredActive
        case standalone
    }

    private final class FeedbackRequest {
        let feedback: ApiAgentV2AnswerFeedback?

        init(feedback: ApiAgentV2AnswerFeedback?) {
            self.feedback = feedback
        }
    }

    /// The rating requests of one answer that have not all settled yet
    private final class FeedbackRequests {
        /// Settles the rating; the SDK sends an answer's requests in order, so it settles last
        var latest: FeedbackRequest
        /// The rating the server keeps after the requests settled so far
        var saved: ApiAgentV2AnswerFeedback?

        init(latest: FeedbackRequest, saved: ApiAgentV2AnswerFeedback?) {
            self.latest = latest
            self.saved = saved
        }
    }

    let client: AgentV2Client
    private(set) var thread: ApiAgentV2ThreadSummary?
    var messages: [AgentV2NativeMessage] { conversation.messages }

    var supportState: AgentSupportState {
        switch thread?.support?.state {
        case .waiting:
            return .waiting
        case .operator:
            // The operator who wrote or joined last, as the chat's header names them
            for message in messages.reversed() {
                if message.role == .operator, let author = message.operatorAuthor {
                    return .operator(author)
                }
                if case .operatorJoined(let author)? = message.supportEvent {
                    return .operator(author)
                }
            }
            return .operator(nil)
        case .closed:
            return .closed
        case nil:
            return .none
        }
    }

    var isSupportActive: Bool {
        thread?.support?.state == .waiting || thread?.support?.state == .operator
    }

    private(set) var failedSupportRequest: FailedSupportRequest?

    var isChatForegroundVisible: Bool { isChatVisible && !isInBackground }
    var isLoadingHistory: Bool { historyReadCount > 0 }
    private(set) var loadedOperatorMessageAt: String?

    private(set) var nextMessageCursor: String?
    private(set) var activeRun: RunState? {
        didSet { retireReplacedStoppedAnswersIfAdmitted() }
    }
    private(set) var runActivity: ApiAgentV2RunActivityEvent?
    private(set) var availability = ApiAgentV2AvailabilityState(state: .available)
    private(set) var userQuota: ApiAgentV2UserQuota?
    private(set) var hints: ApiAgentV2HintsResponse?
    private(set) var limitRetry: LimitRetry?
    private(set) var hasHydratedMessages = false
    /// The messages are the SDK's copy of the thread's latest ones, shown until the history loads. Nothing in them can be
    /// acted on, rated or asked for again, and they have no older page.
    private(set) var isShowingCachedMessages = false {
        didSet {
            if !isShowingCachedMessages {
                hasCachedHistoryFailed = false
            }
        }
    }
    /// The cached messages stay with a failure, and since then without their suggestions
    private(set) var hasCachedHistoryFailed = false
    /// The chat has shown cached messages, so its timeline follows whatever replaces them
    private(set) var hasShownCachedMessages = false
    private var unloadedMessageCount = 0

    var seenMessageCount: Int? {
        guard hasHydratedMessages else { return nil }
        return unloadedMessageCount + messages.filter { !$0.status.isStreaming && $0.role != .event }.count
    }

    /// The message that follows the first `seenMessageCount` ones counted as `seenMessageCount` counts them, without
    /// the messages in `ignoredIDs`. Seen messages beyond the loaded ones leave the first loaded message.
    func getFirstUnseenMessageID(seenMessageCount: Int, ignoredIDs: Set<String>) -> String? {
        guard hasHydratedMessages else { return nil }
        let settled = messages.filter { !$0.status.isStreaming && $0.role != .event && !ignoredIDs.contains($0.id) }
        let index = max(0, seenMessageCount - unloadedMessageCount)
        return index < settled.count ? settled[index].id : nil
    }

    /// Whether the server takes problem reports, as its check last answered, once the thread loaded and whenever the
    /// chat is shown; nil until it has answered
    private(set) var problemReportAvailability: Bool?

    /// Reports are taken until the server's check says otherwise
    var isProblemReportAvailable: Bool {
        problemReportAvailability ?? true
    }

    /// The user has allowed the Agent, as far as the chat knows: an opening whose consent read says so, or before its
    /// read, as the app last knew it, or a thread loaded with consent
    var hasConsent: Bool {
        guard !needsConsentToSend, !needsOpeningConsent else { return false }
        return isOpening ? hasOpeningConsent || client.isConsentKnownGiven : thread != nil
    }

    /// Reports waiting for the thread, which an opening creates
    private var threadWaiters: [CheckedContinuation<Void, Never>] = []

    var error: String? {
        switch errorSource {
        case .agentUnavailable: lang("Agent is unavailable")
        case .newsUnavailable: lang("$agent_news_unavailable")
        case .digestUnavailable: lang("$agent_digest_unavailable")
        case .failedToLoadChat(let code): Self.loadErrorText(code)
        case .run(let code): AgentV2Copy.error(code, resetAt: userQuotaResetDate)
        case nil: nil
        }
    }

    /// A history request cannot fail a wallet operation. Keep actionable connection/session errors, but name
    /// the failed read for other codes, including a tool error returned by the SDK's read operation.
    private static func loadErrorText(_ code: ApiAgentV2ErrorCode?) -> String {
        guard let code else { return lang("Failed to load chat") }
        switch code {
        case .clientUpdateRequired, .deviceTokenMissing, .deviceTokenInvalid, .deviceTokenExpired,
             .profileIdInvalid, .profileDeleted, .networkError, .invalidEvent:
            return AgentV2Copy.error(code)
        default:
            return lang("Failed to load chat")
        }
    }

    /// The chat couldn't load its messages, which Retry loads again
    var isLoadFailure: Bool {
        if case .failedToLoadChat? = errorSource {
            return true
        }
        return false
    }

    /// Loads the chat again after it failed to: its newest messages, or the whole chat if none had loaded
    func retryLoad() {
        guard !isStopped, loadRetryTask == nil else { return }
        let shouldReloadMessages = hasHydratedMessages || isLoadFailure && thread != nil
        errorSource = nil
        notifyObservers()
        if shouldReloadMessages {
            // News can fail its history read while startup still publishes host context. Retry the read now,
            // without waiting for that independent work or starting a second request on another tap.
            loadRetryTask = Task { [weak self] in
                guard let self else { return }
                defer { self.loadRetryTask = nil }
                await self.hydrate()
            }
        } else if let startupTask {
            // The chat failed while startup still waits for its hints, which would end it without loading again
            loadRetryTask = Task { [weak self] in
                await startupTask.value
                guard let self else { return }
                defer { self.loadRetryTask = nil }
                self.start()
            }
        } else {
            start()
        }
    }

    /// The error is the failure of a run, which its failed answer may show as well
    var isRunFailure: Bool {
        if case .run? = errorSource {
            return true
        }
        return false
    }

    var isInputBlockedByLimit: Bool { inputLimitErrorCode != nil }

    var userQuotaResetDate: Date? {
        if let limitRetry, limitRetry.kind == .userQuota {
            return limitRetry.resetAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
        }
        return userQuota.map { AgentV2DateParser.date($0.resetAt) }
    }

    /// The limit that blocks sending now, if any. An operator's chat is answered without the model, so neither the
    /// capacity nor the daily quota blocks it.
    var inputLimitErrorCode: ApiAgentV2ErrorCode? {
        let now = Date()
        let isSupportActive = isSupportActive
        if !isSupportActive,
           availability.state == .capacityExhausted,
           let resetAt = availability.resetAt,
           Date(timeIntervalSince1970: resetAt / 1_000) > now {
            return .agentCapacityExhausted
        }
        if !isSupportActive,
           let userQuota,
           limitRetry?.kind != .userQuota,
           userQuota.remaining == 0,
           AgentV2DateParser.date(userQuota.resetAt) > now {
            return .userQuotaExhausted
        }
        if isRateLimitWaiting {
            return .rateLimited
        }
        if !isSupportActive,
           let retry = limitRetry,
           let resetAt = retry.resetAt,
           Date(timeIntervalSince1970: resetAt / 1_000) > now {
            return .userQuotaExhausted
        }
        return nil
    }

    /// A rate limit holds a question back until it resets, which a support request waits for too
    var isRateLimitWaiting: Bool {
        guard let retry = limitRetry, retry.kind == .rateLimit, let resetAt = retry.resetAt else { return false }
        return Date(timeIntervalSince1970: resetAt / 1_000) > Date()
    }

    /// A limit holds back a question that Retry sends again; while support has the chat, only a message sent to support
    var hasLimitRetry: Bool {
        guard let limitRetry else { return false }
        return !isSupportActive || limitRetry.isSupportAppend
    }

    var canRetryLimit: Bool {
        hasLimitRetry && activeRun?.isRunning != true && !isInputBlockedByLimit
    }

    struct Opening {
        enum Source {
            case question(text: String, entryPoint: ApiAgentV2EntryPoint?)
            case news(ApiAgentV2ThreadNewsRequest, ApiAgentV2ThreadNewsCard?)
            case digest(ApiAgentV2ThreadDigestRequest)
        }

        let source: Source
        let inputMessageId = "local-opening-\(UUID().uuidString.lowercased())"
        let createdAt = Date()

        var text: String {
            switch source {
            case .question(let text, _): text
            case .news(_, let preview): preview?.headline ?? ""
            case .digest: ""
            }
        }

        var entryPoint: ApiAgentV2EntryPoint? {
            switch source {
            case .question(_, let entryPoint): entryPoint ?? .agentTab
            case .news, .digest: nil
            }
        }

        var isQuestion: Bool {
            if case .question = source { return true }
            return false
        }
    }

    private let newsRequest: ApiAgentV2ThreadNewsRequest?
    private let digestRequest: ApiAgentV2ThreadDigestRequest?
    private let shouldDeferThread: Bool
    private(set) var discussionNaming: ApiAgentV2NewsFeedItem.DiscussionNaming?
    private var hasRequestedDiscussionThread = false
    private(set) var hasLoadedDiscussionStatus = false
    private(set) var isDiscussionSupportRequest = false

    var isDeferredDiscussion: Bool {
        shouldDeferThread && !hasHydratedMessages
    }

    var isWaitingForFirstDiscussionMessage: Bool {
        isDeferredDiscussion && !hasRequestedDiscussionThread
    }

    var isCreatingDiscussionThread: Bool {
        isDeferredDiscussion && hasRequestedDiscussionThread && thread == nil && startupTask != nil
    }

    var isAwaitingDiscussionStatus: Bool {
        isDeferredDiscussion && hasOpeningConsent && !hasLoadedDiscussionStatus
    }

    var isDiscussion: Bool {
        news != nil || newsRequest != nil || digest != nil || digestRequest != nil
    }
    private(set) var newsPreview: ApiAgentV2ThreadNewsCard?
    /// The digest as the feed's card showed it, which the digest discussion's post shows until its thread comes
    private(set) var digestPreview: ApiAgentV2ThreadDigestCard?
    private var opening: Opening?
    private var queuedOpenings: [Opening] = []
    private var openingFinished = false
    private var openingRunAttempted = false
    private var openingBaselineMessageIds = Set<String>()
    private var openingMessageDates: [String: Date] = [:]
    private var openingCanonicalInputMessageId: String?
    private var hasOpeningConsent = false
    private(set) var needsOpeningConsent = false
    /// A news discussion opened before the user allowed the Agent: its post and suggestions show, and its first
    /// message, suggestion or recording asks for consent in the sheet
    private(set) var needsConsentToSend = false
    /// A news discussion opening whose consent read hasn't answered, as it is under way or failed, without consent the
    /// app knows: whether what it sends needs the sheet is still unknown
    var isConsentToSendUnknown: Bool {
        isOpening && opening?.isQuestion == false && !hasOpeningConsent && !needsConsentToSend
            && !client.isConsentKnownGiven
    }
    private(set) var isAcceptingOpeningConsent = false
    var resolveOpeningThread: ((ApiAgentV2ThreadSummary) -> Bool)?
    var onOpeningThreadCreated: ((ApiAgentV2ThreadSummary) -> Void)?
    var onOpeningFinished: (() -> Void)?
    /// The thread's latest history loaded, or `nil` once the thread has none to show
    var onCachedHistoryChange: ((String, AgentCachedHistory?) -> Void)?

    /// The digest a digest discussion is about; a news discussion has none
    var digest: ApiAgentV2ThreadDigestCard? {
        news == nil ? thread?.digest ?? digestPreview : nil
    }

    var news: ApiAgentV2ThreadNewsCard? {
        guard let news = thread?.news else { return newsPreview }
        guard let newsPreview, newsPreview.eventId == news.eventId else { return news }
        return ApiAgentV2ThreadNewsCard(
            eventId: news.eventId,
            headline: news.headline,
            excerpt: news.excerpt,
            imageUrl: news.imageUrl,
            publishedAt: news.publishedAt,
            source: news.source ?? newsPreview.source,
            body: news.body ?? newsPreview.body,
            sources: Self.fillSourceNames(news.sources, from: newsPreview.sources)
        )
    }

    /// The thread's sources, named as the feed named them where the thread leaves a name out, so the post keeps showing
    /// the source the card showed
    private static func fillSourceNames(
        _ sources: [ApiAgentV2NewsFeedItem.Source]?,
        from preview: [ApiAgentV2NewsFeedItem.Source]?
    ) -> [ApiAgentV2NewsFeedItem.Source]? {
        guard let sources else { return preview }
        guard let preview else { return sources }
        return sources.map { source in
            guard source.name?.isEmpty != false,
                  let name = preview.first(where: { $0.url == source.url })?.name, !name.isEmpty else { return source }
            return ApiAgentV2NewsFeedItem.Source(name: name, url: source.url)
        }
    }

    func updateNewsPreview(_ preview: ApiAgentV2ThreadNewsCard) {
        newsPreview = preview
        notifyObservers()
    }

    func updateDigestPreview(_ preview: ApiAgentV2ThreadDigestCard) {
        digestPreview = preview
        notifyObservers()
    }

    func updateDiscussionNaming(_ naming: ApiAgentV2NewsFeedItem.DiscussionNaming?) {
        discussionNaming = naming
        notifyObservers()
    }

    func requestDiscussionThreadCreation(isSupportRequest: Bool = false) {
        guard isWaitingForFirstDiscussionMessage, !isStopped else { return }
        hasRequestedDiscussionThread = true
        isDiscussionSupportRequest = isSupportRequest
        startOpening()
    }

    var openingInputMessageId: String? { opening?.isQuestion == true ? opening?.inputMessageId : nil }
    var presentationOpeningInputMessageId: String? {
        queuedOpenings.last?.inputMessageId ?? openingCanonicalInputMessageId ?? openingInputMessageId
    }
    var hasOpening: Bool { opening != nil || !queuedOpenings.isEmpty }
    var hasPendingOpenings: Bool { isOpening || !queuedOpenings.isEmpty }
    var isOpening: Bool { opening != nil && !openingFinished }
    var canRetryOpening: Bool {
        !isSupportActive && isOpening && error != nil && startupTask == nil
            && activeRun?.isRunning != true && !isInputBlockedByLimit
    }
    var showsOpeningTypingIndicator: Bool {
        (opening?.isQuestion == true && isOpening || !queuedOpenings.isEmpty)
            && error == nil && !needsOpeningConsent && activeRun?.isRunning != false
    }

    func openingMessageDate(id: String) -> Date? { openingMessageDates[id] }

    private var revision = 1
    private var conversation = AgentV2ConversationState()
    private var observers: [WeakObserver] = []
    private var startupTask: Task<Void, Never>?
    private var threadCreationTask: Task<ApiAgentV2ThreadSummary, Error>?
    private var deletionTask: Task<Void, Error>?
    private(set) var isDeletingChat = false
    private var loadRetryTask: Task<Void, Never>?
    private var initialHostContextTask: Task<Bool, Never>?
    private var statusRefreshTask: Task<Void, Never>?
    private var problemReportAvailabilityTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    /// The thread's revision when the user stopped an answer; the thread saved by the server's cancellation is newer
    private var stoppedThreadRevision: Int?
    /// The bubbles of stopped messages to support under their local ids, which stay until the next history the chat
    /// applies tells whether the server took them
    private var stoppedSupportInputIds: Set<String> = []
    /// The answers the user stopped in this chat, as they showed. A reload keeps one as it showed while the server's
    /// saved version has less of its text, or none of it; once the server has as much, the server's version stays.
    private var stoppedAnswers: [String: AgentV2NativeMessage] = [:]
    /// The stopped answers an edit or a regeneration replaces, forgotten once the server admits its run. Until then a
    /// history load leaves them out; a run rejected before admission keeps them.
    private var replacedStoppedAnswers: (clientRunId: String, messageIds: Set<String>)?
    private var presentationExpiryTasks: [String: Task<Void, Never>] = [:]
    private var hydrationGeneration = 0
    private var historyReadCount = 0
    private var supportPollingTimer: Timer?
    private var supportRefreshTask: Task<Void, Never>?
    private var needsSupportRefresh = false
    private var isSupportRefreshDeferred = false
    private var isRefreshingSupportHistory = false
    private var actionGeneration = 0
    private var runGeneration = 0
    private var retiredClientRunIds = Set<String>()
    private var retiredRunIds = Set<String>()
    private var terminalErrorSourcesByClientRunId: [String: ErrorSource] = [:]
    private var failedMessageIdsByClientRunId: [String: String] = [:]
    private var supportResendClientRunId: String?
    private var supportRevisionConflictClientRunId: String?
    private var limitExpiryTask: Task<Void, Never>?
    private var errorSource: ErrorSource? {
        didSet {
            if errorSource != nil, isShowingCachedMessages {
                hasCachedHistoryFailed = true
            }
        }
    }
    private var isStopped = false
    private var isChatVisible = false
    private var isInBackground = false
    private var isChatActive = false
    private var chatActivityTask: Task<Void, Never>?
    private var feedbackRequestsByMessageId: [String: FeedbackRequests] = [:]
    /// The chat opened on an existing thread by its id, whose history the SDK may have a copy of
    private let canShowCachedMessages: Bool
    /// The hydration whose history request is still under way, which the SDK's copy may stand in for
    private var cacheableHydrationGeneration: Int?
    private var initialContentWaiters: [CheckedContinuation<Void, Never>] = []
    private let hostContextProvider: AgentV2HostContextProvider
    private let initialHostContextRetryDelay: Duration
    /// The wallet's active account, whose actions the chat resolves and which a question that waits is asked for
    private let activeAccount: @MainActor () -> MAccount?
    /// How often a chat support has reads its latest history while it shows
    private let supportPollingInterval: TimeInterval

    /// The wallet the user is in
    var activeAccountID: String? {
        activeAccount()?.id
    }

    /// The wallet's authority is being published again, as after an account change: the questions that wait go once it
    /// is
    var isAwaitingAuthorityContext: Bool {
        hostContextProvider.isRepublishingAuthorityContext
    }

    init(
        client: AgentV2Client,
        thread: ApiAgentV2ThreadSummary? = nil,
        initialHostContextRetryDelay: Duration = .seconds(1),
        news: ApiAgentV2ThreadNewsCard? = nil,
        newsRequest: ApiAgentV2ThreadNewsRequest? = nil,
        shouldDeferThread: Bool = false,
        discussionNaming: ApiAgentV2NewsFeedItem.DiscussionNaming? = nil,
        digestRequest: ApiAgentV2ThreadDigestRequest? = nil,
        digest: ApiAgentV2ThreadDigestCard? = nil,
        question: String? = nil,
        entryPoint: ApiAgentV2EntryPoint? = nil,
        cachedHistory: AgentCachedHistory? = nil,
        isSummaryCached: Bool = false,
        supportPollingInterval: TimeInterval = AgentV2Coordinator.defaultSupportPollingInterval,
        activeAccount: @escaping @MainActor () -> MAccount? = { AccountStore.account }
    ) {
        self.client = client
        self.supportPollingInterval = supportPollingInterval
        self.activeAccount = activeAccount
        self.thread = thread
        self.newsPreview = news
        digestPreview = digest
        canShowCachedMessages = !isSummaryCached && (thread?.messageCount ?? 0) > 0
            && thread?.news == nil && thread?.digest == nil
            && news == nil && newsRequest == nil && digestRequest == nil && digest == nil && question == nil
        self.newsRequest = newsRequest
        self.shouldDeferThread = shouldDeferThread
        self.discussionNaming = discussionNaming
        hasOpeningConsent = shouldDeferThread && client.isConsentKnownGiven
        needsConsentToSend = shouldDeferThread && !hasOpeningConsent
        self.digestRequest = digestRequest
        if let digestRequest {
            opening = Opening(source: .digest(digestRequest))
        } else if let newsRequest {
            opening = Opening(source: .news(newsRequest, news))
        } else if let question {
            opening = Opening(source: .question(text: question, entryPoint: entryPoint))
        }
        revision = thread?.revision ?? 1
        self.initialHostContextRetryDelay = initialHostContextRetryDelay
        hostContextProvider = AgentV2HostContextProvider(client: client, activeAccount: activeAccount)
        hostContextProvider.isRunActive = { [weak self] in
            self?.activeRun?.isRunning == true
        }
        hostContextProvider.onAuthorityContextInvalidated = { [weak self] in
            self?.handleAuthorityContextInvalidation()
        }
        hostContextProvider.onAuthorityContextPublished = { [weak self] in
            self?.refreshActionPresentations()
            self?.loadStartupStatusIfNeeded()
            self?.notifyAuthorityContextPublished()
        }
        WalletCoreData.add(eventObserver: self)
        if let cachedHistory {
            showCachedHistory(cachedHistory)
        }
    }

    deinit {
        supportPollingTimer?.invalidate()
        supportRefreshTask?.cancel()
        startupTask?.cancel()
        loadRetryTask?.cancel()
        initialHostContextTask?.cancel()
        statusRefreshTask?.cancel()
        runTask?.cancel()
        limitExpiryTask?.cancel()
        presentationExpiryTasks.values.forEach { $0.cancel() }
    }

    func start() {
        guard !isStopped, startupTask == nil, !hasHydratedMessages else { return }
        if isOpening {
            seedOpeningMessage()
            startOpening()
            return
        }
        startupTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.startupTask = nil
                self.resumeInitialContentWaiters()
                self.startNextOpeningIfPossible()
            }
            await self.prepareStartup {
                if self.thread != nil {
                    await self.hydrate()
                } else {
                    await self.loadDefaultThread()
                }
            }
        }
    }

    private func prepareStartup(loadConversation: () async -> Void) async {
        let shouldReloadStartupStatus = statusRefreshTask != nil && !isDeferredDiscussion
        let requiresHostContext = !isDiscussion
        if initialHostContextTask == nil {
            initialHostContextTask = Task { [weak self] in
                guard let self else { return false }
                for attempt in 0..<Self.initialHostContextMaxAttempts {
                    let didPublishHostContext = await self.hostContextProvider.start()
                    guard !Task.isCancelled, !self.isStopped else { return false }
                    if didPublishHostContext { return true }
                    if requiresHostContext {
                        self.errorSource = .agentUnavailable
                        self.notifyObservers()
                    }
                    guard attempt + 1 < Self.initialHostContextMaxAttempts else { return false }
                    do {
                        try await Task.sleep(for: self.initialHostContextRetryDelay)
                    } catch {
                        return false
                    }
                }
                return false
            }
        }
        let hostContextTask = initialHostContextTask
        if !requiresHostContext {
            await loadConversation()
        }
        let didPublishHostContext = await hostContextTask?.value == true
        guard !Task.isCancelled, !isStopped else { return }
        guard didPublishHostContext else {
            initialHostContextTask = nil
            return
        }
        if shouldReloadStartupStatus {
            statusRefreshTask?.cancel()
            statusRefreshTask = nil
        }
        loadStartupStatusIfNeeded()
        if requiresHostContext { errorSource = nil }
        guard opening?.isQuestion != true, !isDiscussion else {
            if requiresHostContext { await loadConversation() }
            return
        }
        async let hints = loadStartupHints()
        if requiresHostContext { await loadConversation() }
        let response = await hints
        guard !isStopped, !isDiscussion, self.hints != response else { return }
        self.hints = response
        notifyObservers()
    }

    /// The availability, the quota and the problem report's availability, which the SDK gives only with consent
    private func loadStartupStatusIfNeeded() {
        guard !isStopped, !needsConsentToSend, statusRefreshTask == nil else { return }
        statusRefreshTask = Task { [weak self, client] in
            async let availability: Void = client.loadAvailability()
            async let userQuota: Void = client.loadUserQuota()
            _ = await (availability, userQuota)
            guard !Task.isCancelled, let self, !self.isStopped, self.isDeferredDiscussion else { return }
            self.hasLoadedDiscussionStatus = true
            self.notifyObservers()
        }
        if isDeferredDiscussion { notifyObservers() }
        refreshProblemReportAvailability()
    }

    private func loadStartupHints() async -> ApiAgentV2HintsResponse? {
        guard !isStopped, opening?.isQuestion != true, !isDiscussion else { return nil }
        return try? await client.hints()
    }

    private func openingMessage(_ opening: Opening) -> AgentV2NativeMessage {
        AgentV2NativeMessage(
            id: opening.inputMessageId,
            threadId: thread?.id ?? "",
            role: .user,
            text: opening.isQuestion ? opening.text : news?.headline ?? opening.text,
            createdAt: opening.createdAt
        )
    }

    private func seedOpeningMessage() {
        guard let opening, opening.isQuestion else { return }
        openingMessageDates[opening.inputMessageId] = opening.createdAt
        let message = openingMessage(opening)
        if messages.contains(where: { $0.id == opening.inputMessageId }) {
            conversation.replaceMessages(messages.map { $0.id == opening.inputMessageId ? message : $0 })
        } else {
            conversation.appendMessage(message)
        }
        notifyObservers()
    }

    func transferOpening(to coordinator: AgentV2Coordinator) {
        if let newsPreview { coordinator.updateNewsPreview(newsPreview) }
        if let digestPreview { coordinator.updateDigestPreview(digestPreview) }
        guard let opening, opening.isQuestion, !openingRunAttempted else { return }
        coordinator.acceptOpening(opening)
    }

    private func acceptOpening(_ accepted: Opening) {
        guard !isStopped,
              opening?.inputMessageId != accepted.inputMessageId,
              !queuedOpenings.contains(where: { $0.inputMessageId == accepted.inputMessageId }) else { return }
        queuedOpenings.append(accepted)
        openingMessageDates[accepted.inputMessageId] = accepted.createdAt
        conversation.appendMessage(openingMessage(accepted))
        notifyObservers()
        startNextOpeningIfPossible()
    }

    private func startNextOpeningIfPossible() {
        guard !isStopped, startupTask == nil, hasHydratedMessages,
              activeRun?.isRunning != true, !isOpening, !queuedOpenings.isEmpty else { return }
        invalidateRunLifecycle(clearsActiveRun: true)
        opening = queuedOpenings.removeFirst()
        openingFinished = false
        openingRunAttempted = false
        openingCanonicalInputMessageId = nil
        hasOpeningConsent = true
        startOpening()
    }

    private func startOpening() {
        guard !isStopped, startupTask == nil, let opening else { return }
        errorSource = nil
        startupTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.isDiscussionSupportRequest, self.thread == nil {
                    self.hasRequestedDiscussionThread = false
                }
                self.isDiscussionSupportRequest = false
                self.startupTask = nil
                self.onOpeningFinished?()
                self.notifyObservers()
                self.startNextOpeningIfPossible()
            }
            do {
                if !self.hasOpeningConsent {
                    self.hasOpeningConsent = try await self.client.consent()
                    guard !Task.isCancelled, !self.isStopped else { return }
                    // The chat knows the user's consent, which its menu shows Report a Problem for, before its thread
                    defer { self.notifyObservers() }
                    if opening.isQuestion {
                        self.needsOpeningConsent = !self.hasOpeningConsent
                        if self.needsOpeningConsent { return }
                    } else {
                        self.needsConsentToSend = !self.hasOpeningConsent
                    }
                }
                if self.isDeferredDiscussion {
                    guard self.hasOpeningConsent else { return }
                    self.loadStartupStatusIfNeeded()
                    await self.statusRefreshTask?.value
                    guard !Task.isCancelled, !self.isStopped, !self.isWaitingForFirstDiscussionMessage else { return }
                    if let code = self.inputLimitErrorCode,
                       !self.isDiscussionSupportRequest || self.isRateLimitWaiting {
                        self.errorSource = .run(self.isDiscussionSupportRequest ? .rateLimited : code)
                        return
                    }
                }
                if self.thread == nil {
                    // Deletion cancels startup but must retain an in-flight create's response for cleanup.
                    let creation = Task { [client = self.client, weak self] in
                        guard let self, !self.isDeletingChat else { throw CancellationError() }
                        try Task.checkCancellation()
                        switch opening.source {
                        case .question:
                            return try await client.createThread().thread
                        case .news(let request, _):
                            return try await client.createThread(news: request).thread
                        case .digest(let request):
                            return try await client.createThread(digest: request).thread
                        }
                    }
                    self.threadCreationTask = creation
                    defer { self.threadCreationTask = nil }
                    let created = try await creation.value
                    guard !Task.isCancelled, !self.isStopped else { return }
                    guard self.resolveOpeningThread?(created) != false else { return }
                    try self.bindThread(created, notify: false)
                    if created.messageCount == 0 { self.seedOpeningMessage() }
                    self.onOpeningThreadCreated?(created)
                    AgentSearchProvider.shared.notifyConversationChanged()
                }
                guard !Task.isCancelled, !self.isStopped else { return }
                if !opening.isQuestion {
                    self.notifyObservers()
                }
                await self.prepareStartup {
                    guard !Task.isCancelled, !self.isStopped, let thread = self.thread else { return }
                    if !opening.isQuestion {
                        await self.hydrate()
                        return
                    }
                    if thread.messageCount > 0, !self.hasHydratedMessages {
                        guard await self.hydrate(), !Task.isCancelled, !self.isStopped else { return }
                    }
                    self.sendOpening()
                }
            } catch {
                guard !Task.isCancelled, !self.isStopped else { return }
                self.errorSource = self.openingError(error)
            }
        }
        notifyObservers()
    }

    private func sendOpening() {
        guard !isDeletingChat, !isStopped, let opening, opening.isQuestion else { return }
        if let code = inputLimitErrorCode {
            errorSource = .run(code)
            return
        }
        hasHydratedMessages = true
        openingBaselineMessageIds = Set(messages.map(\.id))
        openingRunAttempted = true
        send(
            input: .append(text: opening.text),
            entryPoint: opening.entryPoint,
            localInputMessageId: opening.inputMessageId
        )
    }

    func loadConsent() async throws -> Bool {
        if isDeferredDiscussion { await startupTask?.value }
        let hasConsent = try await client.consent()
        if hasConsent, isDeferredDiscussion {
            markConsentGiven()
            await statusRefreshTask?.value
        }
        return hasConsent
    }

    /// The opening's consent turned out given when read again before the sheet would ask: the opening goes on
    func confirmOpeningConsent() {
        guard needsOpeningConsent, startupTask == nil, !isStopped else { return }
        hasOpeningConsent = true
        needsOpeningConsent = false
        startOpening()
    }

    func acceptConsent() async throws {
        if isDeferredDiscussion { await startupTask?.value }
        try await client.acceptConsent()
        if isDeferredDiscussion {
            markConsentGiven()
            await statusRefreshTask?.value
        }
    }

    /// The user allowed the Agent in the sheet a news discussion opened before consent asked with
    func markConsentGiven() {
        hasOpeningConsent = true
        guard needsConsentToSend else { return }
        needsConsentToSend = false
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
        if isDeferredDiscussion || hostContextProvider.isAuthorityContextCurrent {
            loadStartupStatusIfNeeded()
        }
    }

    func acceptOpeningConsent() {
        guard needsOpeningConsent, startupTask == nil, !isStopped else { return }
        isAcceptingOpeningConsent = true
        startupTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.client.acceptConsent()
                guard !Task.isCancelled, !self.isStopped else { return }
                self.hasOpeningConsent = true
                self.needsOpeningConsent = false
                self.isAcceptingOpeningConsent = false
                self.startupTask = nil
                self.startOpening()
            } catch {
                guard !Task.isCancelled, !self.isStopped else { return }
                self.isAcceptingOpeningConsent = false
                self.startupTask = nil
                if let displayError = AgentV2Copy.displayError(error) {
                    if self.opening?.isQuestion == true {
                        self.needsOpeningConsent = false
                        self.errorSource = .agentUnavailable
                    } else {
                        AppActions.showError(error: displayError)
                    }
                }
                self.notifyObservers()
            }
        }
        notifyObservers()
    }

    func retryOpening() {
        guard canRetryOpening else { return }
        if hasHydratedMessages, let thread, openingRunAttempted {
            if let run = activeRun, run.isConfirmed {
                retryRun(clientRunId: run.clientRunId, threadId: thread.id)
            } else {
                invalidateRunLifecycle(clearsActiveRun: true)
                errorSource = nil
                startupTask = Task { [weak self] in
                    guard let self else { return }
                    defer {
                        self.startupTask = nil
                        self.notifyObservers()
                        self.startNextOpeningIfPossible()
                    }
                    guard await self.hydrate(), !Task.isCancelled, !self.isStopped else { return }
                    guard self.isOpening, self.activeRun == nil else { return }
                    self.sendOpening()
                }
                notifyObservers()
            }
        } else {
            startOpening()
        }
    }

    private func openingError(_ error: Error) -> ErrorSource {
        if digestRequest != nil,
           (error as? ApiAgentV2MutationError)?.code == .digestUnavailable
            || (error as? SdkError)?.backendMessage == "digest_unavailable" {
            return .digestUnavailable
        }
        if newsRequest != nil,
           (error as? ApiAgentV2MutationError)?.code == .newsUnavailable
            || (error as? SdkError)?.backendMessage == "news_unavailable" {
            return .newsUnavailable
        }
        return .agentUnavailable
    }

    /// Waits for the initial timeline and suggestions; status probes update independently.
    func waitForInitialLoad() async {
        await startupTask?.value
    }

    /// Waits for the initial timeline, or for the SDK's copy of it that shows while it loads
    func waitForInitialContent() async {
        guard startupTask != nil, !isShowingCachedMessages else { return }
        await withCheckedContinuation { initialContentWaiters.append($0) }
    }

    private func resumeInitialContentWaiters() {
        let waiters = initialContentWaiters
        initialContentWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func beginChatDeletion(onCompletion: @escaping (Bool) -> Void) {
        guard !isDeletingChat else { return }
        isDeletingChat = true
        let threadId = thread?.id
        let creation = threadCreationTask
        if hasPendingOpenings {
            stop()
        } else {
            notifyObservers()
        }
        deletionTask = Task { [self, client] in
            do {
                let id: String?
                if let threadId {
                    id = threadId
                } else {
                    id = try? await creation?.value.id
                }
                // A failed or unstarted creation has nothing to remove on the server
                if let id {
                    let response = try await client.deleteThread(id: id)
                    WalletCoreData.notify(event: .agentThreadDeleted(threadId: response.threadId))
                    AgentSearchProvider.shared.notifyConversationChanged()
                }
                onCompletion(true)
            } catch {
                isDeletingChat = false
                onCompletion(false)
                throw error
            }
        }
    }

    func waitForChatDeletion() async throws {
        try await deletionTask?.value
    }

    /// While the chat is on screen in the foreground, the SDK keeps the server's copy of the wallet snapshot current.
    func setChatVisible(_ isVisible: Bool) {
        let wasVisible = isChatVisible
        isChatVisible = isVisible
        updateChatActivity()
        if isVisible && !wasVisible && (isSupportActive || needsSupportRefresh) {
            needsSupportRefresh = true
            isSupportRefreshDeferred = false
        }
        updateSupportPolling()
        if thread?.support != nil { notifyObservers() }
        if isVisible {
            refreshProblemReportAvailability()
        }
    }

    private func refreshProblemReportAvailability() {
        // A loaded thread means consent, which the SDK requires for the check, unless it is a news discussion's
        // opened before consent
        guard !isStopped, thread != nil, !needsConsentToSend else { return }
        problemReportAvailabilityTask?.cancel()
        problemReportAvailabilityTask = Task { [weak self, client] in
            let isAvailable = await client.problemReportAvailability()
            guard !Task.isCancelled, let self, !self.isStopped else { return }
            let wasAvailable = self.isProblemReportAvailable
            self.problemReportAvailability = isAvailable
            if isAvailable != wasAvailable {
                self.notifyObservers()
            }
        }
    }

    private func updateChatActivity(resending: Bool = false) {
        guard !isStopped else { return }
        let isActive = isChatVisible && !isInBackground
        guard isActive != isChatActive || (resending && isActive) else { return }
        isChatActive = isActive
        sendChatActivity(isActive)
    }

    private func sendChatActivity(_ isActive: Bool) {
        // Calls stay in order, so the SDK ends with the latest state.
        let previous = chatActivityTask
        chatActivityTask = Task { [client] in
            await previous?.value
            await client.setChatActive(isActive)
        }
    }

    func stop() {
        guard !isStopped else { return }
        if isChatActive {
            isChatActive = false
            sendChatActivity(false)
        }
        isStopped = true
        isDiscussionSupportRequest = false
        supportPollingTimer?.invalidate()
        supportPollingTimer = nil
        supportRefreshTask?.cancel()
        supportRefreshTask = nil
        if !isDeletingChat { threadCreationTask?.cancel() }
        startupTask?.cancel()
        startupTask = nil
        loadRetryTask?.cancel()
        loadRetryTask = nil
        initialHostContextTask?.cancel()
        initialHostContextTask = nil
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
        problemReportAvailabilityTask?.cancel()
        problemReportAvailabilityTask = nil
        resumeThreadWaiters()
        WalletCoreData.remove(observer: self)
        hostContextProvider.stop()
        invalidateRunLifecycle(clearsActiveRun: true)
        limitExpiryTask?.cancel()
        limitExpiryTask = nil
        hydrationGeneration += 1
        actionGeneration += 1
        presentationExpiryTasks.values.forEach { $0.cancel() }
        presentationExpiryTasks.removeAll()
        observers.removeAll()
        resumeInitialContentWaiters()
    }

    func addObserver(_ observer: AgentV2CoordinatorObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(WeakObserver(observer))
    }

    func removeObserver(_ observer: AgentV2CoordinatorObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
    }

    func loadHints() async {
        guard !isStopped, !isDiscussion else { return }
        let response = try? await client.hints()
        guard !isStopped, !isDiscussion, hints != response else { return }
        hints = response
        notifyObservers()
    }

    func loadDefaultThread() async {
        guard !isStopped else { return }
        do {
            let response = try await client.defaultThread()
            guard !isStopped else { return }
            try bindThread(response.thread)
            refreshProblemReportAvailability()
            await hydrate()
        } catch {
            guard !isStopped else { return }
            log.error("default thread load failed error=\(agentFailureSummary(error), .public)")
            self.errorSource = .failedToLoadChat((error as? ApiAgentV2MutationError)?.code)
            notifyObservers()
        }
    }

    func clearThread() async -> Bool {
        guard !isStopped, let thread, activeRun?.isRunning != true,
              !isDiscussion || hasHydratedMessages else { return false }
        let newsBeforeClear = news
        let generation = runGeneration
        guard let result = try? await client.clearThread(id: thread.id, revision: currentRevision()),
              result.ok,
              let updated = result.value?.thread else { return false }
        guard !isStopped,
              runGeneration == generation,
              (try? bindThread(updated, notify: false)) != nil else { return false }
        newsPreview = newsBeforeClear
        invalidateRunLifecycle(clearsActiveRun: true)
        hydrationGeneration += 1
        invalidateActionPresentations(threadId: thread.id)
        conversation.removeAllMessages()
        loadedOperatorMessageAt = nil
        stoppedAnswers.removeAll()
        unloadedMessageCount = 0
        nextMessageCursor = nil
        hasHydratedMessages = true
        runActivity = nil
        errorSource = nil
        limitRetry = nil
        failedSupportRequest = nil
        scheduleLimitExpiryUpdate()
        onCachedHistoryChange?(thread.id, nil)
        AgentSearchProvider.shared.notifyConversationChanged()
        notifyObservers()
        return true
    }

    /// Sends a report of the thread, or of its message `messageId`, once the thread exists and the server's check has
    /// said it takes reports: at once when both are known, or as soon as they are, while the chat lives
    func reportProblem(messageId: String?, comment: String?) async -> Bool {
        guard let thread = await waitForThread(), await waitForProblemReportAvailability(), !isStopped else { return false }
        do {
            try await client.reportProblem(
                threadId: thread.id,
                report: ApiAgentV2ProblemReport(messageId: messageId, comment: comment)
            )
            return true
        } catch {
            log.error("problem report failed error=\(agentFailureSummary(error), .public)")
            // A server that has switched reports off refuses them, and asking again takes the entry points away
            refreshProblemReportAvailability()
            await problemReportAvailabilityTask?.value
            return false
        }
    }

    /// The thread, once the opening that creates it has; nil when there is none to come, as after a failed opening
    private func waitForThread() async -> ApiAgentV2ThreadSummary? {
        while thread == nil {
            guard !isStopped, startupTask != nil || isOpening && errorSource == nil else { return nil }
            await withCheckedContinuation { threadWaiters.append($0) }
        }
        return isStopped ? nil : thread
    }

    /// Whether the server takes reports, asking it when it hasn't answered yet
    private func waitForProblemReportAvailability() async -> Bool {
        for _ in 0..<3 {
            if let problemReportAvailability { return problemReportAvailability }
            // The check under way, or a new one when that ended without an answer
            if let task = problemReportAvailabilityTask {
                await task.value
                if let problemReportAvailability { return problemReportAvailability }
            }
            guard !isStopped else { return false }
            refreshProblemReportAvailability()
            guard let task = problemReportAvailabilityTask else { return false }
            await task.value
        }
        return problemReportAvailability ?? false
    }

    private func resumeThreadWaiters() {
        let waiters = threadWaiters
        threadWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    /// Sets the rating of the complete answer `messageId`, or withdraws it with `nil`. The rating shows at once, and
    /// only the latest request of the answer settles it. Returns `false` when saving failed and the rating the server
    /// keeps shows again.
    func setFeedback(messageId: String, feedback: ApiAgentV2AnswerFeedback?) async -> Bool {
        guard !isStopped,
              !isShowingCachedMessages,
              let threadId = thread?.id,
              let message = messages.first(where: { $0.id == messageId }),
              message.isStoredAsComplete else { return false }
        let request = FeedbackRequest(feedback: feedback)
        let requests = feedbackRequestsByMessageId[messageId] ?? FeedbackRequests(latest: request, saved: message.feedback)
        requests.latest = request
        feedbackRequestsByMessageId[messageId] = requests
        conversation.setFeedback(id: messageId, feedback: feedback)
        notifyObservers(.messageUpdated(id: messageId))

        let didSave: Bool
        do {
            requests.saved = try await client.setMessageFeedback(
                threadId: threadId,
                messageId: messageId,
                feedback: feedback
            )
            didSave = true
        } catch {
            log.error("answer feedback failed error=\(agentFailureSummary(error), .public)")
            didSave = false
        }
        guard requests.latest === request else { return true }
        feedbackRequestsByMessageId.removeValue(forKey: messageId)
        conversation.setFeedback(id: messageId, feedback: requests.saved)
        notifyObservers(.messageUpdated(id: messageId))
        return didSave
    }

    @discardableResult
    /// With `idleRunGeneration`, loads and applies the history only while the chat stays free in that run generation
    func hydrate(
        preservingLiveActions: Bool = false,
        idleRunGeneration: Int? = nil,
        isFailureSilent: Bool = false
    ) async -> Bool {
        guard !Task.isCancelled, !isStopped, isIdle(inRunGeneration: idleRunGeneration),
              let threadId = thread?.id else { return false }
        hydrationGeneration += 1
        let generation = hydrationGeneration
        let fetchRunGeneration = activeRun?.generation
        let shouldMergeSupportHistory = hasHydratedMessages
            && (isSupportActive || activeRun?.isRunning == true && activeRun?.isSupportAppend == true)
        let fetchLifecycleGeneration = runGeneration
        historyReadCount += 1
        updateSupportPolling()
        var isHistoryReadEnded = false
        // The read ends before the chat hears of its result, so the chat reads a state without it, as the support it
        // offers again once a failed load is retried
        func endHistoryRead() {
            guard !isHistoryReadEnded else { return }
            isHistoryReadEnded = true
            historyReadCount -= 1
            updateSupportPolling()
        }
        defer { endHistoryRead() }
        let isCacheable = canShowCachedHistory
        cacheableHydrationGeneration = isCacheable ? generation : nil
        if isCacheable {
            showCachedMessages(threadId: threadId, generation: generation)
        }
        do {
            var retriesRemaining = 2
            let page: ApiAgentV2ThreadHydration
            while true {
                do {
                    page = try await client.messages(threadId: threadId, cursor: nil, limit: 50)
                    break
                } catch let error as ApiAgentV2MutationError
                    where error.code == .walletContextChanged && retriesRemaining > 0 {
                    endCacheableHydration(generation)
                    guard !Task.isCancelled, !isStopped, hydrationGeneration == generation else { return false }
                    if let initialHostContextTask {
                        _ = await initialHostContextTask.value
                        guard !Task.isCancelled, !isStopped, hydrationGeneration == generation else { return false }
                    }
                    retriesRemaining -= 1
                }
            }
            endCacheableHydration(generation)
            guard !Task.isCancelled, !isStopped, hydrationGeneration == generation else { return false }
            guard !hasHydratedMessages || activeRun?.generation == fetchRunGeneration,
                  isIdle(inRunGeneration: idleRunGeneration) else { return false }
            guard page.thread.id == threadId,
                  page.messages.allSatisfy({ $0.threadId == threadId }) else {
                throw AgentV2NativeContractError.threadBindingMismatch
            }
            if shouldMergeSupportHistory, page.thread.revision < currentRevision() { return false }
            let supportPages = shouldMergeSupportHistory
                ? try await loadLatestSupportPages(firstPage: page, generation: generation, runGeneration: fetchLifecycleGeneration)
                : SupportPages(pages: [page], gapCursor: nil)
            // Pages that don't reach the loaded history take its place, as a first load does
            let isMergingSupportHistory = shouldMergeSupportHistory && supportPages.gapCursor == nil
            guard !Task.isCancelled, !isStopped, hydrationGeneration == generation,
                  !hasHydratedMessages || activeRun?.generation == fetchRunGeneration else { return false }
            invalidateActionPresentations(
                threadId: threadId,
                clearsExistingPresentations: !preservingLiveActions
            )
            let pendingSupportRefresh = needsSupportRefresh
            let closesSupport = thread?.support?.state != .closed && page.thread.support?.state == .closed
            newsPreview = news
            if hasHydratedMessages || page.thread.revision >= currentRevision()
                || thread?.support == nil && page.thread.support == nil {
                try bindThread(page.thread, notify: false)
            }
            needsSupportRefresh = pendingSupportRefresh || closesSupport
            let hydratedMessages = supportPages.pages.reversed().flatMap(\.messages).map(hydratedMessage)
            var shouldFinishOpening = false
            if isOpening, let opening {
                if opening.isQuestion {
                    if openingRunAttempted,
                       let accepted = hydratedMessages.first(where: {
                           $0.role == .user && !openingBaselineMessageIds.contains($0.id)
                       }) {
                        reconcileOpeningInput(localId: opening.inputMessageId, canonicalId: accepted.id)
                        shouldFinishOpening = true
                    }
                } else {
                    shouldFinishOpening = true
                }
            }
            let pending = (isOpening && !shouldFinishOpening ? opening.map { [$0] } ?? [] : []) + queuedOpenings
            let pendingMessages = pending.filter { item in
                !hydratedMessages.contains(where: { $0.id == item.inputMessageId })
            }.map(openingMessage)
            let shouldReplaceMessages = !hydratedMessages.isEmpty || pendingMessages.isEmpty || isShowingCachedMessages
            isShowingCachedMessages = false
            if shouldReplaceMessages {
                dropStoppedSupportInputs()
                if isMergingSupportHistory {
                    conversation.mergeLatestMessages(keepingStoppedAnswers(in: hydratedMessages) + pendingMessages)
                } else {
                    conversation.replaceMessages(
                        keepingStoppedAnswers(in: hydratedMessages) + pendingMessages,
                        preservingLiveActions: preservingLiveActions
                    )
                }
                unloadedMessageCount = max(0, page.thread.messageCount - messages.filter { $0.role != .event }.count)
            }
            loadedOperatorMessageAt = page.thread.support?.lastOperatorMessageAt
            applyPendingFeedback()
            if !isMergingSupportHistory { nextMessageCursor = supportPages.gapCursor ?? page.nextCursor }
            hasHydratedMessages = true
            scheduleLimitExpiryUpdate()
            let isHistoryCacheable = !page.messages.isEmpty && page.thread.news == nil && page.thread.digest == nil
            onCachedHistoryChange?(
                threadId,
                isHistoryCacheable ? AgentCachedHistory(thread: page.thread, messages: page.messages) : nil
            )
            if limitRetry == nil && (!isOpening || shouldFinishOpening) {
                errorSource = nil
            }
            refreshActionPresentations(in: messages, threadId: threadId)
            AgentSearchProvider.shared.notifyConversationChanged()
            endHistoryRead()
            notifyObservers(shouldReplaceMessages && !isMergingSupportHistory ? .messagesHydrated : .reload)
            if shouldFinishOpening {
                openingFinished = true
                notifyObservers()
            }
            startNextOpeningIfPossible()
            return true
        } catch {
            endCacheableHydration(generation)
            guard !Task.isCancelled, !(error is CancellationError),
                  !isStopped, hydrationGeneration == generation else { return false }
            if isFailureSilent { return false }
            endHistoryRead()
            if (error as? ApiAgentV2MutationError)?.code == .threadNotFound {
                if isShowingCachedMessages {
                    isShowingCachedMessages = false
                    conversation.removeAllMessages()
                    notifyObservers()
                }
                WalletCoreData.notify(event: .agentThreadDeleted(threadId: threadId))
                return false
            }
            log.error("thread hydration failed error=\(agentFailureSummary(error), .public)")
            self.errorSource = .failedToLoadChat((error as? ApiAgentV2MutationError)?.code)
            notifyObservers()
            return false
        }
    }

    private var canRefreshSupportHistory: Bool {
        !isStopped && !isDeletingChat && isChatForegroundVisible && hasHydratedMessages
            && thread != nil && activeRun?.isRunning != true && !isLoadingHistory
    }

    private func updateSupportPolling() {
        let shouldPoll = !isStopped && !isDeletingChat && isChatForegroundVisible
            && hasHydratedMessages && isSupportActive
        if shouldPoll, supportPollingTimer == nil {
            let timer = Timer(timeInterval: supportPollingInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isSupportActive else { return }
                    self.needsSupportRefresh = true
                    self.isSupportRefreshDeferred = false
                    self.updateSupportPolling()
                }
            }
            supportPollingTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else if !shouldPoll {
            supportPollingTimer?.invalidate()
            supportPollingTimer = nil
        }
        if !isChatForegroundVisible || isStopped {
            supportRefreshTask?.cancel()
        }
        guard needsSupportRefresh, !isSupportRefreshDeferred, canRefreshSupportHistory, supportRefreshTask == nil,
              !isRefreshingSupportHistory else { return }
        supportRefreshTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.refreshSupportHistory()
            self.supportRefreshTask = nil
            self.updateSupportPolling()
        }
    }

    @discardableResult
    func refreshSupportHistory() async -> Bool {
        guard canRefreshSupportHistory, !isRefreshingSupportHistory,
              isSupportActive || needsSupportRefresh, let threadId = thread?.id else { return false }
        needsSupportRefresh = false
        isSupportRefreshDeferred = false
        isRefreshingSupportHistory = true
        historyReadCount += 1
        hydrationGeneration += 1
        let generation = hydrationGeneration
        let fetchRunGeneration = runGeneration
        updateSupportPolling()
        var hasAppliedHistory = false
        defer {
            historyReadCount -= 1
            isRefreshingSupportHistory = false
            updateSupportPolling()
            // The chat hears of the history once its read has ended, as a support that closed offers its request again
            if hasAppliedHistory { notifyObservers() }
        }
        do {
            let page = try await client.messages(threadId: threadId, cursor: nil, limit: 50)
            let supportPages = try await loadLatestSupportPages(
                firstPage: page,
                generation: generation,
                runGeneration: fetchRunGeneration
            )
            guard !Task.isCancelled, canApplySupportHistory(generation: generation, runGeneration: fetchRunGeneration),
                  isChatForegroundVisible, page.thread.revision >= currentRevision() else {
                if !isChatForegroundVisible { needsSupportRefresh = true }
                return false
            }
            let previousThread = thread
            let previousMessages = messages
            let pendingSupportRefresh = needsSupportRefresh
            let closesSupport = thread?.support?.state != .closed && page.thread.support?.state == .closed
            try bindThread(page.thread, notify: false)
            needsSupportRefresh = pendingSupportRefresh || closesSupport
            let latestMessages = supportPages.pages.reversed().flatMap(\.messages).map(hydratedMessage)
            dropStoppedSupportInputs()
            if let gapCursor = supportPages.gapCursor {
                // The pages don't reach the loaded history: they take its place, and the older pages load from the gap
                conversation.replaceMessages(keepingStoppedAnswers(in: latestMessages))
                nextMessageCursor = gapCursor
            } else {
                conversation.mergeLatestMessages(keepingStoppedAnswers(in: latestMessages))
            }
            unloadedMessageCount = max(0, page.thread.messageCount - messages.filter { $0.role != .event }.count)
            loadedOperatorMessageAt = page.thread.support?.lastOperatorMessageAt
            applyPendingFeedback()
            refreshActionPresentations(in: latestMessages, threadId: threadId)
            scheduleLimitExpiryUpdate()
            if previousThread != thread || previousMessages != messages {
                AgentSearchProvider.shared.notifyConversationChanged()
            }
            hasAppliedHistory = true
            return true
        } catch {
            if Task.isCancelled {
                needsSupportRefresh = true
            } else if thread?.support?.state == .closed {
                isSupportRefreshDeferred = !needsSupportRefresh
                needsSupportRefresh = true
            }
            return false
        }
    }

    /// The newest pages of a support chat, back to the loaded history. When they run out first, `gapCursor` is the
    /// cursor of the older messages between them and the loaded history.
    private struct SupportPages {
        let pages: [ApiAgentV2ThreadHydration]
        let gapCursor: String?
    }

    private func loadLatestSupportPages(
        firstPage: ApiAgentV2ThreadHydration,
        generation: Int,
        runGeneration: Int
    ) async throws -> SupportPages {
        let threadId = firstPage.thread.id
        let knownIds = Set(messages.map(\.id))
        var pages = [firstPage]
        var gapCursor: String?
        while let page = pages.last {
            guard !Task.isCancelled, canApplySupportHistory(generation: generation, runGeneration: runGeneration) else {
                throw CancellationError()
            }
            guard isBoundThread(threadId), page.thread.id == threadId,
                  page.messages.allSatisfy({ $0.threadId == threadId }) else {
                throw AgentV2NativeContractError.threadBindingMismatch
            }
            guard !page.messages.contains(where: { knownIds.contains($0.id) }), let cursor = page.nextCursor else { break }
            guard pages.count < Self.maxSupportHistoryPages else {
                gapCursor = cursor
                break
            }
            pages.append(try await client.messages(threadId: threadId, cursor: cursor, limit: 50))
        }
        return SupportPages(pages: pages, gapCursor: gapCursor)
    }

    private func canApplySupportHistory(generation: Int, runGeneration: Int) -> Bool {
        !isStopped && hydrationGeneration == generation && self.runGeneration == runGeneration
    }

    /// A chat opened on its thread that shows nothing of its own yet. A chat with unread messages opens at the first of
    /// them, which only its history places.
    private var canShowCachedHistory: Bool {
        guard canShowCachedMessages, let thread, !AgentThreadReadState.shared.isUnread(thread) else { return false }
        return !hasHydratedMessages && !isDiscussion && messages.isEmpty && activeRun?.isRunning != true && !hasPendingOpenings
    }

    /// Shows the SDK's copy of the thread's latest messages while the hydration `generation` reads the history, unless
    /// its first request ends first, another hydration starts or the chat gets messages of its own
    private func showCachedMessages(threadId: String, generation: Int) {
        Task { [weak self, client] in
            let cached = await client.cachedMessages(threadId: threadId)
            guard let self, let cached, !self.isStopped,
                  self.cacheableHydrationGeneration == generation,
                  self.thread?.id == threadId,
                  self.showCachedHistory(AgentCachedHistory(thread: cached.thread, messages: cached.messages)) else { return }
            self.resumeInitialContentWaiters()
            self.notifyObservers()
        }
    }

    /// Shows the cached history in place of the thread's history, when the chat may show it
    @discardableResult
    private func showCachedHistory(_ history: AgentCachedHistory) -> Bool {
        guard canShowCachedHistory,
              let threadId = thread?.id,
              history.thread.id == threadId,
              history.thread.news == nil,
              history.thread.digest == nil,
              !history.messages.isEmpty,
              history.messages.allSatisfy({ $0.threadId == threadId }) else { return false }
        conversation.replaceMessages(history.messages.map(hydratedMessage))
        scheduleLimitExpiryUpdate()
        isShowingCachedMessages = true
        hasShownCachedMessages = true
        return true
    }

    /// Live content of the thread takes the place of its cached history, which would otherwise keep it inert
    private func leaveCachedHistory() {
        guard isShowingCachedMessages else { return }
        isShowingCachedMessages = false
        conversation.removeAllMessages()
    }

    /// A history request of the hydration `generation` has ended, and the SDK's copy no longer stands in for it
    private func endCacheableHydration(_ generation: Int) {
        if cacheableHydrationGeneration == generation {
            cacheableHydrationGeneration = nil
        }
    }

    func refreshThreadIfNeeded(_ thread: ApiAgentV2ThreadSummary) {
        if isBoundThread(thread.id), thread.revision >= currentRevision(),
           self.thread?.support != nil || thread.support != nil {
            let hasSupportChanges = self.thread?.support != thread.support
            if hasSupportChanges {
                try? bindThread(thread)
                return
            }
        }
        guard !isStopped, !hasPendingOpenings, isBoundThread(thread.id), activeRun?.isRunning != true,
              thread.revision > currentRevision() else { return }
        Task { [weak self] in
            guard let self, self.activeRun?.isRunning != true else { return }
            await self.hydrate()
        }
    }

    @discardableResult
    func loadOlderMessages() async -> Bool {
        guard !isStopped, !isRefreshingSupportHistory, let threadId = thread?.id, let cursor = nextMessageCursor else { return false }
        historyReadCount += 1
        updateSupportPolling()
        var hasPrependedMessages = false
        defer {
            historyReadCount -= 1
            updateSupportPolling()
            // The chat hears of the older messages once their read has ended
            if hasPrependedMessages { notifyObservers() }
        }
        let generation = hydrationGeneration
        guard let page = try? await client.messages(threadId: threadId, cursor: cursor, limit: 50) else { return false }
        guard !isStopped,
              hydrationGeneration == generation,
              nextMessageCursor == cursor,
              page.thread.id == threadId,
              page.messages.allSatisfy({ $0.threadId == threadId }) else { return false }
        guard (try? bindThread(page.thread, notify: false)) != nil else { return false }
        let hydratedMessages = keepingStoppedAnswers(in: page.messages.map(hydratedMessage), olderThan: messages)
        let previousMessageCount = messages.filter { $0.role != .event }.count
        conversation.prependMessages(hydratedMessages)
        let addedMessageCount = messages.filter { $0.role != .event }.count - previousMessageCount
        unloadedMessageCount = max(0, unloadedMessageCount - addedMessageCount)
        applyPendingFeedback()
        nextMessageCursor = page.nextCursor
        refreshActionPresentations(in: hydratedMessages, threadId: threadId)
        AgentSearchProvider.shared.notifyConversationChanged()
        hasPrependedMessages = true
        return true
    }

    @discardableResult
    func send(
        input: ApiAgentV2RunInput,
        entryPoint: ApiAgentV2EntryPoint? = .agentTab,
        followup: ApiAgentV2RunCommand.FollowUpReference? = nil,
        visibleText: String? = nil,
        localInputMessageId: String? = nil
    ) -> Bool {
        let isSupportRequest = Self.isSupportRequest(entryPoint)
        guard !isStopped,
              let threadId = thread?.id,
              activeRun?.isRunning != true,
              !isDiscussion || hasHydratedMessages,
              isSupportRequest ? !isRateLimitWaiting : !isInputBlockedByLimit else { return false }
        if isSupportActive {
            guard case .append = input, followup == nil else { return false }
        }
        let generation = beginRunLifecycle()
        let replacedStoppedAnswerIds: Set<String>
        switch input {
        case .edit(let targetUserMessageId, _):
            invalidateActionPresentations(threadId: threadId)
            replacedStoppedAnswerIds = findStoppedAnswerIds(from: targetUserMessageId)
        case .regenerate(let targetAssistantMessageId):
            invalidateActionPresentations(threadId: threadId)
            replacedStoppedAnswerIds = findStoppedAnswerIds(from: targetAssistantMessageId)
        case .append:
            replacedStoppedAnswerIds = []
        }
        // A support request leaves the question a limit holds back with its Retry
        if !isSupportRequest {
            limitRetry = nil
            scheduleLimitExpiryUpdate()
        }
        failedSupportRequest = nil
        let optimisticInputMessageId: String?
        if let visibleText, !visibleText.isEmpty {
            let messageId: String
            if case .append = input, let localInputMessageId {
                messageId = localInputMessageId
            } else {
                messageId = "local-\(UUID().uuidString.lowercased())"
            }
            conversation.appendMessage(AgentV2NativeMessage(
                id: messageId,
                threadId: threadId,
                role: .user,
                text: visibleText
            ))
            optimisticInputMessageId = messageId
        } else {
            optimisticInputMessageId = localInputMessageId
        }
        let clientRunId = client.makeClientRunId()
        if isSupportActive, case .append = input {
            supportResendClientRunId = clientRunId
        }
        replacedStoppedAnswers = replacedStoppedAnswerIds.isEmpty ? nil : (clientRunId, replacedStoppedAnswerIds)
        activeRun = RunState(
            generation: generation,
            clientRunId: clientRunId,
            isConfirmed: false,
            runId: nil,
            threadId: threadId,
            localInputMessageId: optimisticInputMessageId,
            isRunning: true,
            isSupportAppend: supportResendClientRunId == clientRunId,
            isSupportRequest: isSupportRequest
        )
        runActivity = nil
        errorSource = nil
        notifyObservers()

        let command = ApiAgentV2RunCommand(
            clientRunId: clientRunId,
            threadId: threadId,
            expectedThreadRevision: currentRevision(),
            input: input,
            entryPoint: entryPoint,
            followupOf: followup
        )
        runTask = Task { [weak self] in
            guard let self else { return }
            let terminalState: ApiAgentV2RunResultState
            let resultClientRunId: String?
            do {
                if self.isDiscussion {
                    if let hostContextTask = self.initialHostContextTask {
                        _ = await hostContextTask.value
                    }
                    guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
                    guard await self.hostContextProvider.start() else {
                        throw AgentV2NativeContractError.retryUnavailable
                    }
                    guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
                }
                guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
                guard !self.isDeletingChat else {
                    self.settleRun(generation: generation, clientRunId: clientRunId, outcome: .cancelled)
                    return
                }
                if let run = self.activeRun, run.isUnsubmittedDiscussionSupportRequest,
                   run.discussionSupportAccountId != self.activeAccountID {
                    self.cancelUnsubmittedDiscussionSupportRequest()
                    return
                }
                self.activeRun?.isUnsubmittedDiscussionSupportRequest = false
                var result = try await self.client.startRun(command)
                guard !Task.isCancelled, self.isCurrentRun(generation), self.isBoundThread(threadId) else { return }
                if self.supportRevisionConflictClientRunId == clientRunId, result.state != .cancelled {
                    self.supportRevisionConflictClientRunId = nil
                    guard self.activeRun?.isRunning == true else { return }
                    let didHydrate = await self.hydrate(preservingLiveActions: true, isFailureSilent: true)
                    guard !Task.isCancelled, self.isCurrentRun(generation), self.isBoundThread(threadId),
                          self.activeRun?.isRunning == true else { return }
                    guard didHydrate else {
                        self.errorSource = .run(.threadRevisionConflict)
                        self.settleRun(generation: generation, clientRunId: clientRunId, outcome: .failed)
                        return
                    }
                    result = try await self.client.startRun(ApiAgentV2RunCommand(
                        clientRunId: clientRunId,
                        threadId: threadId,
                        expectedThreadRevision: self.currentRevision(),
                        input: command.input,
                        entryPoint: command.entryPoint,
                        followupOf: command.followupOf
                    ))
                }
                guard !Task.isCancelled,
                      self.bindRunResult(result, generation: generation, threadId: threadId) else { return }
                self.reconcileRunInput(result)
                terminalState = result.state
                resultClientRunId = result.clientRunId
            } catch {
                guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
                log.error("run start failed error=\(agentFailureSummary(error), .public)")
                let activeClientRunId = self.activeRun?.clientRunId
                if self.replacedStoppedAnswers?.clientRunId == activeClientRunId {
                    self.replacedStoppedAnswers = nil
                }
                if let run = self.activeRun, run.isSupportRequest, self.failedSupportRequest == nil {
                    self.failSupportRequest(run, code: (error as? ApiAgentV2MutationError)?.code)
                }
                self.dropLocalSupportInput()
                if !self.isOpening {
                    await self.hydrate()
                } else {
                    self.errorSource = (error as? ApiAgentV2MutationError).map { .run($0.code) }
                }
                guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
                self.settleRun(
                    generation: generation,
                    clientRunId: activeClientRunId,
                    outcome: .failed
                )
                return
            }
            if !self.isOpening || terminalState == .completed || terminalState == .cancelled {
                if self.isOpening { self.openingFinished = true }
                self.dropLocalSupportInput()
                await self.hydrate(preservingLiveActions: true)
            }
            guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
            self.settleRun(
                generation: generation,
                clientRunId: resultClientRunId,
                outcome: terminalState
            )
        }
        return true
    }

    func bindDiscussionSupportRun(accountId: String?) {
        guard activeRun?.isSupportRequest == true, activeRun?.isConfirmed == false,
              activeRun?.isRunning == true else { return }
        activeRun?.isUnsubmittedDiscussionSupportRequest = true
        activeRun?.discussionSupportAccountId = accountId
    }

    private func cancelUnsubmittedDiscussionSupportRequest() {
        guard let run = activeRun, run.isRunning, run.isUnsubmittedDiscussionSupportRequest else { return }
        if let localId = run.localInputMessageId {
            conversation.removeMessage(id: localId)
        }
        invalidateRunLifecycle(clearsActiveRun: false)
        runActivity = nil
        hostContextProvider.flushDeferredDynamicUpdate()
        notifyObservers(.runTerminated(.cancelled))
        startNextOpeningIfPossible()
    }

    /// The bubble of a message to support that its run left under its local id, before the history merges: the
    /// history has the message under its own id, or never took it, and the merge keeps every message it doesn't have.
    /// A message a limit holds back for Retry keeps its bubble.
    private func dropLocalSupportInput() {
        guard let run = activeRun, let localId = getLocalSupportInputId(of: run) else { return }
        conversation.removeMessage(id: localId)
    }

    /// The bubble of a message to support that `run` left under its local id, unless a limit holds it back for Retry
    private func getLocalSupportInputId(of run: RunState) -> String? {
        guard run.isSupportAppend || isSupportActive, limitRetry?.clientRunId != run.clientRunId,
              let localId = run.localInputMessageId, localId.hasPrefix("local-") else { return nil }
        return localId
    }

    /// The history the chat applies has the stopped messages to support under their own ids, or never took them
    private func dropStoppedSupportInputs() {
        for id in stoppedSupportInputIds {
            conversation.removeMessage(id: id)
        }
        stoppedSupportInputIds.removeAll()
    }

    /// Stops the answer being written. The chat is free at once; the runtime ends the run, cancels it on the server
    /// and reports the saved thread, which brings the saved part of the answer.
    func stopRun() {
        guard !isStopped, let run = activeRun, run.isRunning else { return }
        // The stopped run hears nothing more, so the next history the chat applies settles a message to support it sent
        if let localId = getLocalSupportInputId(of: run) {
            stoppedSupportInputIds.insert(localId)
        }
        invalidateRunLifecycle(clearsActiveRun: false)
        runActivity = nil
        conversation.finalizeStreamingMessages(status: .cancelled)
        conversation.cancelMessages(ids: run.answerMessageIds)
        for message in conversation.messages
        where run.answerMessageIds.contains(message.id) && message.role == .assistant && !message.text.isEmpty {
            stoppedAnswers[message.id] = message
        }
        hostContextProvider.flushDeferredDynamicUpdate()
        if isOpening { openingFinished = true }
        stoppedThreadRevision = currentRevision()
        Task { [client] in await client.stopRun(threadId: run.threadId) }
        AgentSearchProvider.shared.notifyConversationChanged()
        notifyObservers(.runTerminated(.cancelled))
        startNextOpeningIfPossible()
    }

    func retryLimit() {
        guard !isStopped, canRetryLimit, let retry = limitRetry else { return }
        retryRun(clientRunId: retry.clientRunId, threadId: retry.threadId)
    }

    private func retryRun(clientRunId: String, threadId: String) {
        let retry = limitRetry
        let generation = beginRunLifecycle(reusingClientRunId: clientRunId)
        if isOpening { errorSource = nil }
        activeRun = RunState(
            generation: generation,
            clientRunId: clientRunId,
            isConfirmed: true,
            runId: nil,
            threadId: threadId,
            localInputMessageId: isOpening ? openingInputMessageId : retry?.localInputMessageId,
            isRunning: true,
            isSupportAppend: retry?.isSupportAppend == true
        )
        scheduleLimitExpiryUpdate()
        notifyObservers()

        runTask = Task { [weak self] in
            guard let self else { return }
            let terminalState: ApiAgentV2RunResultState
            let resultClientRunId: String?
            do {
                guard let result = try await self.client.retryRun(clientRunId: clientRunId) else {
                    throw AgentV2NativeContractError.retryUnavailable
                }
                guard !Task.isCancelled,
                      self.bindRunResult(result, generation: generation, threadId: threadId) else { return }
                if self.opening != nil, self.activeRun?.localInputMessageId != nil {
                    self.reconcileRunInput(result)
                }
                if result.state == .completed || result.state == .cancelled,
                   self.limitRetry == retry {
                    self.limitRetry = nil
                }
                terminalState = result.state
                resultClientRunId = result.clientRunId
            } catch {
                guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
                log.error("run retry failed error=\(agentFailureSummary(error), .public)")
                let activeClientRunId = self.activeRun?.clientRunId
                if !self.isOpening {
                    await self.hydrate()
                } else {
                    self.errorSource = (error as? ApiAgentV2MutationError).map { .run($0.code) }
                    if let contractError = error as? AgentV2NativeContractError,
                       case .retryUnavailable = contractError {
                        self.activeRun?.isConfirmed = false
                        self.activeRun?.runId = nil
                        if self.limitRetry?.clientRunId == clientRunId {
                            self.limitRetry = nil
                            self.scheduleLimitExpiryUpdate()
                        }
                    }
                }
                guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
                self.settleRun(
                    generation: generation,
                    clientRunId: activeClientRunId,
                    outcome: .failed
                )
                return
            }
            if !self.isOpening || terminalState == .completed || terminalState == .cancelled {
                if self.isOpening { self.openingFinished = true }
                self.dropLocalSupportInput()
                await self.hydrate(preservingLiveActions: true)
            }
            guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
            self.settleRun(
                generation: generation,
                clientRunId: resultClientRunId,
                outcome: terminalState
            )
        }
    }

    func resolveAction(messageId: String, actionId: String) async -> ResolvedAction? {
        guard !isStopped,
              !isShowingCachedMessages,
              hostContextProvider.isAuthorityContextCurrent,
              let accountId = hostContextProvider.publishedActiveAccountId,
              activeAccount()?.id == accountId else { return nil }
        let generation = actionGeneration
        guard let value = try? await client.resolveAction(messageId: messageId, actionId: actionId) else { return nil }
        guard !isStopped,
              hostContextProvider.isAuthorityContextCurrent,
              actionGeneration == generation,
              hostContextProvider.publishedActiveAccountId == accountId,
              activeAccount()?.id == accountId else { return nil }
        return ResolvedAction(value: value, accountId: accountId)
    }

    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .agentV2(let update):
            handle(update)
        case .accountChanged(let accountId, _):
            if activeRun?.discussionSupportAccountId != accountId {
                cancelUnsubmittedDiscussionSupportRequest()
            }
            notifyObservers(.walletSelectionChanged(accountId: accountId))
        case .accountsReset:
            cancelUnsubmittedDiscussionSupportRequest()
            notifyObservers(.walletSelectionChanged(accountId: nil))
        case .applicationDidEnterBackground:
            isInBackground = true
            updateChatActivity()
            updateSupportPolling()
            if thread?.support != nil { notifyObservers() }
        case .applicationWillEnterForeground:
            isInBackground = false
            updateChatActivity()
            if isSupportActive || needsSupportRefresh {
                needsSupportRefresh = true
                isSupportRefreshDeferred = false
            }
            updateSupportPolling()
            if thread?.support != nil { notifyObservers() }
        default:
            break
        }
    }

    private func handle(_ update: ApiAgentV2ClientUpdate) {
        guard !isStopped else { return }
        let change: AgentV2CoordinatorChange
        switch update {
        case .runtimeReady:
            // A new SDK runtime starts with the chat inactive.
            updateChatActivity(resending: true)
            change = .reload
        case .runStarted(let bound, let threadRevision, let inputMessageId):
            guard isBoundThread(bound.threadId),
                  !retiredClientRunIds.contains(bound.clientRunId),
                  !retiredRunIds.contains(bound.runId) else { return }
            leaveCachedHistory()
            runActivity = nil
            let localInputMessageId: String?
            if var run = activeRun,
               run.generation == runGeneration,
               run.isRunning {
                guard run.threadId == bound.threadId,
                      run.clientRunId == bound.clientRunId,
                      run.runId == nil || run.runId == bound.runId else { return }
                run.isConfirmed = true
                run.runId = bound.runId
                run.isRunning = true
                localInputMessageId = run.localInputMessageId
                if let inputMessageId {
                    run.localInputMessageId = inputMessageId
                }
                activeRun = run
            } else {
                let generation = beginRunLifecycle(reusingClientRunId: bound.clientRunId)
                localInputMessageId = nil
                activeRun = RunState(
                    generation: generation,
                    clientRunId: bound.clientRunId,
                    isConfirmed: true,
                    runId: bound.runId,
                    threadId: bound.threadId,
                    localInputMessageId: inputMessageId,
                    isRunning: true
                )
            }
            revision = threadRevision
            if isOpening { openingFinished = true }
            let didReconcileInputMessage = conversation.reconcileOptimisticInputMessage(
                localId: localInputMessageId,
                canonicalId: inputMessageId
            )
            if didReconcileInputMessage, let localInputMessageId, let inputMessageId {
                preserveOpeningMessageDate(localId: localInputMessageId, canonicalId: inputMessageId)
                change = .messageIdReconciled(localId: localInputMessageId, canonicalId: inputMessageId)
            } else {
                change = .reload
            }
        case .messageStarted(let bound, let messageId, let contentKind, let responseLanguage):
            guard acceptPayloadUpdate(bound) else { return }
            ensureRunAnswer(
                threadId: bound.threadId,
                messageId: messageId,
                contentKind: contentKind,
                responseLanguage: responseLanguage
            )
            change = .reload
        case .textDelta(let bound, let messageId, let delta):
            guard acceptPayloadUpdate(bound) else { return }
            runActivity = nil
            ensureRunAnswer(
                threadId: bound.threadId,
                messageId: messageId,
                contentKind: .markdown
            )
            conversation.appendMarkdown(messageId: messageId, delta: delta)
            change = .messageUpdated(id: messageId)
        case .answerTablesChanged(let bound, let messageId, let tables, let references):
            guard acceptPayloadUpdate(bound) else { return }
            conversation.setAnswerTables(id: messageId, tables: tables, references: references)
            change = .messageUpdated(id: messageId)
        case .answerLinkAdded(let bound, let messageId, let link):
            guard acceptPayloadUpdate(bound) else { return }
            // The link arrives before the text that carries its label
            ensureRunAnswer(
                threadId: bound.threadId,
                messageId: messageId,
                contentKind: .markdown
            )
            conversation.addAnswerLink(id: messageId, link: link)
            change = .messageUpdated(id: messageId)
        case .messageContentEnded(let bound, let messageId):
            guard acceptPayloadUpdate(bound) else { return }
            runActivity = nil
            conversation.endMessageContent(id: messageId)
            change = .messageUpdated(id: messageId)
        case .messageCompleted(let bound, let messageId, let finishReason):
            guard acceptPayloadUpdate(bound) else { return }
            runActivity = nil
            conversation.completeMessage(id: messageId, finishReason: finishReason)
            change = .messageUpdated(id: messageId)
        case .actionAvailable(let bound, let messageId, let action):
            guard acceptPayloadUpdate(bound) else { return }
            conversation.upsertAction(
                id: messageId,
                action: AgentV2NativeAction(
                    id: action.id,
                    kind: action.kind,
                    labelCode: action.labelCode,
                    title: action.title,
                    presentation: nil
                )
            )
            refreshActionPresentation(
                threadId: bound.threadId,
                messageId: messageId,
                actionId: action.id
            )
            change = .messageUpdated(id: messageId)
        case .followupsAvailable(let bound, let messageId, let items):
            guard acceptPayloadUpdate(bound) else { return }
            conversation.setFollowups(messageId: messageId, followups: items)
            change = .messageUpdated(id: messageId)
        case .semanticContentAvailable(let bound, let messageId, let content):
            guard acceptPayloadUpdate(bound) else { return }
            runActivity = nil
            ensureRunAnswer(
                threadId: bound.threadId,
                messageId: messageId,
                contentKind: .semantic
            )
            conversation.setSemanticContent(id: messageId, content: content)
            change = .messageUpdated(id: messageId)
        case .toolActivityChanged(let bound, _, _, _, _):
            guard acceptPayloadUpdate(bound) else { return }
            change = .reload
        case .runActivityChanged(let bound, let event):
            guard acceptPayloadUpdate(bound), event.runId == bound.runId else { return }
            runActivity = event
            change = .reload
        case .runFailed(let bound, let clientRunId, let threadId, let messageId, let code, let retryable, let resetAt):
            let target = bound?.threadId ?? threadId
            guard let target, isBoundThread(target) else { return }
            if code == .threadRevisionConflict, bound == nil, messageId == nil,
               supportResendClientRunId == clientRunId,
               let run = activeRun, run.generation == runGeneration, run.isRunning,
               !run.isConfirmed, run.runId == nil,
               run.clientRunId == clientRunId, run.threadId == target {
                supportResendClientRunId = nil
                supportRevisionConflictClientRunId = clientRunId
                return
            }
            guard let disposition = matchRunUpdate(
                    clientRunId: clientRunId,
                    runId: bound?.runId,
                    threadId: target
                  ) else { return }
            let errorSource: ErrorSource = .run(code)
            let supportRequest = activeRun.flatMap { $0.clientRunId == clientRunId && $0.isSupportRequest ? $0 : nil }
            if let supportRequest, bound == nil {
                // The server didn't take the request, which shows with its failure under it
                failSupportRequest(supportRequest, code: code)
            } else {
                terminalErrorSourcesByClientRunId[clientRunId] = errorSource
                // A support request is never held for Retry, nor does it touch the question a limit holds back
                if supportRequest == nil {
                    limitRetry = makeLimitRetry(
                        bound: bound,
                        clientRunId: clientRunId,
                        threadId: target,
                        code: code,
                        retryable: retryable,
                        resetAt: resetAt
                    )
                }
                // A failed answer shows its own error; the status row shows a failure without one and a limit retry.
                if supportRequest != nil || limitRetry == nil,
                   let messageId,
                   conversation.failMessage(id: messageId, error: ApiAgentV2MessageError(
                    code: code,
                    retryable: retryable,
                    resetAt: resetAt.map {
                        Date(timeIntervalSince1970: $0 / 1_000).ISO8601Format(.init(includingFractionalSeconds: true))
                    }
                   )) {
                    failedMessageIdsByClientRunId[clientRunId] = messageId
                } else {
                    self.errorSource = errorSource
                }
            }
            scheduleLimitExpiryUpdate()
            if disposition == .retiredActive {
                change = .reload
                break
            }
            conversation.finalizeStreamingMessages()
            activeRun?.isRunning = false
            runActivity = nil
            retiredClientRunIds.insert(clientRunId)
            if let runId = bound?.runId {
                retiredRunIds.insert(runId)
            }
            hostContextProvider.flushDeferredDynamicUpdate()
            if code == .threadRevisionConflict || code == .runReplayExpired {
                if isOpening {
                    invalidateRunLifecycle(clearsActiveRun: true)
                }
                Task { [weak self] in await self?.hydrate() }
            }
            change = .runTerminated(.failed)
        case .runCancelled(let bound):
            guard isBoundThread(bound.threadId),
                  let disposition = matchRunUpdate(
                    clientRunId: bound.clientRunId,
                    runId: bound.runId,
                    threadId: bound.threadId
                  ) else { return }
            guard disposition != .retiredActive else {
                change = .reload
                break
            }
            conversation.finalizeStreamingMessages()
            activeRun?.isRunning = false
            runActivity = nil
            retiredClientRunIds.insert(bound.clientRunId)
            retiredRunIds.insert(bound.runId)
            hostContextProvider.flushDeferredDynamicUpdate()
            change = .runTerminated(.cancelled)
        case .availabilityChanged(let availability):
            self.availability = availability
            scheduleLimitExpiryUpdate()
            change = .reload
        case .userQuotaChanged(let quota):
            userQuota = quota
            scheduleLimitExpiryUpdate()
            change = .reload
        case .walletAuthorityChanged(let threadId, let preservesActiveRuns):
            guard threadId.map(isBoundThread) ?? true else { return }
            let terminatesRun = threadId == nil && !preservesActiveRuns
            if terminatesRun {
                invalidateRunLifecycle(clearsActiveRun: false)
                runActivity = nil
                conversation.finalizeStreamingMessages(status: .cancelled)
            }
            invalidateAuthorityBoundState(threadId: threadId, isThreadInvalidated: threadId != nil)
            if threadId == nil, hostContextProvider.isAuthorityContextCurrent {
                refreshActionPresentations()
            }
            change = terminatesRun ? .runTerminated(.cancelled) : .reload
        case .walletContextChanged:
            invalidateWalletContextBoundState(threadId: nil)
            refreshActionPresentations()
            change = .reload
        case .threadChanged(let threadId, let thread):
            guard thread.id == threadId, isBoundThread(threadId) else { return }
            try? bindThread(thread, notify: false)
            if let stoppedThreadRevision, thread.revision > stoppedThreadRevision, activeRun?.isRunning != true {
                self.stoppedThreadRevision = nil
                let generation = runGeneration
                Task { [weak self] in await self?.hydrate(preservingLiveActions: true, idleRunGeneration: generation) }
            }
            change = .reload
        }
        notifyObservers(change)
    }

    /// The stopped answers of `messageId` and the messages after it, which an edit or a regeneration of it replaces
    private func findStoppedAnswerIds(from messageId: String) -> Set<String> {
        guard let index = conversation.messages.firstIndex(where: { $0.id == messageId }) else { return [] }
        return Set(conversation.messages[index...].map(\.id).filter { stoppedAnswers[$0] != nil })
    }

    /// The server drops the answers an admitted edit or regeneration replaces, so none of them is kept as it showed
    private func retireReplacedStoppedAnswersIfAdmitted() {
        guard let replaced = replacedStoppedAnswers,
              let run = activeRun,
              run.clientRunId == replaced.clientRunId,
              run.isConfirmed else { return }
        replacedStoppedAnswers = nil
        for messageId in replaced.messageIds {
            stoppedAnswers.removeValue(forKey: messageId)
        }
    }

    /// `hydrated` with each answer the user stopped as it showed, where the server saved less of its text or none of it:
    /// in its own place, or after the question it answered. The server's version replaces it once it has as much.
    /// An older page goes before `newerMessages`: an answer they hold, or whose question they hold, stays out of it.
    private func keepingStoppedAnswers(
        in hydrated: [AgentV2NativeMessage],
        olderThan newerMessages: [AgentV2NativeMessage] = []
    ) -> [AgentV2NativeMessage] {
        guard !stoppedAnswers.isEmpty else { return hydrated }
        var messages = hydrated
        let awaitingAdmissionIds = replacedStoppedAnswers.flatMap { replaced in
            activeRun?.clientRunId == replaced.clientRunId && activeRun?.isRunning == true ? replaced.messageIds : nil
        } ?? []
        for shown in stoppedAnswers.values.sorted(by: { $0.createdAt < $1.createdAt })
        where !awaitingAdmissionIds.contains(shown.id) {
            if let index = messages.firstIndex(where: { $0.id == shown.id }) {
                if messages[index].text.count >= shown.text.count {
                    stoppedAnswers.removeValue(forKey: shown.id)
                } else {
                    messages[index] = shown
                }
            } else if !newerMessages.contains(where: {
                $0.id == shown.id || $0.role == .user && $0.createdAt <= shown.createdAt
            }), let question = messages.lastIndex(where: { $0.role == .user && $0.createdAt <= shown.createdAt }) {
                messages.insert(shown, at: question + 1)
            }
        }
        return messages
    }

    private func hydratedMessage(_ persisted: ApiAgentV2PersistedMessage) -> AgentV2NativeMessage {
        AgentV2NativeMessage(persisted: persisted)
    }

    /// Keeps a rating still being saved over the stored one a history page brings
    private func applyPendingFeedback() {
        for (messageId, requests) in feedbackRequestsByMessageId {
            conversation.setFeedback(id: messageId, feedback: requests.latest.feedback)
        }
    }

    private func handleAuthorityContextInvalidation() {
        guard !isStopped else { return }
        if activeRun?.discussionSupportAccountId != activeAccountID {
            cancelUnsubmittedDiscussionSupportRequest()
        }
        invalidateAuthorityBoundState(threadId: thread?.id, isThreadInvalidated: false)
        notifyObservers()
    }

    /// The questions that wait for the wallet's authority go once it is published again
    private func notifyAuthorityContextPublished() {
        guard !isStopped, hasHydratedMessages else { return }
        notifyObservers()
    }

    /// The question a limit held back stays held while the user stays in its wallet, unless the thread itself was
    /// invalidated
    private func invalidateAuthorityBoundState(threadId: String?, isThreadInvalidated: Bool) {
        invalidateWalletContextBoundState(threadId: threadId)
        if let limitRetry, isThreadInvalidated || limitRetry.accountId != activeAccountID {
            invalidateRunLifecycle(clearsActiveRun: false)
            self.limitRetry = nil
        }
        scheduleLimitExpiryUpdate()
    }

    private func invalidateWalletContextBoundState(threadId: String?) {
        invalidateActionPresentations(threadId: threadId)
    }

    private func invalidateActionPresentations(
        threadId requestedThreadId: String?,
        clearsExistingPresentations: Bool = true
    ) {
        guard requestedThreadId.map(isBoundThread) ?? true else { return }
        actionGeneration += 1
        guard clearsExistingPresentations else { return }
        conversation.clearActionPresentations()
        cancelPresentationExpiryTasks(threadId: requestedThreadId)
    }

    private func refreshActionPresentations() {
        guard !isStopped,
              hostContextProvider.isAuthorityContextCurrent,
              let threadId = thread?.id else { return }
        refreshActionPresentations(in: messages, threadId: threadId)
    }

    private func refreshActionPresentations(
        in messages: [AgentV2NativeMessage],
        threadId: String
    ) {
        guard !isShowingCachedMessages, hostContextProvider.isAuthorityContextCurrent else { return }
        for message in messages where message.threadId == threadId {
            for action in message.actions where action.kind == .send {
                refreshActionPresentation(
                    threadId: threadId,
                    messageId: message.id,
                    actionId: action.id
                )
            }
        }
    }

    private func refreshActionPresentation(
        threadId: String,
        messageId: String,
        actionId: String
    ) {
        guard hostContextProvider.isAuthorityContextCurrent else { return }
        let generation = actionGeneration
        Task { [weak self] in
            guard let self,
                  let presentation = try? await self.client.actionPresentation(
                    messageId: messageId,
                    actionId: actionId
                  ) else { return }
            guard !self.isStopped,
                  self.actionGeneration == generation,
                  self.isBoundThread(threadId) else { return }
            self.conversation.setActionPresentation(
                messageId: messageId,
                actionId: actionId,
                presentation: presentation
            )
            self.schedulePresentationExpiry(
                presentation,
                threadId: threadId,
                messageId: messageId,
                actionId: actionId
            )
            self.notifyObservers(.messageUpdated(id: messageId))
        }
    }

    private static func isSupportRequest(_ entryPoint: ApiAgentV2EntryPoint?) -> Bool {
        guard case .supportRequest? = entryPoint else { return false }
        return true
    }

    /// Keeps the request the server didn't take, as the chat showed it, for its failure to show under it. A question
    /// a limit holds back shows its limit again, with its Retry, which the request's start cleared.
    private func failSupportRequest(_ run: RunState, code: ApiAgentV2ErrorCode?) {
        if let limitRetry, errorSource == nil {
            errorSource = .run(limitRetry.kind == .rateLimit ? .rateLimited : .userQuotaExhausted)
        }
        guard let messageId = run.localInputMessageId,
              let message = messages.first(where: { $0.id == messageId }) else { return }
        failedSupportRequest = FailedSupportRequest(clientRunId: run.clientRunId, message: message, code: code)
    }

    private func makeLimitRetry(
        bound: ApiAgentV2ClientUpdate.Bound?,
        clientRunId: String,
        threadId: String,
        code: ApiAgentV2ErrorCode,
        retryable: Bool,
        resetAt: Double?
    ) -> LimitRetry? {
        guard retryable else { return nil }
        let kind: LimitRetry.Kind
        switch code {
        case .rateLimited:
            kind = .rateLimit
        case .userQuotaExhausted where bound == nil:
            kind = .userQuota
        default:
            return nil
        }
        let run = activeRun?.clientRunId == clientRunId ? activeRun : nil
        let isSupportAppend = run?.isSupportAppend == true
        return LimitRetry(
            kind: kind,
            clientRunId: clientRunId,
            threadId: threadId,
            resetAt: resetAt,
            accountId: activeAccountID,
            isSupportAppend: isSupportAppend,
            localInputMessageId: isSupportAppend ? run?.localInputMessageId : nil
        )
    }

    private func beginRunLifecycle(reusingClientRunId: String? = nil) -> Int {
        runTask?.cancel()
        runTask = nil
        supportResendClientRunId = nil
        supportRevisionConflictClientRunId = nil
        stoppedThreadRevision = nil
        if let runId = activeRun?.runId {
            retiredRunIds.insert(runId)
        }
        for clientRunId in [activeRun?.clientRunId, limitRetry?.clientRunId].compactMap({ $0 })
            where clientRunId != reusingClientRunId {
            retiredClientRunIds.insert(clientRunId)
            terminalErrorSourcesByClientRunId.removeValue(forKey: clientRunId)
            failedMessageIdsByClientRunId.removeValue(forKey: clientRunId)
        }
        runGeneration += 1
        if let reusingClientRunId {
            retiredClientRunIds.remove(reusingClientRunId)
        }
        return runGeneration
    }

    private func invalidateRunLifecycle(clearsActiveRun: Bool) {
        runTask?.cancel()
        runTask = nil
        supportResendClientRunId = nil
        supportRevisionConflictClientRunId = nil
        if let runId = activeRun?.runId {
            retiredRunIds.insert(runId)
        }
        for clientRunId in [activeRun?.clientRunId, limitRetry?.clientRunId].compactMap({ $0 }) {
            retiredClientRunIds.insert(clientRunId)
        }
        terminalErrorSourcesByClientRunId.removeAll()
        failedMessageIdsByClientRunId.removeAll()
        runGeneration += 1
        if clearsActiveRun {
            activeRun = nil
        } else {
            activeRun?.isRunning = false
        }
    }

    private func isIdle(inRunGeneration generation: Int?) -> Bool {
        guard let generation else { return true }
        return runGeneration == generation && activeRun?.isRunning != true
    }

    private func isCurrentRun(_ generation: Int) -> Bool {
        !isStopped && runGeneration == generation && activeRun?.generation == generation
    }

    private func bindRunResult(
        _ result: ApiAgentV2RunResult,
        generation: Int,
        threadId: String
    ) -> Bool {
        guard isCurrentRun(generation), var run = activeRun,
              run.threadId == threadId,
              run.clientRunId == result.clientRunId,
              run.runId == nil || result.runId == nil || run.runId == result.runId else { return false }
        run.isConfirmed = true
        if let runId = result.runId {
            run.runId = runId
        }
        activeRun = run
        return true
    }

    private func reconcileRunInput(_ result: ApiAgentV2RunResult) {
        guard activeRun?.runId != nil else { return }
        let localInputMessageId = activeRun?.localInputMessageId
        if let inputMessageId = result.inputMessageId {
            activeRun?.localInputMessageId = inputMessageId
        }
        if conversation.reconcileOptimisticInputMessage(
            localId: localInputMessageId,
            canonicalId: result.inputMessageId
           ), let localId = localInputMessageId, let canonicalId = result.inputMessageId {
            preserveOpeningMessageDate(localId: localId, canonicalId: canonicalId)
            notifyObservers(.messageIdReconciled(localId: localId, canonicalId: canonicalId))
        }
    }

    private func preserveOpeningMessageDate(localId: String, canonicalId: String) {
        if let date = openingMessageDates[localId] {
            openingMessageDates[canonicalId] = date
        }
        if localId == openingInputMessageId {
            openingCanonicalInputMessageId = canonicalId
        }
    }

    private func reconcileOpeningInput(localId: String, canonicalId: String) {
        preserveOpeningMessageDate(localId: localId, canonicalId: canonicalId)
        if conversation.reconcileOptimisticInputMessage(localId: localId, canonicalId: canonicalId) {
            notifyObservers(.messageIdReconciled(localId: localId, canonicalId: canonicalId))
        }
    }

    private func ensureRunAnswer(
        threadId: String,
        messageId: String,
        contentKind: ApiAgentV2ContentKind,
        responseLanguage: String? = nil
    ) {
        conversation.ensureAssistantMessage(
            threadId: threadId,
            messageId: messageId,
            inputMessageId: activeRun?.localInputMessageId,
            contentKind: contentKind,
            responseLanguage: responseLanguage
        )
        activeRun?.answerMessageIds.insert(messageId)
    }

    private func acceptPayloadUpdate(_ bound: ApiAgentV2ClientUpdate.Bound) -> Bool {
        guard isBoundThread(bound.threadId),
              !retiredClientRunIds.contains(bound.clientRunId),
              !retiredRunIds.contains(bound.runId) else { return false }
        guard var run = activeRun else {
            leaveCachedHistory()
            return true
        }
        guard run.generation == runGeneration,
              run.isRunning,
              run.threadId == bound.threadId,
              run.clientRunId == bound.clientRunId,
              run.runId == nil || run.runId == bound.runId else { return false }
        run.isConfirmed = true
        run.runId = bound.runId
        activeRun = run
        leaveCachedHistory()
        return true
    }

    private func matchRunUpdate(
        clientRunId: String,
        runId: String?,
        threadId: String
    ) -> RunUpdateDisposition? {
        guard var run = activeRun else {
            guard !retiredClientRunIds.contains(clientRunId),
                  runId.map({ !retiredRunIds.contains($0) }) ?? true else { return nil }
            return .standalone
        }
        guard run.threadId == threadId else { return nil }
        if let runId, retiredRunIds.contains(runId) {
            guard !run.isRunning,
                  run.clientRunId == clientRunId,
                  run.runId == runId else { return nil }
            return .retiredActive
        }
        guard run.clientRunId == clientRunId,
              run.runId == nil || runId == nil || run.runId == runId else { return nil }
        if retiredClientRunIds.contains(clientRunId) { return .retiredActive }
        run.isConfirmed = true
        if let runId {
            run.runId = runId
        }
        activeRun = run
        return .active
    }

    private func settleRun(
        generation: Int,
        clientRunId: String?,
        outcome: ApiAgentV2RunResultState
    ) {
        guard isCurrentRun(generation) else { return }
        runTask = nil
        supportResendClientRunId = nil
        supportRevisionConflictClientRunId = nil
        activeRun?.isRunning = false
        hostContextProvider.flushDeferredDynamicUpdate()
        let terminalErrorSource = clientRunId.flatMap {
            terminalErrorSourcesByClientRunId.removeValue(forKey: $0)
        }
        let failedMessageId = clientRunId.flatMap {
            failedMessageIdsByClientRunId.removeValue(forKey: $0)
        }
        // Hydration replaces the failed answer; the status row returns only when the answer no longer shows the error.
        let isShownByFailedMessage = failedMessageId.map { id in
            messages.contains { $0.id == id && $0.error != nil }
        } ?? false
        let isShownBySupportRequest = clientRunId != nil && failedSupportRequest?.clientRunId == clientRunId
        if !isShownByFailedMessage, !isShownBySupportRequest {
            restoreTerminalErrorIfNeeded(outcome: outcome, terminalErrorSource: terminalErrorSource)
        }
        if let clientRunId {
            retiredClientRunIds.insert(clientRunId)
        }
        if let runId = activeRun?.runId {
            retiredRunIds.insert(runId)
        }
        AgentSearchProvider.shared.notifyConversationChanged()
        notifyObservers(.runTerminated(outcome))
        startNextOpeningIfPossible()
    }

    private func restoreTerminalErrorIfNeeded(
        outcome: ApiAgentV2RunResultState,
        terminalErrorSource: ErrorSource?
    ) {
        guard outcome == .failed || outcome == .interrupted else { return }
        if let terminalErrorSource {
            errorSource = terminalErrorSource
        } else if errorSource == nil {
            errorSource = .agentUnavailable
        }
    }

    private func scheduleLimitExpiryUpdate() {
        limitExpiryTask?.cancel()
        let now = Date()
        let messageResetDates = messages.compactMap { message -> Date? in
            guard message.error?.code == .userQuotaExhausted, let resetAt = message.error?.resetAt else { return nil }
            return AgentV2DateParser.date(resetAt)
        }
        let resetDates = ([
            availability.resetAt.map { Date(timeIntervalSince1970: $0 / 1_000) },
            userQuota.map { AgentV2DateParser.date($0.resetAt) },
            limitRetry?.resetAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
        ].compactMap { $0 } + messageResetDates).filter { $0 > now }
        guard let resetDate = resetDates.min() else {
            limitExpiryTask = nil
            return
        }
        let delay = resetDate.timeIntervalSince(now)
        limitExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            guard !Task.isCancelled, let self, !self.isStopped else { return }
            self.limitExpiryTask = nil
            self.notifyObservers()
            self.scheduleLimitExpiryUpdate()
        }
    }

    private func schedulePresentationExpiry(
        _ presentation: ApiAgentV2ActionPresentation,
        threadId: String,
        messageId: String,
        actionId: String
    ) {
        guard presentation.kind == .send,
              presentation.status == .active,
              let expiresAt = presentation.expiresAt else { return }
        let key = presentationKey(threadId: threadId, messageId: messageId, actionId: actionId)
        presentationExpiryTasks[key]?.cancel()
        let delay = max(0, AgentV2DateParser.date(expiresAt).timeIntervalSinceNow)
        presentationExpiryTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            guard !Task.isCancelled, let self else { return }
            guard self.isBoundThread(threadId), self.conversation.expireActionPresentation(
                messageId: messageId,
                actionId: actionId,
                expiresAt: expiresAt
            ) else { return }
            self.presentationExpiryTasks.removeValue(forKey: key)
            self.notifyObservers(.messageUpdated(id: messageId))
        }
    }

    private func cancelPresentationExpiryTasks(threadId: String?) {
        let keys = presentationExpiryTasks.keys.filter { key in
            threadId.map { key.hasPrefix("\($0)\u{0}") } ?? true
        }
        for key in keys {
            presentationExpiryTasks.removeValue(forKey: key)?.cancel()
        }
    }

    private func presentationKey(threadId: String, messageId: String, actionId: String) -> String {
        "\(threadId)\u{0}\(messageId)\u{0}\(actionId)"
    }

    private func currentRevision() -> Int {
        max(revision, thread?.revision ?? 1)
    }

    private func bindThread(_ thread: ApiAgentV2ThreadSummary, notify: Bool = true) throws {
        if let boundThread = self.thread, boundThread.id != thread.id {
            throw AgentV2NativeContractError.threadBindingMismatch
        }
        if self.thread?.support != thread.support,
           self.thread?.support != nil || thread.support != nil {
            needsSupportRefresh = true
            isSupportRefreshDeferred = false
        }
        self.thread = thread
        revision = thread.revision
        if notify { notifyObservers() }
    }

    private func isBoundThread(_ threadId: String) -> Bool {
        thread?.id == threadId
    }

    private func notifyObservers(_ change: AgentV2CoordinatorChange = .reload) {
        if case .runTerminated = change, isSupportActive {
            needsSupportRefresh = true
            isSupportRefreshDeferred = false
        }
        updateSupportPolling()
        // Reports waiting for the thread look again: it is there, or there is none to come
        resumeThreadWaiters()
        guard !isStopped else { return }
        observers = observers.filter { $0.value != nil }
        for observer in observers {
            observer.value?.agentV2CoordinatorDidChange(self, change: change)
        }
    }
}

private enum AgentV2NativeContractError: Error {
    case threadBindingMismatch
    case retryUnavailable
}

/// A failure crossing the JS bridge arrives as an opaque value, and the logger redacts anything it
/// cannot prove safe to print, so an exported log carried only "error=<redacted>" - which is all a
/// chat that refused to open ever said about itself.
///
/// Only fields that are known to be free of content are named, and everything else is reduced to
/// its type. That is deliberate rather than cautious: `SdkError` carries the raw JavaScript
/// exception text and the rejected response payload as associated values, so printing the error
/// itself would put wallet data into a log marked `.public`, which is the one place redaction no
/// longer applies. The bridged domain and code identify which case was thrown without reaching
/// into it, which is what a log needs to tell one failure from another.
private func agentFailureSummary(_ error: Error) -> String {
    if let mutation = error as? ApiAgentV2MutationError {
        return "\(type(of: error)) code=\(mutation.code)"
    }
    let bridged = error as NSError
    return "\(type(of: error)) domain=\(bridged.domain) code=\(bridged.code)"
}
