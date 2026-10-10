import Foundation
import WalletContext
import WalletCore

private let log = Log("AgentV2Coordinator")

@MainActor
enum AgentV2CoordinatorChange: Equatable {
    case reload
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

    private final class WeakObserver {
        weak var value: AgentV2CoordinatorObserver?
        init(_ value: AgentV2CoordinatorObserver) { self.value = value }
    }

    struct RunState: Equatable, Sendable {
        let generation: Int
        var clientRunId: String?
        var runId: String?
        let threadId: String
        let localInputMessageId: String?
        var isRunning: Bool
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
    }

    private enum ErrorSource {
        case agentUnavailable
        case failedToLoadChat
        case run(ApiAgentV2ErrorCode)
    }

    private enum RunUpdateDisposition: Equatable {
        case active
        case retiredActive
        case standalone
    }

    let client: AgentV2Client
    private(set) var thread: ApiAgentV2ThreadSummary?
    var messages: [AgentV2NativeMessage] { conversation.messages }
    private(set) var nextMessageCursor: String?
    private(set) var activeRun: RunState?
    private(set) var runActivity: ApiAgentV2RunActivityEvent?
    private(set) var availability = ApiAgentV2AvailabilityState(state: .available)
    private(set) var userQuota: ApiAgentV2UserQuota?
    private(set) var hints: ApiAgentV2HintsResponse?
    private(set) var limitRetry: LimitRetry?
    private(set) var hasHydratedMessages = false
    /// Whether the server takes problem reports, checked once the thread loads and whenever the chat is shown
    private(set) var isProblemReportAvailable = false

    var error: String? {
        switch errorSource {
        case .agentUnavailable: lang("Agent is unavailable")
        case .failedToLoadChat: lang("Failed to load chat")
        case .run(let code): AgentV2Copy.error(code)
        case nil: nil
        }
    }

    var isInputBlockedByLimit: Bool {
        let now = Date()
        if availability.state == .capacityExhausted,
           let resetAt = availability.resetAt,
           Date(timeIntervalSince1970: resetAt / 1_000) > now {
            return true
        }
        if let userQuota,
           limitRetry?.kind != .userQuota,
           userQuota.remaining == 0,
           AgentV2DateParser.date(userQuota.resetAt) > now {
            return true
        }
        if let resetAt = limitRetry?.resetAt,
           Date(timeIntervalSince1970: resetAt / 1_000) > now {
            return true
        }
        return false
    }

    var hasLimitRetry: Bool {
        limitRetry != nil
    }

    var canRetryLimit: Bool {
        limitRetry != nil && activeRun?.isRunning != true && !isInputBlockedByLimit
    }

    private var revision = 1
    private var conversation = AgentV2ConversationState()
    private var observers: [WeakObserver] = []
    private var startupTask: Task<Void, Never>?
    private var statusRefreshTask: Task<Void, Never>?
    private var problemReportAvailabilityTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var presentationExpiryTasks: [String: Task<Void, Never>] = [:]
    private var hydrationGeneration = 0
    private var actionGeneration = 0
    private var runGeneration = 0
    private var retiredClientRunIds = Set<String>()
    private var retiredRunIds = Set<String>()
    private var terminalErrorSourcesByClientRunId: [String: ErrorSource] = [:]
    private var failedMessageIdsByClientRunId: [String: String] = [:]
    private var limitExpiryTask: Task<Void, Never>?
    private var errorSource: ErrorSource?
    private var isStopped = false
    private var isChatVisible = false
    private var isInBackground = false
    private var isChatActive = false
    private var chatActivityTask: Task<Void, Never>?
    private let hostContextProvider: AgentV2HostContextProvider
    private let initialHostContextRetryDelay: Duration

    init(client: AgentV2Client, initialHostContextRetryDelay: Duration = .seconds(1)) {
        self.client = client
        self.initialHostContextRetryDelay = initialHostContextRetryDelay
        hostContextProvider = AgentV2HostContextProvider(client: client)
        hostContextProvider.isRunActive = { [weak self] in
            self?.activeRun?.isRunning == true
        }
        hostContextProvider.onAuthorityContextInvalidated = { [weak self] in
            self?.handleAuthorityContextInvalidation()
        }
        hostContextProvider.onAuthorityContextPublished = { [weak self] in
            self?.refreshActionPresentations()
        }
        WalletCoreData.add(eventObserver: self)
    }

    deinit {
        startupTask?.cancel()
        statusRefreshTask?.cancel()
        runTask?.cancel()
        limitExpiryTask?.cancel()
        presentationExpiryTasks.values.forEach { $0.cancel() }
    }

    func start() {
        guard !isStopped, startupTask == nil, thread == nil else { return }
        startupTask = Task { [weak self] in
            guard let self else { return }
            for attempt in 0..<Self.initialHostContextMaxAttempts {
                let didPublishHostContext = await self.hostContextProvider.start()
                guard !Task.isCancelled else { return }
                if didPublishHostContext {
                    self.errorSource = nil
                    self.statusRefreshTask = Task { [client] in
                        async let availability: Void = client.loadAvailability()
                        async let userQuota: Void = client.loadUserQuota()
                        _ = await (availability, userQuota)
                    }
                    async let hints: Void = self.loadHints()
                    await self.loadDefaultThread()
                    await hints
                    self.startupTask = nil
                    return
                }

                self.errorSource = .agentUnavailable
                self.notifyObservers()
                guard attempt + 1 < Self.initialHostContextMaxAttempts else {
                    self.startupTask = nil
                    return
                }
                do {
                    try await Task.sleep(for: self.initialHostContextRetryDelay)
                } catch {
                    return
                }
            }
        }
    }

    /// Waits for the initial timeline and suggestions; status probes update independently.
    func waitForInitialLoad() async {
        await startupTask?.value
    }

    /// While the chat is on screen in the foreground, the SDK keeps the server's copy of the wallet snapshot current.
    func setChatVisible(_ isVisible: Bool) {
        isChatVisible = isVisible
        updateChatActivity()
        if isVisible {
            refreshProblemReportAvailability()
        }
    }

    private func refreshProblemReportAvailability() {
        // A loaded thread means consent, which the SDK requires for the check
        guard !isStopped, thread != nil else { return }
        problemReportAvailabilityTask?.cancel()
        problemReportAvailabilityTask = Task { [weak self, client] in
            let isAvailable = await client.problemReportAvailability()
            guard !Task.isCancelled, let self, !self.isStopped,
                  isAvailable != self.isProblemReportAvailable else { return }
            self.isProblemReportAvailable = isAvailable
            self.notifyObservers()
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
        startupTask?.cancel()
        startupTask = nil
        statusRefreshTask?.cancel()
        statusRefreshTask = nil
        problemReportAvailabilityTask?.cancel()
        problemReportAvailabilityTask = nil
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
    }

    func addObserver(_ observer: AgentV2CoordinatorObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
        observers.append(WeakObserver(observer))
    }

    func removeObserver(_ observer: AgentV2CoordinatorObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
    }

    func loadHints() async {
        guard !isStopped else { return }
        hints = try? await client.hints()
        guard !isStopped else { return }
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
            self.errorSource = (error as? ApiAgentV2MutationError).map { .run($0.code) } ?? .failedToLoadChat
            notifyObservers()
        }
    }

    func clearThread() async -> Bool {
        guard !isStopped, let thread, activeRun?.isRunning != true else { return false }
        let generation = runGeneration
        guard let result = try? await client.clearThread(id: thread.id, revision: currentRevision()),
              result.ok,
              let updated = result.value?.thread else { return false }
        guard !isStopped,
              runGeneration == generation,
              (try? bindThread(updated, notify: false)) != nil else { return false }
        invalidateRunLifecycle(clearsActiveRun: true)
        hydrationGeneration += 1
        invalidateActionPresentations(threadId: thread.id)
        conversation.removeAllMessages()
        nextMessageCursor = nil
        hasHydratedMessages = true
        runActivity = nil
        errorSource = nil
        limitRetry = nil
        scheduleLimitExpiryUpdate()
        AgentSearchProvider.shared.invalidateConversationTitle()
        AgentSearchProvider.shared.notifyConversationChanged()
        notifyObservers()
        return true
    }

    func reportProblem(messageId: String?, comment: String?) async -> Bool {
        guard !isStopped, let thread else { return false }
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

    func hydrate(preservingLiveActions: Bool = false) async {
        guard !Task.isCancelled, !isStopped, let threadId = thread?.id else { return }
        hydrationGeneration += 1
        let generation = hydrationGeneration
        do {
            let page = try await client.messages(threadId: threadId, cursor: nil, limit: 50)
            guard !Task.isCancelled,
                  !isStopped,
                  hydrationGeneration == generation,
                  page.thread.id == threadId,
                  page.messages.allSatisfy({ $0.threadId == threadId }) else {
                throw AgentV2NativeContractError.threadBindingMismatch
            }
            invalidateActionPresentations(
                threadId: threadId,
                clearsExistingPresentations: !preservingLiveActions
            )
            try bindThread(page.thread, notify: false)
            let hydratedMessages = page.messages.map(hydratedMessage)
            conversation.replaceMessages(
                hydratedMessages,
                preservingLiveActions: preservingLiveActions
            )
            nextMessageCursor = page.nextCursor
            hasHydratedMessages = true
            if limitRetry == nil {
                errorSource = nil
            }
            refreshActionPresentations(in: messages, threadId: threadId)
            AgentSearchProvider.shared.notifyConversationChanged()
            notifyObservers(.messagesHydrated)
        } catch {
            guard !Task.isCancelled, !isStopped, hydrationGeneration == generation else { return }
            log.error("thread hydration failed error=\(agentFailureSummary(error), .public)")
            self.errorSource = (error as? ApiAgentV2MutationError).map { .run($0.code) } ?? .failedToLoadChat
            notifyObservers()
        }
    }

    @discardableResult
    func loadOlderMessages() async -> Bool {
        guard !isStopped, let threadId = thread?.id, let cursor = nextMessageCursor else { return false }
        let generation = hydrationGeneration
        guard let page = try? await client.messages(threadId: threadId, cursor: cursor, limit: 50) else { return false }
        guard !isStopped,
              hydrationGeneration == generation,
              nextMessageCursor == cursor,
              page.thread.id == threadId,
              page.messages.allSatisfy({ $0.threadId == threadId }) else { return false }
        guard (try? bindThread(page.thread, notify: false)) != nil else { return false }
        let hydratedMessages = page.messages.map(hydratedMessage)
        conversation.prependMessages(hydratedMessages)
        nextMessageCursor = page.nextCursor
        refreshActionPresentations(in: hydratedMessages, threadId: threadId)
        AgentSearchProvider.shared.notifyConversationChanged()
        notifyObservers()
        return true
    }

    func send(
        input: ApiAgentV2RunInput,
        entryPoint: ApiAgentV2EntryPoint? = .agentTab,
        followup: ApiAgentV2RunCommand.FollowUpReference? = nil,
        visibleText: String? = nil,
        localInputMessageId: String? = nil
    ) {
        guard !isStopped,
              let threadId = thread?.id,
              activeRun?.isRunning != true,
              !isInputBlockedByLimit else { return }
        let generation = beginRunLifecycle()
        switch input {
        case .edit:
            invalidateActionPresentations(threadId: threadId)
            AgentSearchProvider.shared.invalidateConversationTitle()
        case .regenerate:
            invalidateActionPresentations(threadId: threadId)
        case .append:
            break
        }
        limitRetry = nil
        scheduleLimitExpiryUpdate()
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
        activeRun = RunState(
            generation: generation,
            clientRunId: nil,
            runId: nil,
            threadId: threadId,
            localInputMessageId: optimisticInputMessageId,
            isRunning: true
        )
        runActivity = nil
        errorSource = nil
        notifyObservers()

        let command = ApiAgentV2RunCommand(
            threadId: threadId,
            expectedThreadRevision: currentRevision(),
            input: input,
            entryPoint: entryPoint,
            followupOf: followup
        )
        runTask = Task { [weak self] in
            guard let self else { return }
            let terminalState: ApiAgentV2RunResultState
            let clientRunId: String?
            do {
                let result = try await self.client.startRun(command)
                guard !Task.isCancelled,
                      self.bindRunResult(result, generation: generation, threadId: threadId) else { return }
                let localInputMessageId = self.activeRun?.localInputMessageId
                let isRunAdmitted = self.activeRun?.runId != nil
                if isRunAdmitted,
                   self.conversation.reconcileOptimisticInputMessage(
                    localId: localInputMessageId,
                    canonicalId: result.inputMessageId
                ), let localInputMessageId, let canonicalInputMessageId = result.inputMessageId {
                    self.notifyObservers(.messageIdReconciled(
                        localId: localInputMessageId,
                        canonicalId: canonicalInputMessageId
                    ))
                }
                terminalState = result.state
                clientRunId = result.clientRunId
            } catch {
                guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
                log.error("run start failed error=\(agentFailureSummary(error), .public)")
                let activeClientRunId = self.activeRun?.clientRunId
                await self.hydrate()
                guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
                self.settleRun(
                    generation: generation,
                    clientRunId: activeClientRunId,
                    outcome: .failed
                )
                return
            }
            await self.hydrate(preservingLiveActions: true)
            guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
            self.settleRun(
                generation: generation,
                clientRunId: clientRunId,
                outcome: terminalState
            )
        }
    }

    func cancelRun() {
        guard let runId = activeRun?.runId else { return }
        Task { [client] in await client.cancelRun(runId) }
    }

    func retryLimit() {
        guard !isStopped, canRetryLimit, let retry = limitRetry else { return }
        let generation = beginRunLifecycle(reusingClientRunId: retry.clientRunId)
        activeRun = RunState(
            generation: generation,
            clientRunId: retry.clientRunId,
            runId: nil,
            threadId: retry.threadId,
            localInputMessageId: nil,
            isRunning: true
        )
        scheduleLimitExpiryUpdate()
        notifyObservers()

        runTask = Task { [weak self] in
            guard let self else { return }
            let terminalState: ApiAgentV2RunResultState
            let clientRunId: String?
            do {
                guard let result = try await self.client.retryRun(clientRunId: retry.clientRunId) else {
                    throw AgentV2NativeContractError.retryUnavailable
                }
                guard !Task.isCancelled,
                      self.bindRunResult(result, generation: generation, threadId: retry.threadId) else { return }
                if result.state == .completed || result.state == .cancelled,
                   self.limitRetry == retry {
                    self.limitRetry = nil
                }
                terminalState = result.state
                clientRunId = result.clientRunId
            } catch {
                guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
                log.error("run retry failed error=\(agentFailureSummary(error), .public)")
                let activeClientRunId = self.activeRun?.clientRunId
                await self.hydrate()
                guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
                self.settleRun(
                    generation: generation,
                    clientRunId: activeClientRunId,
                    outcome: .failed
                )
                return
            }
            await self.hydrate(preservingLiveActions: true)
            guard !Task.isCancelled, self.isCurrentRun(generation) else { return }
            self.settleRun(
                generation: generation,
                clientRunId: clientRunId,
                outcome: terminalState
            )
        }
    }

    func resolveAction(messageId: String, actionId: String) async -> ResolvedAction? {
        guard !isStopped,
              hostContextProvider.isAuthorityContextCurrent,
              let accountId = hostContextProvider.publishedActiveAccountId,
              AccountStore.account?.id == accountId else { return nil }
        let generation = actionGeneration
        guard let value = try? await client.resolveAction(messageId: messageId, actionId: actionId) else { return nil }
        guard !isStopped,
              hostContextProvider.isAuthorityContextCurrent,
              actionGeneration == generation,
              hostContextProvider.publishedActiveAccountId == accountId,
              AccountStore.account?.id == accountId else { return nil }
        return ResolvedAction(value: value, accountId: accountId)
    }

    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .agentV2(let update):
            handle(update)
        case .applicationDidEnterBackground:
            isInBackground = true
            updateChatActivity()
        case .applicationWillEnterForeground:
            isInBackground = false
            updateChatActivity()
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
            runActivity = nil
            let localInputMessageId: String?
            if var run = activeRun,
               run.generation == runGeneration,
               run.isRunning {
                guard run.threadId == bound.threadId,
                      run.clientRunId == nil || run.clientRunId == bound.clientRunId,
                      run.runId == nil || run.runId == bound.runId else { return }
                run.clientRunId = bound.clientRunId
                run.runId = bound.runId
                run.isRunning = true
                localInputMessageId = run.localInputMessageId
                activeRun = run
            } else {
                let generation = beginRunLifecycle(reusingClientRunId: bound.clientRunId)
                localInputMessageId = nil
                activeRun = RunState(
                    generation: generation,
                    clientRunId: bound.clientRunId,
                    runId: bound.runId,
                    threadId: bound.threadId,
                    localInputMessageId: nil,
                    isRunning: true
                )
            }
            revision = threadRevision
            let didReconcileInputMessage = conversation.reconcileOptimisticInputMessage(
                localId: localInputMessageId,
                canonicalId: inputMessageId
            )
            if didReconcileInputMessage, let localInputMessageId, let inputMessageId {
                change = .messageIdReconciled(localId: localInputMessageId, canonicalId: inputMessageId)
            } else {
                change = .reload
            }
        case .messageStarted(let bound, let messageId, let contentKind, let responseLanguage):
            guard acceptPayloadUpdate(bound) else { return }
            conversation.ensureAssistantMessage(
                threadId: bound.threadId,
                messageId: messageId,
                contentKind: contentKind,
                responseLanguage: responseLanguage
            )
            change = .reload
        case .textDelta(let bound, let messageId, let delta):
            guard acceptPayloadUpdate(bound) else { return }
            runActivity = nil
            conversation.ensureAssistantMessage(
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
            conversation.ensureAssistantMessage(
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
        case .messageCompleted(let bound, let messageId, _):
            guard acceptPayloadUpdate(bound) else { return }
            runActivity = nil
            conversation.completeMessage(id: messageId)
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
            conversation.ensureAssistantMessage(
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
            guard let target,
                  isBoundThread(target),
                  let disposition = matchRunUpdate(
                    clientRunId: clientRunId,
                    runId: bound?.runId,
                    threadId: target
                  ) else { return }
            terminalErrorSourcesByClientRunId[clientRunId] = .run(code)
            limitRetry = makeLimitRetry(
                bound: bound,
                clientRunId: clientRunId,
                threadId: target,
                code: code,
                retryable: retryable,
                resetAt: resetAt
            )
            scheduleLimitExpiryUpdate()
            // A failed answer shows its own error; the status row shows a failure without one and a limit retry.
            if limitRetry == nil,
               let messageId,
               conversation.failMessage(id: messageId, error: ApiAgentV2MessageError(code: code, retryable: retryable)) {
                failedMessageIdsByClientRunId[clientRunId] = messageId
            } else {
                errorSource = .run(code)
            }
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
            invalidateAuthorityBoundState(threadId: threadId)
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
            change = .reload
        }
        notifyObservers(change)
    }

    private func hydratedMessage(_ persisted: ApiAgentV2PersistedMessage) -> AgentV2NativeMessage {
        AgentV2NativeMessage(persisted: persisted)
    }

    private func handleAuthorityContextInvalidation() {
        guard !isStopped else { return }
        invalidateAuthorityBoundState(threadId: thread?.id)
        notifyObservers()
    }

    private func invalidateAuthorityBoundState(threadId: String?) {
        invalidateWalletContextBoundState(threadId: threadId)
        if limitRetry != nil {
            invalidateRunLifecycle(clearsActiveRun: false)
        }
        limitRetry = nil
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
        guard hostContextProvider.isAuthorityContextCurrent else { return }
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
        return LimitRetry(
            kind: kind,
            clientRunId: clientRunId,
            threadId: threadId,
            resetAt: resetAt
        )
    }

    private func beginRunLifecycle(reusingClientRunId: String? = nil) -> Int {
        runTask?.cancel()
        runTask = nil
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
              run.clientRunId == nil || run.clientRunId == result.clientRunId,
              run.runId == nil || result.runId == nil || run.runId == result.runId else { return false }
        run.clientRunId = result.clientRunId
        if let runId = result.runId {
            run.runId = runId
        }
        activeRun = run
        return true
    }

    private func acceptPayloadUpdate(_ bound: ApiAgentV2ClientUpdate.Bound) -> Bool {
        guard isBoundThread(bound.threadId),
              !retiredClientRunIds.contains(bound.clientRunId),
              !retiredRunIds.contains(bound.runId) else { return false }
        guard var run = activeRun else { return true }
        guard run.generation == runGeneration,
              run.isRunning,
              run.threadId == bound.threadId,
              run.clientRunId == nil || run.clientRunId == bound.clientRunId,
              run.runId == nil || run.runId == bound.runId else { return false }
        run.clientRunId = bound.clientRunId
        run.runId = bound.runId
        activeRun = run
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
        if let activeClientRunId = run.clientRunId {
            guard activeClientRunId == clientRunId,
                  run.runId == nil || runId == nil || run.runId == runId else { return nil }
            return retiredClientRunIds.contains(clientRunId) ? .retiredActive : .active
        }
        guard run.isRunning, !retiredClientRunIds.contains(clientRunId) else { return nil }
        run.clientRunId = clientRunId
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
        if !isShownByFailedMessage {
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
        let resetDates = [
            availability.resetAt.map { Date(timeIntervalSince1970: $0 / 1_000) },
            userQuota.map { AgentV2DateParser.date($0.resetAt) },
            limitRetry?.resetAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
        ].compactMap { $0 }.filter { $0 > now }
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
        self.thread = thread
        revision = thread.revision
        if notify { notifyObservers() }
    }

    private func isBoundThread(_ threadId: String) -> Bool {
        thread?.id == threadId
    }

    private func notifyObservers(_ change: AgentV2CoordinatorChange = .reload) {
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
