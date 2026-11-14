import Foundation
import UIComponents
import WalletContext
import WalletCore

@MainActor
final class AgentV2Model: AgentModel {
    private let coordinator: AgentV2Coordinator
    private let v2Backend: AgentV2Backend
    private var didStop = false
    private var presentationCount = 0
    private var activePresentations = Set<ObjectIdentifier>()
    private var hasLeftOpening = false
    var onStop: (() -> Void)?
    var onDiscussionMessageQueued: (() -> Void)?
    private var transferredPresentationModel: AgentV2Model?
    var presentationModel: AgentV2Model { transferredPresentationModel ?? self }
    private var presentationModelChangedHandlers: [ObjectIdentifier: (AgentV2Model) -> Void] = [:]
    var resolveOpeningThreadModel: ((ApiAgentV2ThreadSummary) -> AgentV2Model?)?
    private var rejectedThreadId: String?
    /// The feed's language the news of the discussion was shown in, when it was opened from the feed or a link
    private(set) var newsLocale: String?

    var isReadyForPresentation: Bool {
        !didStop && (coordinator.hasPendingOpenings || coordinator.hasHydratedMessages && coordinator.error == nil)
    }

    var threadId: String? {
        coordinator.thread?.id ?? rejectedThreadId
    }

    var thread: ApiAgentV2ThreadSummary? {
        coordinator.thread
    }

    func refreshThreadIfNeeded(_ thread: ApiAgentV2ThreadSummary) {
        coordinator.refreshThreadIfNeeded(thread)
    }

    var hasMessages: Bool {
        !coordinator.messages.isEmpty || newsPostItemID != nil
    }

    /// A discussion opened without the feed's copy of its post, as from a digest's headline, until the post comes, unless
    /// its opening fails or waits for consent
    var isAwaitingDiscussionPost: Bool {
        !didStop && coordinator.isDiscussion && !hasMessages && coordinator.error == nil && !needsOpeningConsent
    }

    /// The user has written in the chat; a news discussion opened without a question has only the post
    var hasUserMessages: Bool {
        coordinator.messages.contains { $0.role == .user }
    }

    /// Whether the user has written in the chat, by the SDK's rule for its thread: a news discussion with only its post
    /// is not started. A message the user sends there counts at once, before the thread says so.
    var isStarted: Bool {
        !coordinator.isDiscussion || hasUserMessages || hasPendingDiscussionMessage || coordinator.thread?.isStarted == true
    }

    var hasActiveRun: Bool {
        coordinator.activeRun?.isRunning == true
    }

    var hasQueuedQuestions: Bool {
        v2Backend.hasQueuedQuestions
    }

    var hasPendingDiscussionMessage: Bool {
        !didStop && coordinator.isDeferredDiscussion && !coordinator.isWaitingForFirstDiscussionMessage
    }

    /// The last run failed or was interrupted, and the chat shows it
    var isRunFailed: Bool {
        coordinator.isRunFailure && coordinator.error != nil
    }

    /// A limit keeps the chat from sending until it resets
    var isInputBlockedByLimit: Bool {
        coordinator.isInputBlockedByLimit
    }

    /// What Contact Support among the starter hints did
    enum StarterHintSupportRequest: Equatable {
        case requested
        /// The chat support already has, which takes the request instead
        case opened(ApiAgentV2ThreadSummary)
        case dropped
    }

    /// The support sheet's text tells that the operator gets the wallet's addresses
    var hasSupportWalletAddresses: Bool {
        v2Backend.hasSupportWalletAddresses
    }

    /// Sends the support request a new chat opened with from the starter hints, now or once the chat's history has
    /// loaded, as after a failed load and its Retry
    func requestSupportOnceLoaded() {
        v2Backend.requestSupportOnceLoaded()
    }

    @discardableResult
    override func requestSupport(source: ApiAgentV2EntryPoint.SupportRequestSource) -> Bool {
        guard coordinator.isDeferredDiscussion, coordinator.thread == nil else {
            return super.requestSupport(source: source)
        }
        guard source == .header, v2Backend.requestDiscussionSupport() else { return false }
        onDiscussionMessageQueued?()
        return true
    }

    /// Contact Support among the starter hints waits for the server's chats as well
    var canRequestSupportFromHint: Bool {
        canRequestSupport && v2Backend.hasLoadedSupportHintThreads
    }

    /// Contact Support among the starter hints: the chat support has, active last, takes it, or this empty chat asks.
    /// It waits for the server's chats; a list that fails to load drops it, as does a chat that `hasStayedOnScreen`
    /// finds the user has left meanwhile.
    func requestSupportFromStarterHint(hasStayedOnScreen: () -> Bool) async -> StarterHintSupportRequest {
        guard canRequestSupportFromHint else { return .dropped }
        let questionCount = sentQuestionCount
        // A question the user sent meanwhile keeps the chat and drops the request, also once its answer has ended
        guard let threads = await v2Backend.loadSupportThreads(), sentQuestionCount == questionCount,
              canRequestSupportFromHint, hasStayedOnScreen() else { return .dropped }
        if let thread = AgentSupportRequest.findSupportThread(in: threads), thread.id != threadId {
            return .opened(thread)
        }
        return requestSupport(source: .starterHint) ? .requested : .dropped
    }

    var seenMessageCount: Int? {
        v2Backend.seenMessageCount
    }

    /// The chat's first row the user hasn't seen, after the first `seenMessageCount` messages
    func getFirstUnseenItemID(seenMessageCount: Int) -> AgentItemID? {
        v2Backend.getFirstUnseenItemID(seenMessageCount: seenMessageCount)
    }

    var isDeletingChat: Bool { coordinator.isDeletingChat }

    /// The messages are the SDK's copy of the history, shown until it loads
    var isShowingCachedMessages: Bool { coordinator.isShowingCachedMessages }

    /// A question's conversation can be deleted even while its thread is being created
    var canDeleteChat: Bool {
        !didStop && !isDeletingChat
            && (!coordinator.isDeferredDiscussion || coordinator.thread != nil)
            && (coordinator.hasPendingOpenings || coordinator.thread != nil)
    }

    /// Synchronously prevents sending before the screen closes. Server cleanup outlives its presentation.
    @discardableResult
    func beginChatDeletion() -> Bool {
        guard canDeleteChat else { return false }
        holdQueuedQuestions()
        coordinator.beginChatDeletion { [self] isDeleted in
            if isDeleted {
                dropQueuedQuestions()
                stop()
            } else if coordinator.hasPendingOpenings || presentationCount == 0 {
                stop()
            } else {
                releaseQueuedQuestions()
            }
        }
        return true
    }

    func deleteChat() async throws {
        if !isDeletingChat, !beginChatDeletion() { return }
        try await coordinator.waitForChatDeletion()
    }

    func holdQueuedQuestions() {
        v2Backend.holdQueuedQuestions()
    }

    func releaseQueuedQuestions() {
        v2Backend.releaseQueuedQuestions()
    }

    func dropQueuedQuestions() {
        v2Backend.dropQueuedQuestions()
    }

    var hasFailedInitialLoad: Bool {
        !coordinator.hasPendingOpenings && !coordinator.hasHydratedMessages && coordinator.error != nil
    }

    /// The failure of a chat that hasn't loaded, whatever it shows meanwhile
    var initialLoadFailure: String? {
        hasFailedInitialLoad ? coordinator.error : nil
    }

    /// The failure of a chat that has nothing to show, which the chat shows in its middle with Retry
    var initialLoadError: String? {
        hasFailedInitialLoad && !hasMessages ? coordinator.error : nil
    }

    func retryLoad() {
        coordinator.retryLoad()
    }

    var news: ApiAgentV2ThreadNewsCard? {
        coordinator.news
    }

    func updateNewsPreview(_ news: ApiAgentV2NewsFeedItem) {
        coordinator.updateNewsPreview(Self.newsPreview(for: news))
        coordinator.updateDiscussionNaming(news.discussionNaming)
    }

    /// The feed's language a reopened discussion was opened from, which its share link carries
    func updateNewsLocale(_ locale: String) {
        newsLocale = locale
    }

    func updateDigestPreview(_ digest: ApiAgentV2ThreadDigestCard) {
        coordinator.updateDigestPreview(digest)
    }

    func updateDigestPreview(_ digest: ApiAgentV2NewsFeedDigest) {
        coordinator.updateDigestPreview(Self.digestPreview(for: digest))
        coordinator.updateDiscussionNaming(digest.discussionNaming)
    }

    var isOpening: Bool { coordinator.hasPendingOpenings }
    var openingInputItemID: AgentItemID? {
        guard let nativeID = coordinator.presentationOpeningInputMessageId else { return nil }
        return v2Backend.itemID(nativeID: nativeID)
    }
    var needsOpeningConsent: Bool { coordinator.needsOpeningConsent }
    var isAcceptingOpeningConsent: Bool { coordinator.isAcceptingOpeningConsent }
    /// A news discussion opened before consent asks for it at its first message, suggestion or recording
    var needsConsentToSend: Bool { coordinator.needsConsentToSend }
    var isConsentToSendUnknown: Bool { coordinator.isConsentToSendUnknown }

    func acceptOpeningConsent() { coordinator.acceptOpeningConsent() }
    func confirmOpeningConsent() { coordinator.confirmOpeningConsent() }

    func loadConsent() async throws -> Bool {
        try await coordinator.loadConsent()
    }

    func acceptConsent() async throws {
        try await coordinator.acceptConsent()
    }

    func markConsentGiven() {
        coordinator.markConsentGiven()
    }

    func cancelOpeningIfNeeded() {
        guard isOpening, threadId == nil, !isDeletingChat, activePresentations.isEmpty else { return }
        hasLeftOpening = true
        if !coordinator.isCreatingDiscussionThread { stop() }
    }

    var newsPostItemID: AgentItemID? { v2Backend.newsPostItemID }

    func newsPost(for message: AgentMessage) -> ApiAgentV2ThreadNewsCard? {
        message.id == newsPostItemID ? news : nil
    }

    /// What the post at the top of a news or digest discussion shows, for its message
    func newsPostContent(for message: AgentMessage) -> AgentNewsPostView.Content? {
        message.id == newsPostItemID ? newsPostContent : nil
    }

    /// What the post at the top of a news or digest discussion shows
    var newsPostContent: AgentNewsPostView.Content? {
        guard newsPostItemID != nil else { return nil }
        return news.map(AgentNewsPostView.Content.init(news:)) ?? coordinator.digest.map(AgentNewsPostView.Content.init(digest:))
    }

    /// A discussion that waits for its thread takes the feed's name for it, otherwise the title of its post
    override var chatTitleText: String {
        if coordinator.isDeferredDiscussion {
            if let naming = coordinator.discussionNaming { return naming.title }
            if coordinator.digest != nil { return lang("$agent_digest_title") }
        }
        return Self.chatTitleText(
            thread: coordinator.thread,
            firstUserMessage: coordinator.news?.headline ?? coordinator.messages.first(where: { $0.role == .user })?.text
        )
    }

    override var chatIcon: String? {
        coordinator.isDeferredDiscussion ? coordinator.discussionNaming?.icon : Self.chatIcon(thread: coordinator.thread)
    }

    static func chatTitleText(thread: ApiAgentV2ThreadSummary?, firstUserMessage: String? = nil) -> String {
        let title = thread?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstMessage = firstUserMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title! : firstMessage?.isEmpty == false ? firstMessage! : lang("New Chat")
    }

    static func chatIcon(thread: ApiAgentV2ThreadSummary?) -> String? {
        let icon = thread?.icon?.trimmingCharacters(in: .whitespacesAndNewlines)
        return icon?.isEmpty == false ? icon : nil
    }

    static func chatTitle(thread: ApiAgentV2ThreadSummary?, firstUserMessage: String? = nil) -> String {
        let text = chatTitleText(thread: thread, firstUserMessage: firstUserMessage)
        return chatIcon(thread: thread).map { "\($0) \(text)" } ?? text
    }

    func setPresentationActive(_ isActive: Bool, owner: ObjectIdentifier) {
        guard !didStop else { return }
        if isActive {
            hasLeftOpening = false
            activePresentations.insert(owner)
        } else {
            activePresentations.remove(owner)
        }
        self.isActive = !activePresentations.isEmpty
    }

    func setPresentationModelChangedHandler(_ handler: ((AgentV2Model) -> Void)?, owner: ObjectIdentifier) {
        presentationModelChangedHandlers[owner] = handler
    }

    func retainPresentation() {
        presentationCount += 1
    }

    func releasePresentation() {
        guard presentationCount > 0 else { return }
        presentationCount -= 1
        if presentationCount == 0 && !isDeletingChat {
            stop()
        }
    }

    /// The thread's latest history loaded, or `nil` once the thread has none to show
    var onCachedHistoryChange: ((String, AgentCachedHistory?) -> Void)? {
        get { coordinator.onCachedHistoryChange }
        set { coordinator.onCachedHistoryChange = newValue }
    }

    /// With `cachedHistory`, a chat that may show the cached history shows it from the start. With `isSummaryCached`,
    /// the thread's summary is the SDK's copy, whose unread state is unknown, and the chat shows no cached history.
    /// `activeAccount` is the wallet the user is in, which a question that waits is asked for.
    init(
        client: AgentV2Client,
        thread: ApiAgentV2ThreadSummary? = nil,
        digest: ApiAgentV2ThreadDigestCard? = nil,
        cachedHistory: AgentCachedHistory? = nil,
        isSummaryCached: Bool = false,
        supportPollingInterval: TimeInterval = AgentV2Coordinator.defaultSupportPollingInterval,
        activeAccount: @escaping @MainActor () -> MAccount? = { AccountStore.account }
    ) {
        let coordinator = AgentV2Coordinator(
            client: client,
            thread: thread,
            digest: digest,
            cachedHistory: cachedHistory,
            isSummaryCached: isSummaryCached,
            supportPollingInterval: supportPollingInterval,
            activeAccount: activeAccount
        )
        self.coordinator = coordinator
        v2Backend = AgentV2Backend(coordinator: coordinator)
        super.init(backend: v2Backend)
        // The base model starts with an empty timeline, which the preview or cached history then fills
        if digest != nil || coordinator.isShowingCachedMessages {
            v2Backend.refreshPresentation()
        }
        coordinator.start()
    }

    init(
        client: AgentV2Client,
        thread: ApiAgentV2ThreadSummary? = nil,
        news: ApiAgentV2NewsFeedItem,
        locale: String,
        activeAccount: @escaping @MainActor () -> MAccount? = { AccountStore.account },
        onThreadCreated: @escaping (ApiAgentV2ThreadSummary) -> Void
    ) {
        let coordinator = AgentV2Coordinator(
            client: client,
            thread: thread,
            news: Self.newsPreview(for: news),
            newsRequest: thread == nil ? .init(eventId: news.eventId, locale: locale) : nil,
            shouldDeferThread: thread == nil && news.discussion == nil,
            discussionNaming: news.discussionNaming,
            activeAccount: activeAccount
        )
        self.coordinator = coordinator
        v2Backend = AgentV2Backend(coordinator: coordinator)
        newsLocale = locale
        super.init(backend: v2Backend)
        v2Backend.refreshPresentation()
        startOpening(onThreadCreated: onThreadCreated)
    }

    init(
        client: AgentV2Client,
        newsRequest: ApiAgentV2ThreadNewsRequest? = nil,
        digestRequest: ApiAgentV2ThreadDigestRequest? = nil,
        onThreadCreated: @escaping (ApiAgentV2ThreadSummary) -> Void
    ) {
        let coordinator = AgentV2Coordinator(client: client, newsRequest: newsRequest, digestRequest: digestRequest)
        self.coordinator = coordinator
        v2Backend = AgentV2Backend(coordinator: coordinator)
        newsLocale = newsRequest?.locale
        super.init(backend: v2Backend)
        startOpening(onThreadCreated: onThreadCreated)
    }

    /// A digest's discussion opened from the feed's copy of the digest, which is its post at once, so its card lands on it
    init(
        client: AgentV2Client,
        digest: ApiAgentV2NewsFeedDigest,
        activeAccount: @escaping @MainActor () -> MAccount? = { AccountStore.account },
        onThreadCreated: @escaping (ApiAgentV2ThreadSummary) -> Void
    ) {
        let coordinator = AgentV2Coordinator(
            client: client,
            shouldDeferThread: digest.discussion == nil,
            discussionNaming: digest.discussionNaming,
            digestRequest: .init(id: digest.id),
            digest: Self.digestPreview(for: digest),
            activeAccount: activeAccount
        )
        self.coordinator = coordinator
        v2Backend = AgentV2Backend(coordinator: coordinator)
        super.init(backend: v2Backend)
        v2Backend.refreshPresentation()
        startOpening(onThreadCreated: onThreadCreated)
    }

    nonisolated static func digestPreview(for digest: ApiAgentV2NewsFeedDigest) -> ApiAgentV2ThreadDigestCard {
        ApiAgentV2ThreadDigestCard(id: digest.id, windowEnd: digest.deliveredAt, total: digest.total, top: digest.top)
    }

    private static func newsPreview(for news: ApiAgentV2NewsFeedItem) -> ApiAgentV2ThreadNewsCard {
        ApiAgentV2ThreadNewsCard(
            eventId: news.eventId,
            headline: news.headline,
            excerpt: AgentMessageTextRenderer.makeAttributedText(
                news.body,
                textColor: .label,
                rendersMarkdown: true,
                detectsLinks: false
            ).string,
            imageUrl: news.imageUrl,
            publishedAt: news.deliveredAt,
            source: news.sources.first?.name,
            body: news.body,
            sources: news.sources
        )
    }

    init(
        client: AgentV2Client,
        question: String,
        entryPoint: ApiAgentV2EntryPoint? = nil,
        onThreadCreated: @escaping (ApiAgentV2ThreadSummary) -> Void = { _ in }
    ) {
        let coordinator = AgentV2Coordinator(client: client, question: question, entryPoint: entryPoint)
        self.coordinator = coordinator
        v2Backend = AgentV2Backend(coordinator: coordinator)
        super.init(backend: v2Backend)
        startOpening(onThreadCreated: onThreadCreated)
    }

    private func startOpening(onThreadCreated: @escaping (ApiAgentV2ThreadSummary) -> Void) {
        coordinator.resolveOpeningThread = { [weak self] thread in
            guard let self else { return false }
            let existing = self.resolveOpeningThreadModel?(thread)
            guard !self.didStop else { return false }
            if let existing, existing !== self {
                self.redirectOpening(to: existing)
                return false
            }
            return true
        }
        coordinator.onOpeningThreadCreated = onThreadCreated
        coordinator.onOpeningFinished = { [weak self] in
            guard let self, self.hasLeftOpening, self.threadId == nil else { return }
            self.stop()
        }
        coordinator.start()
    }

    func rejectDeletedThread(id: String) {
        rejectedThreadId = id
        stop()
        WalletCoreData.notify(event: .agentThreadDeleted(threadId: id))
    }

    func redirectOpening(to existing: AgentV2Model) {
        coordinator.transferOpening(to: existing.coordinator)
        if coordinator.isDeferredDiscussion {
            v2Backend.transferQueuedQuestions(to: existing.v2Backend)
        }
        transferredPresentationModel = existing
        for handler in Array(presentationModelChangedHandlers.values) {
            handler(existing)
        }
        stop()
    }

    func waitForInitialLoad() async {
        await coordinator.waitForInitialLoad()
    }

    /// Waits for the initial timeline, or for the SDK's copy of it that shows while it loads
    func waitForInitialContent() async {
        await coordinator.waitForInitialContent()
    }

    override func stop() {
        guard !didStop else { return }
        didStop = true
        super.stop()
        onStop?()
        onStop = nil
    }

    override func send(text: String?, editingMessageID: AgentItemID? = nil, source: AgentBackendSendSource = .composer) {
        guard !didStop, editingMessageID == nil || editingMessageID != newsPostItemID,
              !coordinator.isDeferredDiscussion || v2Backend.canAcceptMessages else { return }
        if coordinator.isSupportActive {
            if editingMessageID != nil { return }
            if case .followup = source { return }
        }
        super.send(text: text, editingMessageID: editingMessageID, source: source)
        if hasPendingDiscussionMessage { onDiscussionMessageQueued?() }
    }
}

@MainActor
private final class AgentV2Backend: AgentBackend, AgentV2CoordinatorObserver {
    private struct PresentedMessage {
        let key: String
        let message: AgentMessage
        let replacedItemID: AgentItemID?
    }

    private enum Interaction {
        case action(messageID: String, action: AgentV2NativeAction)
        case followup(messageID: String, followup: ApiAgentV2FollowUp)
        case discussionFollowup(text: String)
        case retryLimit
        case retryOpening
        case retryLoad
        case retryFailedQuestions
    }

    /// A question can go now, and suggestions, edits and regeneration can: nothing is answered or waiting
    var canSendMessages: Bool {
        canSendNow && queuedQuestions.isEmpty
    }

    var hasQueuedQuestions: Bool {
        !queuedQuestions.isEmpty
    }

    private var canSendNow: Bool {
        isTimelineReady
            && (!coordinator.hasPendingOpenings || coordinator.isWaitingForFirstDiscussionMessage)
            && coordinator.activeRun?.isRunning != true
            && !coordinator.isAwaitingDiscussionStatus
            && !coordinator.isInputBlockedByLimit
            && !coordinator.isDeletingChat
            && queuedQuestionHoldCount == 0
            && !isClearing
            && !isLoadingOlderMessages
    }

    /// A question sent while an answer is written waits in the chat for it, after any already waiting, as Android
    /// queues it; nothing goes or waits while a limit holds
    var canAcceptMessages: Bool {
        canSendMessages || isTimelineReady
            && coordinator.thread != nil
            && !coordinator.hasPendingOpenings
            && (coordinator.activeRun?.isRunning == true || !queuedQuestions.isEmpty)
            && !coordinator.isInputBlockedByLimit
            && !coordinator.isDeletingChat
            && !isClearing
    }

    var queuesNextQuestion: Bool {
        coordinator.isWaitingForFirstDiscussionMessage && canSendMessages || !canSendMessages && canAcceptMessages
    }

    var trailingItemIDs: [AgentItemID] {
        let failedIDs = trailingFailedQuestions.map { group in group.questions.map(\.userMessageID) + [group.failureID] }
        return (failedIDs ?? []) + queuedQuestions.map(\.userMessageID)
    }

    var canStopAnswer: Bool {
        !didStop && coordinator.activeRun?.isRunning == true
    }

    var seenMessageCount: Int? {
        messageReplacement.seenMessageCount(coordinator.seenMessageCount, messages: coordinator.messages)
    }

    func getFirstUnseenItemID(seenMessageCount: Int) -> AgentItemID? {
        coordinator.getFirstUnseenMessageID(
            seenMessageCount: seenMessageCount,
            ignoredIDs: messageReplacement.ignoredNativeIDs
        ).flatMap(itemID(nativeID:))
    }

    /// Clearing also cancels the answer being written, and drops the questions that wait for it
    var canClearConversation: Bool {
        isTimelineReady
            && !coordinator.hasPendingOpenings
            && coordinator.thread != nil
            && !isClearing
            && !isLoadingOlderMessages
    }

    var shouldConfirmConversationClear: Bool {
        true
    }

    /// Reports wait for the thread and the server's check, and a deferred discussion offers them once its thread exists
    var canReportProblem: Bool {
        !didStop
            && coordinator.hasConsent
            && coordinator.isProblemReportAvailable
            && (!coordinator.isDeferredDiscussion || coordinator.thread != nil)
            && (coordinator.thread != nil || coordinator.isOpening)
            && !isClearing
    }

    /// Contact Support shows in a chat the host lets an operator answer, unless support already has it
    var isSupportRequestVisible: Bool {
        !didStop
            && AgentV2HostContextProvider.supportsSupportHandoff
            && !coordinator.isSupportActive
    }

    /// A support request goes once the chat's history has loaded and nothing runs, waits or clears in it. Only a rate
    /// limit holds it back: the server takes it beyond the daily quota and capacity.
    var canRequestSupport: Bool {
        let isWaitingForFirstDiscussionMessage = coordinator.isWaitingForFirstDiscussionMessage
        return isSupportRequestVisible
            && coordinator.hasConsent
            && (coordinator.thread != nil && coordinator.hasHydratedMessages
                || isWaitingForFirstDiscussionMessage && coordinator.hasLoadedDiscussionStatus)
            && !coordinator.isShowingCachedMessages
            && !coordinator.isLoadingHistory
            && (!coordinator.hasPendingOpenings || isWaitingForFirstDiscussionMessage)
            && !isDiscussionSupportRequestPending
            && coordinator.activeRun?.isRunning != true
            && !coordinator.isRateLimitWaiting
            && !coordinator.isDeletingChat
            && queuedQuestions.isEmpty
            && queuedQuestionHoldCount == 0
            && !isClearing
            && !isLoadingOlderMessages
    }

    func requestDiscussionSupport() -> Bool {
        guard coordinator.isWaitingForFirstDiscussionMessage, canRequestSupport else { return false }
        discussionSupportAccountId = coordinator.activeAccountID
        isDiscussionSupportRequestPending = true
        coordinator.requestDiscussionThreadCreation(isSupportRequest: true)
        notifyStateChanged()
        return true
    }

    private func sendPendingDiscussionSupportRequestIfPossible() {
        guard isDiscussionSupportRequestPending else { return }
        let hasHydratedMessages = coordinator.hasHydratedMessages
        guard !didStop, !coordinator.isDeletingChat,
              discussionSupportAccountId == coordinator.activeAccountID,
              coordinator.error == nil || hasHydratedMessages && !coordinator.isLoadFailure else {
            isDiscussionSupportRequestPending = false
            discussionSupportAccountId = nil
            return
        }
        guard hasHydratedMessages, !coordinator.isLoadingHistory, !coordinator.isAwaitingAuthorityContext else { return }
        if coordinator.hasPendingOpenings, coordinator.isDiscussionSupportRequest { return }
        let accountId = discussionSupportAccountId
        isDiscussionSupportRequestPending = false
        discussionSupportAccountId = nil
        guard canRequestSupport, let context else { return }
        context.sendMessage(lang("$agent_support_request_message"), source: .supportRequest(.header))
        coordinator.bindDiscussionSupportRun(accountId: accountId)
    }

    /// The operator gets the wallet's addresses with the chat once the user has allowed the Agent and has a wallet
    var hasSupportWalletAddresses: Bool {
        coordinator.hasConsent && coordinator.activeAccountID != nil
    }

    /// The server's chats, fresh, for Contact Support to choose from; nil when they fail to load
    func loadSupportThreads() async -> [ApiAgentV2ThreadSummary]? {
        guard let response = try? await coordinator.client.listThreads(
            cursor: nil,
            limit: AgentSupportRequest.threadPageSize,
            query: nil
        ), !didStop else { return nil }
        return response.threads.map(\.thread)
    }

    func requestSupportOnceLoaded() {
        isSupportRequestPending = true
        sendPendingSupportRequestIfPossible()
    }

    private func sendPendingSupportRequestIfPossible() {
        guard isSupportRequestPending else { return }
        // A chat support already has takes no request
        guard isSupportRequestVisible else {
            isSupportRequestPending = false
            return
        }
        guard canRequestSupport, let context else { return }
        isSupportRequestPending = false
        context.sendMessage(lang("$agent_support_request_message"), source: .supportRequest(.starterHint))
    }

    private func loadSupportHintThreadsIfNeeded() {
        guard !hasLoadedSupportHintThreads, !hasSupportHintThreadsFailed, supportHintThreadsTask == nil else { return }
        supportHintThreadsTask = Task { [weak self] in
            guard let self else { return }
            let threads = await loadSupportThreads()
            supportHintThreadsTask = nil
            guard threads != nil else {
                hasSupportHintThreadsFailed = true
                return
            }
            hasLoadedSupportHintThreads = true
            notifyStateChanged()
        }
    }

    var typingIndicatorAccessibilityLabel: String? {
        if coordinator.showsOpeningTypingIndicator { return lang("$agent_activity_analyzing_request") }
        if let runActivity = coordinator.runActivity {
            return AgentV2Copy.runActivity(runActivity)
        }
        return coordinator.activeRun?.isRunning == true ? lang("$agent_chat_running") : nil
    }

    var typingIndicatorStatusText: String? {
        coordinator.runActivity.map(AgentV2Copy.runActivity) ?? lang("$agent_activity_analyzing_request")
    }

    var accessibilityStatus: String? {
        guard let activeRun = coordinator.activeRun else { return nil }
        return activeRun.isRunning ? lang("$agent_chat_running") : lang("Agent")
    }

    var supportState: AgentSupportState {
        coordinator.supportState
    }

    private weak var context: AgentBackendContext?
    private let coordinator: AgentV2Coordinator
    private let actionExecutor: AgentV2ActionExecutor
    private var uiIDByNativeID: [String: AgentItemID] = [:]
    private var nativeIDByUIID: [AgentItemID: String] = [:]
    /// An operator has joined the chat, so its answers name their authors
    private var shouldShowAuthors = false
    private var presentedKeys: [String] = []
    private var interactionsByMessageID: [AgentItemID: [String: Interaction]] = [:]
    private var messageReplacement = AgentV2MessageReplacement()
    private var pendingTypingIndicatorID: AgentItemID?
    private var statusMessageID: AgentItemID?
    private var failureCaptionIDByNativeID: [String: AgentItemID] = [:]
    private var lastHints: [AgentHint] = []
    /// The server's chats have loaded for the starter hint's Contact Support, which waits for them
    private(set) var hasLoadedSupportHintThreads = false
    private var supportHintThreadsTask: Task<Void, Never>?
    /// A load of them failed, which the chat tries again as it shows
    private var hasSupportHintThreadsFailed = false
    /// The support request a new chat opened with, which waits until the chat can send it
    private var isSupportRequestPending = false
    private var isDiscussionSupportRequestPending = false
    private var discussionSupportAccountId: String?
    private var hintsAnimated = false
    private var didPresentInitialTimeline = false
    private var isClearing = false
    private(set) var isLoadingOlderMessages = false
    private var didStop = false
    private var lastSettledRunGeneration: Int?
    private var presentedNews: ApiAgentV2ThreadNewsCard?
    private var presentedDigest: ApiAgentV2ThreadDigestCard?
    private let postItemID = AgentItemID()
    private var postTimestamp: Date?
    private(set) var newsPostItemID: AgentItemID?
    /// Questions sent while an answer is written: each shows at once as the user's bubble at the chat's end, below the
    /// answer, and goes once nothing else is answered, first in, first out
    private var queuedQuestions: [QueuedQuestion] = []
    private var queuedQuestionHoldCount = 0
    /// Questions a wallet switch failed, as failed sends: last in the chat, before the questions that wait, until a
    /// later question goes, and from then on where they stand
    private var failedQuestionGroups: [FailedQuestionGroup] = []
    /// The run a stop started for a waiting question
    private var stopStartedRunGeneration: Int?
    /// The question a limit held back that the queue sent again once the limit reset, before the questions behind it
    private var queueRetriedLimit: AgentV2Coordinator.LimitRetry?

    private struct QueuedQuestion {
        let text: String
        let userMessageID: AgentItemID
        let nativeID: String
        let source: AgentBackendSendSource
        let timestamp: Date
        /// The wallet the question is asked for
        var accountID: String?
    }

    private struct FailedQuestionGroup {
        let questions: [QueuedQuestion]
        /// The failure after them
        let failureID: AgentItemID
        /// The message they follow once a later question went; nil while they stay last, where Retry asks them again,
        /// as on Android
        var anchorNativeID: String?
    }

    init(coordinator: AgentV2Coordinator) {
        self.coordinator = coordinator
        actionExecutor = AgentV2ActionExecutor(coordinator: coordinator)
    }

    func attach(to context: AgentBackendContext) {
        self.context = context
        coordinator.addObserver(self)
        synchronizeHints(force: true)
        synchronizeMessages()
        notifyStateChanged()
    }

    func detach() {
        coordinator.removeObserver(self)
        context = nil
    }

    func loadHints(animated: Bool) {
        hintsAnimated = animated
        synchronizeHints(force: true)
        guard coordinator.hasHydratedMessages, !coordinator.isDiscussion,
              coordinator.hints == nil, !coordinator.hasPendingOpenings else { return }
        Task { [weak self] in
            await self?.coordinator.loadHints()
        }
    }

    func prepareForEditing(_ editContext: AgentBackendEditContext) {
        guard !coordinator.isSupportActive, let nativeID = nativeIDByUIID[editContext.messageID] else { return }
        messageReplacement.beginEditing(targetNativeID: nativeID, messages: coordinator.messages)
    }

    func didSendUserMessage(
        _ text: String,
        userMessageID: AgentItemID,
        source: AgentBackendSendSource,
        editContext: AgentBackendEditContext?
    ) {
        if case .supportRequest = source {
            guard editContext == nil, canRequestSupport, let context else { return }
            startRun(text: text, userMessageID: userMessageID, source: source, editContext: nil, in: context)
            return
        }
        let shouldCreateDiscussionThread = coordinator.isWaitingForFirstDiscussionMessage && canSendMessages
        if editContext == nil, queuesNextQuestion {
            let nativeID = "local-ios-\(userMessageID.uuidString.lowercased())"
            bind(nativeID: nativeID, to: userMessageID)
            queuedQuestions.append(QueuedQuestion(
                text: text,
                userMessageID: userMessageID,
                nativeID: nativeID,
                source: source,
                timestamp: context?.message(for: userMessageID)?.timestamp ?? Date(),
                accountID: coordinator.activeAccountID
            ))
            if shouldCreateDiscussionThread { coordinator.requestDiscussionThreadCreation() }
            synchronizeMessages()
            notifyStateChanged()
            return
        }
        guard canSendMessages, let context else { return }
        startRun(text: text, userMessageID: userMessageID, source: source, editContext: editContext, in: context)
    }

    private func startRun(
        text: String,
        userMessageID: AgentItemID,
        source: AgentBackendSendSource,
        editContext: AgentBackendEditContext?,
        in context: AgentBackendContext
    ) {
        let input: ApiAgentV2RunInput
        let localInputMessageID: String?
        if let editContext {
            guard let targetID = nativeIDByUIID[editContext.messageID] else {
                Task { [weak self] in await self?.coordinator.hydrate() }
                AppActions.showError(error: DisplayError(text: lang("Agent is unavailable")))
                return
            }
            removeFailedQuestions(from: targetID)
            messageReplacement.sendEdit(targetNativeID: targetID, text: text)
            input = .edit(targetUserMessageId: targetID, text: text)
            localInputMessageID = targetID
        } else {
            anchorFailedQuestions()
            let optimisticID = "local-ios-\(userMessageID.uuidString.lowercased())"
            bind(nativeID: optimisticID, to: userMessageID)
            input = .append(text: text)
            localInputMessageID = optimisticID
        }

        var entryPoint: ApiAgentV2EntryPoint?
        var followup: ApiAgentV2RunCommand.FollowUpReference?

        if editContext == nil {
            switch source {
            case .composer:
                entryPoint = !coordinator.isDiscussion ? .agentTab : nil
            case .hint(let id, let catalogVersion):
                entryPoint = !coordinator.isDiscussion ? .emptyState(hintId: id, catalogVersion: catalogVersion) : nil
            case .supportRequest(let supportSource):
                entryPoint = .supportRequest(source: supportSource)
            case .followup(let messageID, let followupID):
                if messageID == newsPostPresentationKey {
                    if let post = coordinator.messages.first(where: \.newsPost),
                       let saved = post.followups.first(where: { $0.text == followupID }) {
                        followup = .init(messageId: post.id, followupId: saved.id)
                    }
                } else {
                    followup = .init(messageId: messageID, followupId: followupID)
                }
            }
        }

        // The model puts the typing row before the questions that still wait at the chat's end
        let typingIndicator = AgentTypingIndicator()
        pendingTypingIndicatorID = typingIndicator.id
        context.append(.typingIndicator(typingIndicator), animated: true)
        coordinator.send(
            input: input,
            entryPoint: entryPoint,
            followup: followup,
            visibleText: editContext == nil ? text : nil,
            localInputMessageId: localInputMessageID
        )
    }

    /// The next waiting question goes once nothing else is answered, no limit holds and the wallet's authority is
    /// published; the chat brings it up as a question just sent. A question a limit held back goes first, by itself.
    private func sendNextQueuedQuestionIfPossible() {
        guard let next = queuedQuestions.first, canSendNow, !coordinator.isAwaitingAuthorityContext,
              let context else { return }
        // The question a limit held back goes as the same run, as its Retry sends it, and the queue follows it. Once
        // that retry has ended with the question still held back, the queue goes on without it.
        if let limitRetry = coordinator.limitRetry, limitRetry != queueRetriedLimit, coordinator.canRetryLimit {
            queueRetriedLimit = limitRetry
            coordinator.retryLimit()
            return
        }
        queuedQuestions.removeFirst()
        context.revealSentMessage(next.userMessageID) {
            startRun(
                text: next.text,
                userMessageID: next.userMessageID,
                source: next.source,
                editContext: nil,
                in: context
            )
        }
    }

    /// The questions that wait for a wallet the user switched from fail together, as a failed send does: their bubbles
    /// stay at the chat's end, with one failure after them, whose Retry asks them again for the current wallet. A
    /// wallet whose authority is only published again keeps its questions waiting.
    private func failQuestionsOfPreviousWallet() {
        let accountID = coordinator.activeAccountID
        if isDiscussionSupportRequestPending, discussionSupportAccountId != accountID {
            isDiscussionSupportRequestPending = false
            discussionSupportAccountId = nil
        }
        let failed = queuedQuestions.filter { $0.accountID != accountID }
        guard !failed.isEmpty else { return }
        queuedQuestions.removeAll { $0.accountID != accountID }
        // They join the questions failed before that stay last, under one failure after them all
        let previous = trailingFailedQuestions?.questions ?? []
        failedQuestionGroups.removeAll { $0.anchorNativeID == nil }
        failedQuestionGroups.append(FailedQuestionGroup(questions: previous + failed, failureID: UUID()))
    }

    /// The questions a wallet switch failed that stay last in the chat
    private var trailingFailedQuestions: FailedQuestionGroup? {
        failedQuestionGroups.first { $0.anchorNativeID == nil }
    }

    private var canRetryFailedQuestions: Bool {
        !didStop && !isClearing && !coordinator.isDeletingChat && !coordinator.isInputBlockedByLimit
    }

    /// Asks again, for the current wallet, the questions a wallet switch failed, also while an answer is written: they
    /// go after it, before the questions that wait since
    private func retryFailedQuestions() {
        guard canRetryFailedQuestions, let failed = trailingFailedQuestions else { return }
        let accountID = coordinator.activeAccountID
        failedQuestionGroups.removeAll { $0.anchorNativeID == nil }
        queuedQuestions.insert(contentsOf: failed.questions.map { question in
            var question = question
            question.accountID = accountID
            return question
        }, at: 0)
        synchronizeMessages()
        sendNextQueuedQuestionIfPossible()
        notifyStateChanged()
    }

    /// Once a later question goes, the questions a wallet switch failed stay where they stand, after the chat's last
    /// message, and their Retry goes, as on Android
    private func anchorFailedQuestions() {
        guard let index = failedQuestionGroups.firstIndex(where: { $0.anchorNativeID == nil }) else { return }
        guard let lastNativeID = coordinator.messages.last?.id else {
            failedQuestionGroups.remove(at: index)
            return
        }
        failedQuestionGroups[index].anchorNativeID = lastNativeID
    }

    /// An edit or a regeneration from the message `nativeID` replaces the questions a wallet switch failed after it
    private func removeFailedQuestions(from nativeID: String) {
        failedQuestionGroups.removeAll { isFailedQuestionGroup($0, after: nativeID) }
    }

    /// The questions of `group` stand after the message `nativeID`: last in the chat, or after it or a later message
    private func isFailedQuestionGroup(_ group: FailedQuestionGroup, after nativeID: String) -> Bool {
        guard let anchorNativeID = group.anchorNativeID else { return true }
        let messages = coordinator.messages
        guard let index = messages.firstIndex(where: { $0.id == nativeID }),
              let anchorIndex = messages.firstIndex(where: { $0.id == anchorNativeID }) else { return false }
        return anchorIndex >= index
    }

    func holdQueuedQuestions() {
        queuedQuestionHoldCount += 1
        notifyStateChanged()
    }

    func releaseQueuedQuestions() {
        queuedQuestionHoldCount -= 1
        sendNextQueuedQuestionIfPossible()
        notifyStateChanged()
    }

    /// The questions that wait in the chat, and those a wallet switch failed, go after the chat is deleted
    func dropQueuedQuestions() {
        guard !queuedQuestions.isEmpty || !failedQuestionGroups.isEmpty else { return }
        queuedQuestions.removeAll()
        failedQuestionGroups.removeAll()
        synchronizeMessages()
        notifyStateChanged()
    }

    func transferQueuedQuestions(to backend: AgentV2Backend) {
        if isDiscussionSupportRequestPending, !backend.isDiscussionSupportRequestPending {
            backend.isDiscussionSupportRequestPending = true
            backend.discussionSupportAccountId = discussionSupportAccountId
        }
        isDiscussionSupportRequestPending = false
        discussionSupportAccountId = nil
        for question in queuedQuestions {
            backend.bind(nativeID: question.nativeID, to: question.userMessageID)
        }
        backend.queuedQuestions += queuedQuestions
        queuedQuestions.removeAll()
        if let failed = trailingFailedQuestions {
            for question in failed.questions {
                backend.bind(nativeID: question.nativeID, to: question.userMessageID)
            }
            let previous = backend.trailingFailedQuestions
            backend.failedQuestionGroups.removeAll { $0.anchorNativeID == nil }
            backend.failedQuestionGroups.append(FailedQuestionGroup(
                questions: (previous?.questions ?? []) + failed.questions,
                failureID: previous?.failureID ?? failed.failureID
            ))
            failedQuestionGroups.removeAll { $0.anchorNativeID == nil }
        }
        backend.synchronizeMessages()
        backend.sendNextQueuedQuestionIfPossible()
        backend.sendPendingDiscussionSupportRequestIfPossible()
        backend.notifyStateChanged()
    }

    func clearConversation() {
        guard canClearConversation else { return }
        queuedQuestions.removeAll()
        failedQuestionGroups.removeAll()
        isClearing = true
        // The answer being written stops, as the cleared thread can't keep it
        coordinator.stopRun()
        notifyStateChanged()
        Task { [weak self] in
            guard let self else { return }
            let didClear = await self.coordinator.clearThread()
            guard !self.didStop else { return }
            self.isClearing = false
            if didClear {
                self.resetPresentationState()
            } else {
                self.synchronizeMessages(forceTimelineReplacement: true)
                AppActions.showError(error: DisplayError(text: lang("Agent is unavailable")))
            }
            self.notifyStateChanged()
        }
    }

    func canEditMessage(messageID: AgentItemID) -> Bool {
        // A question of the SDK's copy of the history is not edited before the history loads, and a question that waits
        // or failed has no stored message to edit
        guard canSendMessages, !coordinator.isShowingCachedMessages,
              let nativeID = nativeIDByUIID[messageID] else { return false }
        return coordinator.messages.contains { $0.id == nativeID }
    }

    func canRegenerateMessage(messageID: AgentItemID) -> Bool {
        guard !coordinator.isSupportActive, canSendMessages, messageID != newsPostItemID, messageID != statusMessageID,
              let nativeID = nativeIDByUIID[messageID],
              let message = coordinator.messages.first(where: { $0.id == nativeID }) else { return false }
        // Only an answer the server stores can be asked for again
        return message.role == .assistant && !message.newsPost && !message.status.isStreaming && !nativeID.hasPrefix("local-")
    }

    func getItemIDsRemovedByRegenerating(messageID: AgentItemID) -> [AgentItemID] {
        let replacedNativeIDs = getNativeIDsReplacedByRegenerating(messageID: messageID)
        guard let nativeID = replacedNativeIDs.first else { return [] }
        // The questions a wallet switch failed after the answer go with it
        let failedIDs = failedQuestionGroups.filter { isFailedQuestionGroup($0, after: nativeID) }.flatMap { group in
            group.questions.map(\.userMessageID) + [group.failureID]
        }
        return replacedNativeIDs.compactMap { uiIDByNativeID[$0] } + failedIDs
    }

    func regenerateMessage(messageID: AgentItemID) {
        let replacedNativeIDs = getNativeIDsReplacedByRegenerating(messageID: messageID)
        guard let nativeID = replacedNativeIDs.first, let context else { return }
        messageReplacement.beginRegeneration(targetNativeID: nativeID, replacedNativeIDs: replacedNativeIDs)
        removeFailedQuestions(from: nativeID)
        synchronizeMessages()
        let typingIndicator = AgentTypingIndicator()
        pendingTypingIndicatorID = typingIndicator.id
        context.append(.typingIndicator(typingIndicator), animated: true)
        let isStarted = coordinator.send(
            input: .regenerate(targetAssistantMessageId: nativeID),
            entryPoint: nil,
            visibleText: nil,
            localInputMessageId: nil
        )
        if !isStarted {
            resyncIfNeeded(after: messageReplacement.regenerationDidNotStart())
            removeOrphanedTypingIndicatorIfNeeded()
            synchronizeMessages(forceTimelineReplacement: true)
        }
    }

    func reportProblem(messageID: AgentItemID?, comment: String?) async -> Bool {
        guard canReportProblem, messageID == nil || messageID != newsPostItemID else { return false }
        // The status row has no stored message, so it reports the conversation. An answer that lost its stored
        // message is not reported as the conversation in its place.
        var nativeMessageID: String?
        if let messageID, messageID != statusMessageID {
            guard let nativeID = nativeIDByUIID[messageID] else { return false }
            nativeMessageID = nativeID
        }
        return await coordinator.reportProblem(messageId: nativeMessageID, comment: comment)
    }

    func rateMessage(messageID: AgentItemID, feedback: ApiAgentV2AnswerFeedback?) async -> Bool {
        guard messageID != newsPostItemID,
              let nativeID = nativeIDByUIID[messageID] else { return false }
        return await coordinator.setFeedback(messageId: nativeID, feedback: feedback)
    }

    func loadOlderMessages() async -> Bool {
        guard didPresentInitialTimeline,
              !isClearing,
              !isLoadingOlderMessages,
              coordinator.activeRun?.isRunning != true,
              coordinator.nextMessageCursor != nil else { return false }
        isLoadingOlderMessages = true
        synchronizeMessages()
        notifyStateChanged()
        let didLoad = await coordinator.loadOlderMessages()
        guard !didStop else { return false }
        isLoadingOlderMessages = false
        synchronizeMessages()
        sendNextQueuedQuestionIfPossible()
        notifyStateChanged()
        return didLoad
    }

    func performControl(messageID: AgentItemID, controlID: String) {
        guard let interaction = interactionsByMessageID[messageID]?[controlID] else { return }
        switch interaction {
        case .action(let nativeMessageID, let action):
            actionExecutor.perform(action, messageId: nativeMessageID)
        case .followup(let nativeMessageID, let followup):
            guard !coordinator.isSupportActive, canSendMessages else { return }
            context?.sendMessage(
                followup.text,
                source: .followup(messageID: nativeMessageID, followupID: followup.id)
            )
        case .discussionFollowup(let text):
            guard canSendMessages else { return }
            context?.sendMessage(text, source: .followup(messageID: newsPostPresentationKey, followupID: text))
        case .retryLimit:
            coordinator.retryLimit()
        case .retryOpening:
            guard !coordinator.isSupportActive else { return }
            coordinator.retryOpening()
        case .retryLoad:
            coordinator.retryLoad()
        case .retryFailedQuestions:
            retryFailedQuestions()
        }
    }

    /// Stops the answer being written, and the next waiting question goes at once
    func stopAnswer() {
        guard canStopAnswer, let run = coordinator.activeRun else { return }
        // Stop stays under the finger that stopped the answer before, so the run that stop started for a waiting
        // question can't be stopped until it has its id, as on Android
        guard run.generation != stopStartedRunGeneration || run.runId != nil else { return }
        let hadQueuedQuestion = !queuedQuestions.isEmpty
        // Its change sends the next waiting question
        coordinator.stopRun()
        sendNextQueuedQuestionIfPossible()
        if hadQueuedQuestion, let nextRun = coordinator.activeRun, nextRun.isRunning {
            stopStartedRunGeneration = nextRun.generation
        }
        notifyStateChanged()
    }

    func refreshPresentation() {
        synchronizeHints(force: true)
        synchronizeMessages(forceMessageUpdates: true)
        notifyStateChanged()
    }

    func setActive(_ isActive: Bool) {
        coordinator.setChatVisible(isActive)
        if isActive, hasSupportHintThreadsFailed {
            hasSupportHintThreadsFailed = false
            synchronizeHints()
        }
    }

    func stop() {
        guard !didStop else { return }
        didStop = true
        isDiscussionSupportRequestPending = false
        discussionSupportAccountId = nil
        queuedQuestions.removeAll()
        failedQuestionGroups.removeAll()
        detach()
        coordinator.stop()
    }

    func agentV2CoordinatorDidChange(
        _ coordinator: AgentV2Coordinator,
        change: AgentV2CoordinatorChange
    ) {
        if case .walletSelectionChanged(let accountId) = change {
            guard isDiscussionSupportRequestPending,
                  accountId == nil || accountId != discussionSupportAccountId else { return }
            isDiscussionSupportRequestPending = false
            discussionSupportAccountId = nil
            notifyStateChanged()
            return
        }
        let terminalOutcome: ApiAgentV2RunResultState?
        if case .runTerminated(let outcome) = change {
            let generation = coordinator.activeRun?.generation
            if let generation, generation == lastSettledRunGeneration {
                terminalOutcome = nil
            } else {
                terminalOutcome = outcome
                lastSettledRunGeneration = generation
            }
        } else {
            terminalOutcome = nil
        }
        if case .messageIdReconciled(let localID, let canonicalID) = change {
            reconcileMessageID(localID: localID, canonicalID: canonicalID)
        }
        failQuestionsOfPreviousWallet()
        messageReplacement.admitRegeneration(runID: coordinator.activeRun?.runId)
        let replacementResolution = messageReplacement.runTerminated(outcome: terminalOutcome)
        resyncIfNeeded(after: replacementResolution)
        let shouldForceTimelineReplacement = replacementResolution != .none
        let shouldRebuildTimelineForTimestampChanges = change == .messagesHydrated
        synchronizeHints()
        synchronizeMessages(
            forceTimelineReplacement: shouldForceTimelineReplacement
                || change == .messagesHydrated && coordinator.isOpening && !coordinator.isDiscussion && coordinator.activeRun == nil,
            shouldRebuildTimelineForTimestampChanges: shouldRebuildTimelineForTimestampChanges
        )
        if terminalOutcome != nil {
            removeOrphanedTypingIndicatorIfNeeded()
        }
        markLoadedSupportMessagesSeen()
        sendNextQueuedQuestionIfPossible()
        sendPendingDiscussionSupportRequestIfPossible()
        sendPendingSupportRequestIfPossible()
        notifyStateChanged()
    }

    private func markLoadedSupportMessagesSeen() {
        guard coordinator.isChatForegroundVisible,
              let threadId = coordinator.thread?.id,
              let loadedOperatorMessageAt = coordinator.loadedOperatorMessageAt else { return }
        AgentThreadReadState.shared.markOperatorMessagesSeen(
            threadId: threadId,
            loadedOperatorMessageAt: loadedOperatorMessageAt
        )
    }

    private var isTimelineReady: Bool {
        !didStop && (coordinator.hasHydratedMessages || coordinator.isDeferredDiscussion)
    }

    private func synchronizeHints(force: Bool = false) {
        let response = coordinator.hasHydratedMessages && !coordinator.isDiscussion ? coordinator.hints : nil
        var hints: [AgentHint] = response?.items.map { item in
            let copy = AgentV2Copy.hint(item.id)
            return AgentHint(
                id: item.id.rawValue,
                title: copy.title,
                subtitle: copy.prompt,
                prompt: copy.prompt,
                catalogVersion: response?.catalogVersion
            )
        } ?? []
        // Contact Support follows the server's suggestions, drawn by the client, once the server's chats it chooses
        // from start to load
        if response != nil, isSupportRequestVisible {
            hints.append(.supportRequest)
            loadSupportHintThreadsIfNeeded()
        }
        guard force || hints != lastHints else { return }
        lastHints = hints
        context?.setHints(hints, animated: hintsAnimated)
        hintsAnimated = false
    }

    private func synchronizeMessages(
        forceTimelineReplacement: Bool = false,
        forceMessageUpdates: Bool = false,
        shouldRebuildTimelineForTimestampChanges: Bool = false
    ) {
        guard let context, !isClearing,
              coordinator.hasHydratedMessages || coordinator.hasShownCachedMessages || coordinator.error != nil
                || coordinator.newsPreview != nil || coordinator.digestPreview != nil
                || !queuedQuestions.isEmpty
                || coordinator.hasPendingOpenings && !coordinator.messages.isEmpty else { return }
        defer { synchronizeOpeningTypingIndicator() }
        let needsMessageUpdates = forceMessageUpdates || presentedNews != coordinator.news || presentedDigest != coordinator.digest
        presentedNews = coordinator.news
        presentedDigest = coordinator.digest
        messageReplacement.prune(messages: coordinator.messages)

        var nextInteractions: [AgentItemID: [String: Interaction]] = [:]
        let news = coordinator.nextMessageCursor == nil ? coordinator.news : nil
        // A digest's post stands where a news item's does, with the digest's card in place of the news
        let digest = coordinator.nextMessageCursor == nil ? coordinator.digest : nil
        let nativePost = news.flatMap { news in
            coordinator.messages.first(where: \.newsPost)
                ?? coordinator.messages.first(where: { $0.role == .user }).flatMap { $0.text == news.headline ? $0 : nil }
        } ?? digest.flatMap { _ in coordinator.messages.first(where: \.newsPost) }
        let postText = news.map { "**\($0.headline)**" + (($0.body ?? $0.excerpt).map { "\n\n\($0)" } ?? "") }
            ?? digest.map { "**\(lang("$agent_digest_title"))**\n\n" + $0.top.map(\.headline).joined(separator: " · ") }
        newsPostItemID = postText == nil ? nil : postItemID
        var desired: [PresentedMessage] = []
        if let postText {
            if let nativePost {
                postTimestamp = nativePost.createdAt
                bind(nativeID: nativePost.id, to: postItemID)
            } else if postTimestamp == nil {
                postTimestamp = coordinator.hasOpening ? Date() : AgentV2DateParser.date(news?.publishedAt ?? digest!.windowEnd)
            }
            // The post's own follow-ups are suggestions about the news, shown under it while it is the latest message and
            // nothing is being answered
            let postControls: [AgentMessageControl]
            if let nativePost, nativePost.newsPost,
               nativePost.id == coordinator.messages.last?.id,
               !nativePost.status.isStreaming,
               coordinator.activeRun?.isRunning != true {
                postControls = messageControls(
                    for: nativePost,
                    messageID: postItemID,
                    interactions: &nextInteractions
                )
            } else if coordinator.isDeferredDiscussion, queuedQuestions.isEmpty {
                postControls = (coordinator.discussionNaming?.followups ?? []).enumerated().map { index, text in
                    let controlID = "discussion-followup:\(index)"
                    nextInteractions[postItemID, default: [:]][controlID] = .discussionFollowup(text: text)
                    return AgentMessageControl(
                        id: controlID,
                        title: text,
                        isEnabled: canSendMessages,
                        kind: .followup
                    )
                }
            } else {
                postControls = []
            }
            desired.append(PresentedMessage(
                key: newsPostPresentationKey,
                message: AgentMessage(
                    id: postItemID,
                    role: .assistant,
                    text: postText,
                    isStreaming: false,
                    controls: postControls,
                    newsPost: true,
                    renderingPolicy: .agentV2Safe,
                    timestamp: postTimestamp ?? Date()
                ),
                replacedItemID: nil
            ))
        }
        let failedSupportRequest = coordinator.failedSupportRequest
        let shownMessages = coordinator.messages.filter {
            $0.id != nativePost?.id && $0.id != failedSupportRequest?.message.id
                && !messageReplacement.ignoredNativeIDs.contains($0.id)
        }
        // A failure shows once: the status row at the end takes the place of the last answer's caption when both show
        // the same failure, the latest run's or that of the limit that blocks sending
        let lastFailedAnswer = shownMessages.last.flatMap { $0.role == .assistant && $0.error != nil ? $0 : nil }
        let isLastFailureShownByStatus = coordinator.error != nil
            ? coordinator.isRunFailure
            : lastFailedAnswer?.error?.code != nil && lastFailedAnswer?.error?.code == coordinator.inputLimitErrorCode
        let failureShownByStatus = isLastFailureShownByStatus ? lastFailedAnswer?.id : nil
        shouldShowAuthors = AgentSupportPresentation.checkAuthorsShown(in: coordinator.messages)
        for nativeMessage in shownMessages {
            desired += presentedMessages(
                nativeMessage,
                showsFailure: nativeMessage.id != failureShownByStatus,
                interactions: &nextInteractions
            )
            for group in failedQuestionGroups where group.anchorNativeID == nativeMessage.id {
                desired += presentedFailedQuestions(group, in: context, interactions: &nextInteractions)
            }
        }
        if let failedSupportRequest {
            desired += presentedFailedSupportRequest(failedSupportRequest, in: context)
        }
        if coordinator.isDeferredDiscussion {
            desired += queuedQuestions.map { presentedQuestion($0, in: context) }
        }
        if let status = statusMessage(interactions: &nextInteractions) {
            desired.append(status)
        }
        // The questions a wallet switch failed, their failure, then the questions that wait stay last, below the answer
        // and its failure
        if let failed = trailingFailedQuestions {
            desired += presentedFailedQuestions(failed, in: context, interactions: &nextInteractions)
        }
        let nativeIDs = Set(coordinator.messages.map(\.id))
        if !coordinator.isDeferredDiscussion {
            desired += queuedQuestions.filter { !nativeIDs.contains($0.nativeID) }.map { presentedQuestion($0, in: context) }
        }
        let desiredKeys = desired.map(\.key)
        interactionsByMessageID = nextInteractions

        let hasTimestampChanges = shouldRebuildTimelineForTimestampChanges && desired.contains { item in
            guard item.key != statusPresentationKey,
                  let existing = context.message(for: item.message.id) else { return false }
            return existing.timestamp != item.message.timestamp
        }

        if forceTimelineReplacement || hasTimestampChanges || !didPresentInitialTimeline
            || context.itemIDs.isEmpty && !desired.isEmpty {
            context.replaceTimeline(
                with: desired.map { .message($0.message) },
                animated: false,
                reconfigureItemIDs: desired.map(\.message.id)
            )
            presentedKeys = desiredKeys
            didPresentInitialTimeline = true
            if !desiredKeys.contains(statusPresentationKey) {
                statusMessageID = nil
            }
            return
        }

        let desiredKeySet = Set(desiredKeys)
        let previousKeySet = Set(presentedKeys)
        let retainedPrevious = presentedKeys.filter(desiredKeySet.contains)
        let retainedDesired = desiredKeys.filter(previousKeySet.contains)
        let newKeys = desiredKeys.filter { !previousKeySet.contains($0) }
        let isAppendOnly = Array(desiredKeys.suffix(newKeys.count)) == newKeys

        if retainedPrevious != retainedDesired || !isAppendOnly {
            context.replaceTimeline(
                with: desired.map { .message($0.message) },
                animated: false,
                reconfigureItemIDs: desired.map(\.message.id)
            )
            presentedKeys = desiredKeys
            if !desiredKeys.contains(statusPresentationKey) {
                statusMessageID = nil
            }
            return
        }

        let replacesStatusOnlyTimeline = presentedKeys == [statusPresentationKey]
            && !desiredKeys.contains(statusPresentationKey)
        if replacesStatusOnlyTimeline {
            context.replaceTimeline(
                with: desired.map { .message($0.message) },
                animated: false,
                reconfigureItemIDs: desired.map(\.message.id)
            )
            presentedKeys = desiredKeys
            statusMessageID = nil
            return
        }

        for removedKey in presentedKeys where !desiredKeySet.contains(removedKey) {
            guard let messageID = uiID(forPresentationKey: removedKey) else { continue }
            context.removeItem(id: messageID, animated: false)
        }

        for item in desired {
            let wasPresented = previousKeySet.contains(item.key)
            if !wasPresented {
                if let existing = context.message(for: item.message.id) {
                    if needsMessageUpdates || !hasSamePresentation(existing, item.message) {
                        context.updateMessage(item.message, animated: false, scrollToBottom: false)
                    }
                } else if let replacedItemID = item.replacedItemID {
                    context.replaceItem(
                        id: replacedItemID,
                        with: .message(item.message),
                        animated: true
                    )
                    if context.message(for: item.message.id) == nil {
                        context.append(.message(item.message), animated: true)
                    }
                } else {
                    context.append(.message(item.message), animated: true)
                }
                continue
            }

            guard let existing = context.message(for: item.message.id),
                  needsMessageUpdates || !hasSamePresentation(existing, item.message) else { continue }
            context.updateMessage(item.message, animated: false, scrollToBottom: false)
        }
        presentedKeys = desiredKeys
        if !desiredKeys.contains(statusPresentationKey) {
            statusMessageID = nil
        }
    }

    private func synchronizeOpeningTypingIndicator() {
        guard coordinator.hasOpening,
              coordinator.hasPendingOpenings || coordinator.activeRun == nil else { return }
        if coordinator.showsOpeningTypingIndicator,
           !presentedKeys.isEmpty {
            if let pendingTypingIndicatorID, context?.itemIDs.contains(pendingTypingIndicatorID) == true { return }
            pendingTypingIndicatorID = nil
            let indicator = AgentTypingIndicator()
            pendingTypingIndicatorID = indicator.id
            context?.append(.typingIndicator(indicator), animated: false)
        } else if let pendingTypingIndicatorID {
            self.pendingTypingIndicatorID = nil
            context?.removeItem(id: pendingTypingIndicatorID, animated: false)
        }
    }

    /// The rows of a message. A failed answer shows its failure as a caption, under what the answer got to show or
    /// in its place.
    private func presentedMessages(
        _ nativeMessage: AgentV2NativeMessage,
        showsFailure: Bool,
        interactions: inout [AgentItemID: [String: Interaction]]
    ) -> [PresentedMessage] {
        let bubble = AgentV2MessagePresentation.bubble(for: nativeMessage)
        let semanticContent = bubble == nil ? nativeMessage.semanticContent : nil
        var text = bubble?.text ?? ""
        let failureText = showsFailure && nativeMessage.role == .assistant ? withMessageLanguage(nativeMessage.responseLanguage) {
            nativeMessage.error.map { AgentV2Copy.error($0.code, resetAt: $0.resetAt.map(AgentV2DateParser.date)) }
        } : nil
        let hasContent = nativeMessage.role == .user
            || !text.isEmpty
            || semanticContent != nil
            || !nativeMessage.actions.isEmpty
            || !getShownFollowups(of: nativeMessage).isEmpty
        guard hasContent || failureText != nil else { return [] }

        let key = presentationKey(nativeID: nativeMessage.id)
        let wasPresented = presentedKeys.contains(key)
        let shouldReplaceTyping = nativeMessage.role == .assistant
            && !wasPresented
            && pendingTypingIndicatorID != nil
        let messageID: AgentItemID
        let replacedItemID: AgentItemID?
        if let existingID = uiIDByNativeID[nativeMessage.id] {
            messageID = existingID
            replacedItemID = nil
        } else if shouldReplaceTyping, let typingIndicatorID = pendingTypingIndicatorID {
            messageID = UUID()
            replacedItemID = typingIndicatorID
            pendingTypingIndicatorID = nil
            bind(nativeID: nativeMessage.id, to: messageID)
        } else {
            messageID = UUID()
            replacedItemID = nil
            bind(nativeID: nativeMessage.id, to: messageID)
        }

        let timestamp = coordinator.openingMessageDate(id: nativeMessage.id) ?? nativeMessage.createdAt
        guard hasContent else {
            return [PresentedMessage(
                key: key,
                message: makeFailureCaption(id: messageID, text: failureText ?? "", timestamp: timestamp),
                replacedItemID: replacedItemID
            )]
        }
        if let editedText = messageReplacement.editedTextByNativeID[nativeMessage.id], nativeMessage.role == .user {
            text = editedText
        }
        let controls = nativeMessage.status.isStreaming
            ? []
            : messageControls(
                for: nativeMessage,
                messageID: messageID,
                interactions: &interactions
            )
        var message = AgentMessage(
            id: messageID,
            role: nativeMessage.role == .event ? .system : nativeMessage.role == .user ? .user : .assistant,
            text: text,
            isStreaming: nativeMessage.role == .assistant
                && nativeMessage.contentKind == .markdown
                && nativeMessage.status.isStreaming,
            responseLanguage: nativeMessage.responseLanguage,
            semanticContent: semanticContent,
            controls: controls,
            newsPost: nativeMessage.newsPost,
            renderingPolicy: .agentV2Safe,
            timestamp: timestamp
        )
        if let operatorAuthor = nativeMessage.operatorAuthor, nativeMessage.role == .operator {
            message.author = .operator(operatorAuthor)
        }
        message.supportEvent = nativeMessage.supportEvent
        message.isPlainText = nativeMessage.role == .operator
        message.isEditingDisabled = coordinator.isSupportActive
        message.shouldShowAuthor = shouldShowAuthors && nativeMessage.role != .user && nativeMessage.role != .event
        if !nativeMessage.tableReferences.isEmpty {
            message.answerBlocks = AgentV2AnswerTables.blocks(
                nativeMessage.content.text,
                tables: nativeMessage.tables,
                references: nativeMessage.tableReferences,
                links: nativeMessage.links
            )
        }
        message.canRate = nativeMessage.isStoredAsComplete && !nativeMessage.newsPost && !coordinator.isShowingCachedMessages
        message.feedback = nativeMessage.feedback
        var presented = [PresentedMessage(key: key, message: message, replacedItemID: replacedItemID)]
        if let failureText {
            presented.append(PresentedMessage(
                key: failurePresentationPrefix + nativeMessage.id,
                message: makeFailureCaption(id: failureCaptionID(for: nativeMessage.id), text: failureText, timestamp: timestamp),
                replacedItemID: nil
            ))
        }
        return presented
    }

    /// The bubble of a question that waits or failed, as the chat showed it once it was sent
    private func presentedQuestion(_ question: QueuedQuestion, in context: AgentBackendContext) -> PresentedMessage {
        PresentedMessage(
            key: presentationKey(nativeID: question.nativeID),
            message: context.message(for: question.userMessageID) ?? AgentMessage(
                id: question.userMessageID,
                role: .user,
                text: question.text,
                isStreaming: false,
                timestamp: question.timestamp
            ),
            replacedItemID: nil
        )
    }

    /// The rows of questions a wallet switch failed, as of a failed send: their bubbles, then one failure, with Retry
    /// while they stay last
    private func presentedFailedQuestions(
        _ group: FailedQuestionGroup,
        in context: AgentBackendContext,
        interactions: inout [AgentItemID: [String: Interaction]]
    ) -> [PresentedMessage] {
        var controls: [AgentMessageControl] = []
        if group.anchorNativeID == nil {
            let retry = AgentMessageControl(
                id: "retry-failed-questions",
                title: lang("Retry"),
                isEnabled: canRetryFailedQuestions
            )
            controls.append(retry)
            interactions[group.failureID, default: [:]][retry.id] = .retryFailedQuestions
        }
        let failure = PresentedMessage(
            key: failedQuestionsPresentationPrefix + group.failureID.uuidString,
            message: makeFailureCaption(
                id: group.failureID,
                text: lang("$agent_error_generic"),
                controls: controls,
                timestamp: group.questions.last?.timestamp ?? Date()
            ),
            replacedItemID: nil
        )
        return group.questions.map { presentedQuestion($0, in: context) } + [failure]
    }

    /// The support request the server didn't take and its failure, without Retry: a new request asks again
    private func presentedFailedSupportRequest(
        _ request: AgentV2Coordinator.FailedSupportRequest,
        in context: AgentBackendContext
    ) -> [PresentedMessage] {
        let nativeID = request.message.id
        let messageID: AgentItemID
        if let boundID = uiIDByNativeID[nativeID] {
            messageID = boundID
        } else {
            messageID = UUID()
            bind(nativeID: nativeID, to: messageID)
        }
        var message = context.message(for: messageID) ?? AgentMessage(
            id: messageID,
            role: .user,
            text: request.message.text,
            isStreaming: false,
            timestamp: request.message.createdAt
        )
        message.isEditingDisabled = true
        let failure = makeFailureCaption(
            id: failureCaptionID(for: nativeID),
            text: request.code.map(AgentV2Copy.error) ?? lang("$agent_error_generic"),
            timestamp: message.timestamp
        )
        return [
            PresentedMessage(key: presentationKey(nativeID: nativeID), message: message, replacedItemID: nil),
            PresentedMessage(key: failurePresentationPrefix + nativeID, message: failure, replacedItemID: nil),
        ]
    }

    private func makeFailureCaption(
        id: AgentItemID,
        text: String,
        controls: [AgentMessageControl] = [],
        timestamp: Date = Date()
    ) -> AgentMessage {
        AgentMessage(
            id: id,
            role: .assistant,
            text: text,
            isStreaming: false,
            controls: controls,
            renderingPolicy: .agentV2Safe,
            systemStyle: .failure,
            timestamp: timestamp
        )
    }

    private func failureCaptionID(for nativeID: String) -> AgentItemID {
        if let id = failureCaptionIDByNativeID[nativeID] { return id }
        let id = UUID()
        failureCaptionIDByNativeID[nativeID] = id
        return id
    }

    private func statusMessage(
        interactions: inout [AgentItemID: [String: Interaction]]
    ) -> PresentedMessage? {
        // A limit that blocks sending shows from the start, as on the web, also in a chat where nothing failed yet
        guard let error = coordinator.error ?? coordinator.inputLimitErrorCode.map({
            AgentV2Copy.error($0, resetAt: coordinator.userQuotaResetDate)
        }) else { return nil }
        // A chat with nothing to show has the failure in its middle instead
        guard coordinator.hasPendingOpenings || coordinator.hasHydratedMessages || coordinator.error == nil
                || coordinator.news != nil || coordinator.digest != nil || !coordinator.messages.isEmpty else { return nil }
        let messageID: AgentItemID
        let replacedItemID: AgentItemID?
        if let statusMessageID {
            messageID = statusMessageID
            replacedItemID = nil
        } else if let typingIndicatorID = pendingTypingIndicatorID {
            messageID = UUID()
            replacedItemID = typingIndicatorID
            pendingTypingIndicatorID = nil
            statusMessageID = messageID
        } else {
            let newID = UUID()
            statusMessageID = newID
            messageID = newID
            replacedItemID = nil
        }

        var controls: [AgentMessageControl] = []
        if coordinator.hasLimitRetry {
            let control = AgentMessageControl(
                id: "retry-limit",
                title: lang("Retry"),
                isEnabled: coordinator.canRetryLimit
            )
            controls.append(control)
            interactions[messageID, default: [:]][control.id] = .retryLimit
        } else if !coordinator.isSupportActive, coordinator.isOpening {
            let control = AgentMessageControl(
                id: "retry-opening",
                title: lang("Retry"),
                isEnabled: coordinator.canRetryOpening
            )
            controls.append(control)
            interactions[messageID, default: [:]][control.id] = .retryOpening
        } else if coordinator.isLoadFailure || coordinator.isShowingCachedMessages && coordinator.error != nil {
            // The chat shows what it had, and the failure line under it loads it again; a chat on its cached history
            // starts over whatever failed
            let control = AgentMessageControl(id: "retry-load", title: lang("Retry"), isEnabled: true)
            controls.append(control)
            interactions[messageID, default: [:]][control.id] = .retryLoad
        }
        return PresentedMessage(
            key: statusPresentationKey,
            message: makeFailureCaption(id: messageID, text: error, controls: controls),
            replacedItemID: replacedItemID
        )
    }

    private func messageControls(
        for nativeMessage: AgentV2NativeMessage,
        messageID: AgentItemID,
        interactions: inout [AgentItemID: [String: Interaction]]
    ) -> [AgentMessageControl] {
        withMessageLanguage(nativeMessage.responseLanguage) {
            var controls: [AgentMessageControl] = []
            for action in nativeMessage.actions {
                let controlID = "action:\(action.id)"
                let isEnabled = !coordinator.isShowingCachedMessages && (
                    action.kind != .send
                        || action.labelCode == .openSend
                        || action.presentation?.kind == .send && action.presentation?.status == .active
                )
                controls.append(AgentMessageControl(
                    id: controlID,
                    title: action.title,
                    isEnabled: isEnabled
                ))
                interactions[messageID, default: [:]][controlID] = .action(
                    messageID: nativeMessage.id,
                    action: action
                )
            }
            // The cached history that stays with a failure shows no suggestions
            let followups = coordinator.hasCachedHistoryFailed ? [] : getShownFollowups(of: nativeMessage)
            for followup in followups {
                let controlID = "followup:\(followup.id)"
                // The cached history's suggestions look as the loaded history's do; the chat ignores a tap on them
                controls.append(AgentMessageControl(
                    id: controlID,
                    title: followup.text,
                    isEnabled: canSendMessages || coordinator.isShowingCachedMessages,
                    kind: .followup
                ))
                interactions[messageID, default: [:]][controlID] = .followup(
                    messageID: nativeMessage.id,
                    followup: followup
                )
            }
            return controls
        }
    }

    private func getShownFollowups(of nativeMessage: AgentV2NativeMessage) -> [ApiAgentV2FollowUp] {
        coordinator.isSupportActive || nativeMessage.status == .cancelled ? [] : nativeMessage.followups
    }

    private func reconcileMessageID(localID: String, canonicalID: String) {
        guard localID != canonicalID else { return }
        messageReplacement.reconcileMessageID(localID: localID, canonicalID: canonicalID)
        for index in failedQuestionGroups.indices where failedQuestionGroups[index].anchorNativeID == localID {
            failedQuestionGroups[index].anchorNativeID = canonicalID
        }
        guard let uiID = uiIDByNativeID.removeValue(forKey: localID) else { return }
        if let previousCanonicalUIID = uiIDByNativeID[canonicalID], previousCanonicalUIID != uiID {
            nativeIDByUIID.removeValue(forKey: previousCanonicalUIID)
        }
        uiIDByNativeID[canonicalID] = uiID
        nativeIDByUIID[uiID] = canonicalID
        let localKey = presentationKey(nativeID: localID)
        if let index = presentedKeys.firstIndex(of: localKey) {
            presentedKeys[index] = presentationKey(nativeID: canonicalID)
        }
    }

    /// Reloads the thread when the server admitted a run whose replaced messages came back
    private func resyncIfNeeded(after resolution: AgentV2MessageReplacement.Resolution) {
        guard resolution == .restoreAndResync else { return }
        Task { [weak self] in await self?.coordinator.hydrate() }
    }

    /// The answer `messageID` names, first, and the messages after it; none when the answer can't be asked for again
    private func getNativeIDsReplacedByRegenerating(messageID: AgentItemID) -> [String] {
        guard canRegenerateMessage(messageID: messageID),
              let nativeID = nativeIDByUIID[messageID],
              let index = coordinator.messages.firstIndex(where: { $0.id == nativeID }) else { return [] }
        return coordinator.messages.suffix(from: index).map(\.id)
    }

    private func removeOrphanedTypingIndicatorIfNeeded() {
        guard let pendingTypingIndicatorID else { return }
        self.pendingTypingIndicatorID = nil
        context?.removeItem(id: pendingTypingIndicatorID, animated: false)
    }

    func itemID(nativeID: String) -> AgentItemID? {
        uiIDByNativeID[nativeID]
    }

    private func bind(nativeID: String, to uiID: AgentItemID) {
        uiIDByNativeID[nativeID] = uiID
        nativeIDByUIID[uiID] = nativeID
    }

    private func resetPresentationState() {
        uiIDByNativeID.removeAll()
        nativeIDByUIID.removeAll()
        failureCaptionIDByNativeID.removeAll()
        presentedKeys.removeAll()
        interactionsByMessageID.removeAll()
        messageReplacement.reset()
        pendingTypingIndicatorID = nil
        statusMessageID = nil
        didPresentInitialTimeline = false
        postTimestamp = nil
        synchronizeMessages()
    }

    private func notifyStateChanged() {
        context?.notifyStateChanged()
    }

    private func uiID(forPresentationKey key: String) -> AgentItemID? {
        if key == newsPostPresentationKey { return postItemID }
        if key == statusPresentationKey {
            return statusMessageID
        }
        if key.hasPrefix(failurePresentationPrefix) {
            return failureCaptionIDByNativeID[String(key.dropFirst(failurePresentationPrefix.count))]
        }
        if key.hasPrefix(failedQuestionsPresentationPrefix) {
            return UUID(uuidString: String(key.dropFirst(failedQuestionsPresentationPrefix.count)))
        }
        guard key.hasPrefix(messagePresentationPrefix) else { return nil }
        return uiIDByNativeID[String(key.dropFirst(messagePresentationPrefix.count))]
    }

    private func presentationKey(nativeID: String) -> String {
        messagePresentationPrefix + nativeID
    }

    private func hasSamePresentation(_ lhs: AgentMessage, _ rhs: AgentMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.role == rhs.role
            && lhs.author == rhs.author
            && lhs.supportEvent == rhs.supportEvent
            && lhs.isPlainText == rhs.isPlainText
            && lhs.isEditingDisabled == rhs.isEditingDisabled
            && lhs.shouldShowAuthor == rhs.shouldShowAuthor
            && lhs.text == rhs.text
            && lhs.isStreaming == rhs.isStreaming
            && lhs.semanticContent == rhs.semanticContent
            && lhs.controls == rhs.controls
            && lhs.renderingPolicy == rhs.renderingPolicy
            && lhs.supplementaryErrorText == rhs.supplementaryErrorText
            && lhs.canRate == rhs.canRate
            && lhs.newsPost == rhs.newsPost
            && lhs.feedback == rhs.feedback
    }

    private let messagePresentationPrefix = "message:"
    /// The caption of a failed answer that shows what it got to write
    private let failurePresentationPrefix = "failure:"
    /// The failure after questions a wallet switch failed
    private let failedQuestionsPresentationPrefix = "failed-questions:"
    private let statusPresentationKey = "status"
    private let newsPostPresentationKey = "news-post"
}
