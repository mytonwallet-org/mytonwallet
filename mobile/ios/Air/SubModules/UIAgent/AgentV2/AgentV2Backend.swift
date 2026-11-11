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
    var onStop: (() -> Void)?
    private var transferredPresentationModel: AgentV2Model?
    var presentationModel: AgentV2Model { transferredPresentationModel ?? self }
    private var presentationModelChangedHandlers: [ObjectIdentifier: (AgentV2Model) -> Void] = [:]
    var resolveOpeningThreadModel: ((ApiAgentV2ThreadSummary) -> AgentV2Model?)?
    private var rejectedThreadId: String?

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

    /// The user has written in the chat; a news discussion opened without a question has only the post
    var hasUserMessages: Bool {
        coordinator.messages.contains { $0.role == .user }
    }

    /// Whether the user has written in the chat, by the SDK's rule for its thread: a news discussion with only its post
    /// is not started. A message the user sends there counts at once, before the thread says so.
    var isStarted: Bool {
        !coordinator.isDiscussion || hasUserMessages || coordinator.thread?.isStarted == true
    }

    var hasActiveRun: Bool {
        coordinator.activeRun?.isRunning == true
    }

    /// The last run failed or was interrupted, and the chat shows it
    var isRunFailed: Bool {
        coordinator.isRunFailure && coordinator.error != nil
    }

    /// A limit keeps the chat from sending until it resets
    var isInputBlockedByLimit: Bool {
        coordinator.isInputBlockedByLimit
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

    /// A shown conversation can be deleted even while its thread is being created
    var canDeleteChat: Bool {
        !didStop && !isDeletingChat && (coordinator.hasPendingOpenings || coordinator.thread != nil)
    }

    /// Synchronously prevents sending before the screen closes. Server cleanup outlives its presentation.
    @discardableResult
    func beginChatDeletion() -> Bool {
        guard canDeleteChat else { return false }
        coordinator.beginChatDeletion()
        stop()
        return true
    }

    func deleteChat() async throws {
        if !isDeletingChat, !beginChatDeletion() { return }
        try await coordinator.waitForChatDeletion()
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
        if isOpening && threadId == nil && !isDeletingChat { stop() }
    }

    var newsPostItemID: AgentItemID? { v2Backend.newsPostItemID }

    func newsPost(for message: AgentMessage) -> ApiAgentV2ThreadNewsCard? {
        message.id == newsPostItemID ? news : nil
    }

    /// What the post at the top of a news or digest discussion shows, for its message
    func newsPostContent(for message: AgentMessage) -> AgentNewsPostView.Content? {
        if let news = newsPost(for: message) { return AgentNewsPostView.Content(news: news) }
        guard message.id == newsPostItemID else { return nil }
        return coordinator.digest.map(AgentNewsPostView.Content.init(digest:))
    }

    override var chatTitleText: String {
        Self.chatTitleText(
            thread: coordinator.thread,
            firstUserMessage: coordinator.news?.headline ?? coordinator.messages.first(where: { $0.role == .user })?.text
        )
    }

    override var chatIcon: String? {
        Self.chatIcon(thread: coordinator.thread)
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
        if presentationCount == 0 {
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
    init(
        client: AgentV2Client,
        thread: ApiAgentV2ThreadSummary? = nil,
        cachedHistory: AgentCachedHistory? = nil,
        isSummaryCached: Bool = false
    ) {
        let coordinator = AgentV2Coordinator(
            client: client,
            thread: thread,
            cachedHistory: cachedHistory,
            isSummaryCached: isSummaryCached
        )
        self.coordinator = coordinator
        v2Backend = AgentV2Backend(coordinator: coordinator)
        super.init(backend: v2Backend)
        // The base model starts with an empty timeline, which the cached history then fills
        if coordinator.isShowingCachedMessages {
            v2Backend.refreshPresentation()
        }
        coordinator.start()
    }

    init(
        client: AgentV2Client,
        thread: ApiAgentV2ThreadSummary? = nil,
        news: ApiAgentV2NewsFeedItem,
        locale: String,
        onThreadCreated: @escaping (ApiAgentV2ThreadSummary) -> Void
    ) {
        let coordinator = AgentV2Coordinator(
            client: client,
            thread: thread,
            news: Self.newsPreview(for: news),
            newsRequest: thread == nil ? .init(eventId: news.eventId, locale: locale) : nil
        )
        self.coordinator = coordinator
        v2Backend = AgentV2Backend(coordinator: coordinator)
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
        super.init(backend: v2Backend)
        startOpening(onThreadCreated: onThreadCreated)
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
        coordinator.start()
    }

    func rejectDeletedThread(id: String) {
        rejectedThreadId = id
        stop()
        WalletCoreData.notify(event: .agentThreadDeleted(threadId: id))
    }

    func redirectOpening(to existing: AgentV2Model) {
        coordinator.transferOpening(to: existing.coordinator)
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
        guard !didStop, editingMessageID == nil || editingMessageID != newsPostItemID else { return }
        super.send(text: text, editingMessageID: editingMessageID, source: source)
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
        case retryLimit
        case retryOpening
        case retryLoad
    }

    var canSendMessages: Bool {
        isTimelineReady
            && !coordinator.hasPendingOpenings
            && coordinator.activeRun?.isRunning != true
            && !coordinator.isInputBlockedByLimit
            && !isClearing
            && !isLoadingOlderMessages
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

    var canClearConversation: Bool {
        isTimelineReady
            && !coordinator.hasPendingOpenings
            && coordinator.thread != nil
            && coordinator.activeRun?.isRunning != true
            && !isClearing
            && !isLoadingOlderMessages
    }

    var shouldConfirmConversationClear: Bool {
        true
    }

    /// Reports are offered from the start once the user has allowed the Agent, also while a discussion's thread is
    /// being created and before the server's check has answered; a report sent then waits for both
    var canReportProblem: Bool {
        !didStop
            && coordinator.hasConsent
            && coordinator.isProblemReportAvailable
            && (coordinator.thread != nil || coordinator.isOpening)
            && !isClearing
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

    private weak var context: AgentBackendContext?
    private let coordinator: AgentV2Coordinator
    private let actionExecutor: AgentV2ActionExecutor
    private var uiIDByNativeID: [String: AgentItemID] = [:]
    private var nativeIDByUIID: [AgentItemID: String] = [:]
    private var presentedKeys: [String] = []
    private var interactionsByMessageID: [AgentItemID: [String: Interaction]] = [:]
    private var messageReplacement = AgentV2MessageReplacement()
    private var pendingTypingIndicatorID: AgentItemID?
    private var statusMessageID: AgentItemID?
    private var failureCaptionIDByNativeID: [String: AgentItemID] = [:]
    private var lastHints: [AgentHint] = []
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
        guard let nativeID = nativeIDByUIID[editContext.messageID] else { return }
        messageReplacement.beginEditing(targetNativeID: nativeID, messages: coordinator.messages)
    }

    func didSendUserMessage(
        _ text: String,
        userMessageID: AgentItemID,
        source: AgentBackendSendSource,
        editContext: AgentBackendEditContext?
    ) {
        guard canSendMessages, let context else { return }

        let input: ApiAgentV2RunInput
        let localInputMessageID: String?
        if let editContext {
            guard let targetID = nativeIDByUIID[editContext.messageID] else {
                Task { [weak self] in await self?.coordinator.hydrate() }
                AppActions.showError(error: DisplayError(text: lang("Agent is unavailable")))
                return
            }
            messageReplacement.sendEdit(targetNativeID: targetID, text: text)
            input = .edit(targetUserMessageId: targetID, text: text)
            localInputMessageID = targetID
        } else {
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
            case .followup(let messageID, let followupID):
                followup = .init(messageId: messageID, followupId: followupID)
            }
        }

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

    func clearConversation() {
        guard canClearConversation else { return }
        isClearing = true
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

    func canRegenerateMessage(messageID: AgentItemID) -> Bool {
        guard canSendMessages, messageID != newsPostItemID, messageID != statusMessageID,
              let nativeID = nativeIDByUIID[messageID],
              let message = coordinator.messages.first(where: { $0.id == nativeID }) else { return false }
        // Only an answer the server stores can be asked for again
        return message.role == .assistant && !message.newsPost && !message.status.isStreaming && !nativeID.hasPrefix("local-")
    }

    func getItemIDsRemovedByRegenerating(messageID: AgentItemID) -> [AgentItemID] {
        getNativeIDsReplacedByRegenerating(messageID: messageID).compactMap { uiIDByNativeID[$0] }
    }

    func regenerateMessage(messageID: AgentItemID) {
        let replacedNativeIDs = getNativeIDsReplacedByRegenerating(messageID: messageID)
        guard let nativeID = replacedNativeIDs.first, let context else { return }
        messageReplacement.beginRegeneration(targetNativeID: nativeID, replacedNativeIDs: replacedNativeIDs)
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
        notifyStateChanged()
        return didLoad
    }

    func performControl(messageID: AgentItemID, controlID: String) {
        guard let interaction = interactionsByMessageID[messageID]?[controlID] else { return }
        switch interaction {
        case .action(let nativeMessageID, let action):
            actionExecutor.perform(action, messageId: nativeMessageID)
        case .followup(let nativeMessageID, let followup):
            guard canSendMessages else { return }
            context?.sendMessage(
                followup.text,
                source: .followup(messageID: nativeMessageID, followupID: followup.id)
            )
        case .retryLimit:
            coordinator.retryLimit()
        case .retryOpening:
            coordinator.retryOpening()
        case .retryLoad:
            coordinator.retryLoad()
        }
    }

    func stopAnswer() {
        coordinator.stopRun()
    }

    func refreshPresentation() {
        synchronizeHints(force: true)
        synchronizeMessages(forceMessageUpdates: true)
        notifyStateChanged()
    }

    func setActive(_ isActive: Bool) {
        coordinator.setChatVisible(isActive)
    }

    func stop() {
        guard !didStop else { return }
        didStop = true
        detach()
        coordinator.stop()
    }

    func agentV2CoordinatorDidChange(
        _ coordinator: AgentV2Coordinator,
        change: AgentV2CoordinatorChange
    ) {
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
        notifyStateChanged()
    }

    private var isTimelineReady: Bool {
        !didStop && coordinator.hasHydratedMessages
    }

    private func synchronizeHints(force: Bool = false) {
        let response = coordinator.hasHydratedMessages && !coordinator.isDiscussion ? coordinator.hints : nil
        let hints: [AgentHint] = response?.items.map { item in
            let copy = AgentV2Copy.hint(item.id)
            return AgentHint(
                id: item.id.rawValue,
                title: copy.title,
                subtitle: copy.prompt,
                prompt: copy.prompt,
                catalogVersion: response?.catalogVersion
            )
        } ?? []
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
                || coordinator.newsPreview != nil
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
        let shownMessages = coordinator.messages.filter { $0.id != nativePost?.id && !messageReplacement.ignoredNativeIDs.contains($0.id) }
        // A failure shows once: the status row at the end takes the place of the last answer's caption when both show
        // the same failure, the latest run's or that of the limit that blocks sending
        let lastFailedAnswer = shownMessages.last.flatMap { $0.role == .assistant && $0.error != nil ? $0 : nil }
        let isLastFailureShownByStatus = coordinator.error != nil
            ? coordinator.isRunFailure
            : lastFailedAnswer?.error?.code != nil && lastFailedAnswer?.error?.code == coordinator.inputLimitErrorCode
        let failureShownByStatus = isLastFailureShownByStatus ? lastFailedAnswer?.id : nil
        desired += shownMessages.flatMap { nativeMessage in
            presentedMessages(
                nativeMessage,
                showsFailure: nativeMessage.id != failureShownByStatus,
                interactions: &nextInteractions
            )
        }
        if let status = statusMessage(interactions: &nextInteractions) {
            desired.append(status)
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
            nativeMessage.error.map { AgentV2Copy.error($0.code) }
        } : nil
        let hasContent = nativeMessage.role == .user
            || !text.isEmpty
            || semanticContent != nil
            || !nativeMessage.actions.isEmpty
            || !Self.getShownFollowups(of: nativeMessage).isEmpty
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
            role: nativeMessage.role == .user ? .user : .assistant,
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
        guard let error = coordinator.error ?? coordinator.inputLimitErrorCode.map(AgentV2Copy.error) else { return nil }
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
        } else if coordinator.isOpening {
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
            let followups = coordinator.hasCachedHistoryFailed ? [] : Self.getShownFollowups(of: nativeMessage)
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

    /// A stopped answer offers no suggestions
    private static func getShownFollowups(of nativeMessage: AgentV2NativeMessage) -> [ApiAgentV2FollowUp] {
        nativeMessage.status == .cancelled ? [] : nativeMessage.followups
    }

    private func reconcileMessageID(localID: String, canonicalID: String) {
        guard localID != canonicalID else { return }
        messageReplacement.reconcileMessageID(localID: localID, canonicalID: canonicalID)
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
        guard key.hasPrefix(messagePresentationPrefix) else { return nil }
        return uiIDByNativeID[String(key.dropFirst(messagePresentationPrefix.count))]
    }

    private func presentationKey(nativeID: String) -> String {
        messagePresentationPrefix + nativeID
    }

    private func hasSamePresentation(_ lhs: AgentMessage, _ rhs: AgentMessage) -> Bool {
        lhs.id == rhs.id
            && lhs.role == rhs.role
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
    private let statusPresentationKey = "status"
    private let newsPostPresentationKey = "news-post"
}
