import Foundation
import UIComponents
import WalletContext
import WalletCore

@MainActor
final class AgentV2Model: AgentModel {
    private let coordinator: AgentV2Coordinator
    private var didStop = false
    var onStop: (() -> Void)?

    var isReadyForPresentation: Bool {
        !didStop && coordinator.hasHydratedMessages && coordinator.error == nil
    }

    init(client: AgentV2Client) {
        let coordinator = AgentV2Coordinator(client: client)
        self.coordinator = coordinator
        super.init(backend: AgentV2Backend(coordinator: coordinator))
        coordinator.start()
    }

    func waitForInitialLoad() async {
        await coordinator.waitForInitialLoad()
    }

    override func stop() {
        guard !didStop else { return }
        didStop = true
        super.stop()
        onStop?()
        onStop = nil
    }
}

@MainActor
private final class AgentV2Backend: AgentBackend, AgentV2CoordinatorObserver {
    private struct PresentedMessage {
        let key: String
        let message: AgentMessage
        let replacedItemID: AgentItemID?
    }

    private struct PendingEdit {
        var targetNativeID: String
        var isAdmitted: Bool
    }

    private enum Interaction {
        case action(messageID: String, action: AgentV2NativeAction)
        case followup(messageID: String, followup: ApiAgentV2FollowUp)
        case retryLimit
    }

    var canSendMessages: Bool {
        isTimelineReady
            && coordinator.activeRun?.isRunning != true
            && !coordinator.isInputBlockedByLimit
            && !isClearing
            && !isLoadingOlderMessages
    }

    var canClearConversation: Bool {
        isTimelineReady
            && coordinator.thread != nil
            && coordinator.activeRun?.isRunning != true
            && !isClearing
            && !isLoadingOlderMessages
    }

    var shouldConfirmConversationClear: Bool {
        true
    }

    var canReportProblem: Bool {
        isTimelineReady
            && coordinator.isProblemReportAvailable
            && coordinator.thread != nil
            && !coordinator.messages.isEmpty
            && !isClearing
    }

    var typingIndicatorAccessibilityLabel: String? {
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
    private var ignoredNativeIDs = Set<String>()
    private var editedTextByNativeID: [String: String] = [:]
    private var pendingEdit: PendingEdit?
    private var pendingTypingIndicatorID: AgentItemID?
    private var statusMessageID: AgentItemID?
    private var lastHints: [AgentHint] = []
    private var hintsAnimated = false
    private var didPresentInitialTimeline = false
    private var isClearing = false
    private var isLoadingOlderMessages = false
    private var didStop = false
    private var lastSettledRunGeneration: Int?

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
        guard coordinator.hints == nil else { return }
        Task { [weak self] in
            await self?.coordinator.loadHints()
        }
    }

    func prepareForEditing(_ editContext: AgentBackendEditContext) {
        guard let nativeID = nativeIDByUIID[editContext.messageID],
              let index = coordinator.messages.firstIndex(where: { $0.id == nativeID }) else { return }
        ignoredNativeIDs = Set(coordinator.messages.suffix(from: index + 1).map(\.id))
        pendingEdit = PendingEdit(targetNativeID: nativeID, isAdmitted: false)
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
            editedTextByNativeID[targetID] = text
            pendingEdit = PendingEdit(targetNativeID: targetID, isAdmitted: false)
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
                entryPoint = .agentTab
            case .entryPoint(let sourceEntryPoint):
                entryPoint = sourceEntryPoint
            case .hint(let id, let catalogVersion):
                entryPoint = .emptyState(hintId: id, catalogVersion: catalogVersion)
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

    func clearConversation(completion: @escaping (Bool) -> Void) {
        guard canClearConversation else {
            completion(false)
            return
        }
        isClearing = true
        notifyStateChanged()
        Task { [weak self] in
            guard let self else { return }
            let didClear = await self.coordinator.clearThread()
            guard !self.didStop else {
                completion(false)
                return
            }
            self.isClearing = false
            if didClear {
                self.resetPresentationState()
            } else {
                AppActions.showError(error: DisplayError(text: lang("Agent is unavailable")))
            }
            self.notifyStateChanged()
            completion(didClear)
        }
    }

    func reportProblem(messageID: AgentItemID?, comment: String?) async -> Bool {
        guard canReportProblem else { return false }
        // The status row has no stored message, so it reports the conversation. An answer that lost its stored
        // message is not reported as the conversation in its place.
        var nativeMessageID: String?
        if let messageID, messageID != statusMessageID {
            guard let nativeID = nativeIDByUIID[messageID] else { return false }
            nativeMessageID = nativeID
        }
        return await coordinator.reportProblem(messageId: nativeMessageID, comment: comment)
    }

    func loadOlderMessages() async -> Bool {
        guard didPresentInitialTimeline,
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
        }
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
        let shouldForceTimelineReplacement = rollbackRejectedEditIfNeeded(outcome: terminalOutcome)
        let shouldRebuildTimelineForTimestampChanges = change == .messagesHydrated
        synchronizeHints()
        if !(isClearing && coordinator.messages.isEmpty) {
            synchronizeMessages(
                forceTimelineReplacement: shouldForceTimelineReplacement,
                shouldRebuildTimelineForTimestampChanges: shouldRebuildTimelineForTimestampChanges
            )
        }
        if terminalOutcome != nil {
            removeOrphanedTypingIndicatorIfNeeded()
        }
        notifyStateChanged()
    }

    private var isTimelineReady: Bool {
        coordinator.hasHydratedMessages
    }

    private func synchronizeHints(force: Bool = false) {
        guard let response = coordinator.hints else { return }
        let hints = response.items.map { item in
            let copy = AgentV2Copy.hint(item.id)
            return AgentHint(
                id: item.id.rawValue,
                title: copy.title,
                subtitle: copy.prompt,
                prompt: copy.prompt,
                catalogVersion: response.catalogVersion
            )
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
        guard let context, isTimelineReady || coordinator.error != nil else { return }
        pruneEditingState()

        var nextInteractions: [AgentItemID: [String: Interaction]] = [:]
        var desired = coordinator.messages
            .filter { !ignoredNativeIDs.contains($0.id) }
            .compactMap { nativeMessage in
                presentedMessage(
                    nativeMessage,
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

        if forceTimelineReplacement || hasTimestampChanges || !didPresentInitialTimeline {
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
                    if forceMessageUpdates || !hasSamePresentation(existing, item.message) {
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
                  forceMessageUpdates || !hasSamePresentation(existing, item.message) else { continue }
            context.updateMessage(item.message, animated: false, scrollToBottom: false)
        }
        presentedKeys = desiredKeys
        if !desiredKeys.contains(statusPresentationKey) {
            statusMessageID = nil
        }
    }

    private func presentedMessage(
        _ nativeMessage: AgentV2NativeMessage,
        interactions: inout [AgentItemID: [String: Interaction]]
    ) -> PresentedMessage? {
        let bubble = AgentV2MessagePresentation.bubble(for: nativeMessage)
        let semanticContent = bubble == nil ? nativeMessage.semanticContent : nil
        var text = bubble?.text ?? ""
        let supplementaryErrorText = withMessageLanguage(nativeMessage.responseLanguage) {
            nativeMessage.error.map { AgentV2Copy.error($0.code) }
        }
        guard nativeMessage.role == .user
            || !text.isEmpty
            || semanticContent != nil
            || supplementaryErrorText != nil
            || !nativeMessage.actions.isEmpty
            || !nativeMessage.followups.isEmpty else { return nil }

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

        if let editedText = editedTextByNativeID[nativeMessage.id], nativeMessage.role == .user {
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
            renderingPolicy: .agentV2Safe,
            supplementaryErrorText: supplementaryErrorText,
            timestamp: nativeMessage.createdAt
        )
        if !nativeMessage.tableReferences.isEmpty {
            message.answerBlocks = AgentV2AnswerTables.blocks(
                nativeMessage.content.text,
                tables: nativeMessage.tables,
                references: nativeMessage.tableReferences,
                links: nativeMessage.links
            )
        }
        return PresentedMessage(
            key: key,
            message: message,
            replacedItemID: replacedItemID
        )
    }

    private func statusMessage(
        interactions: inout [AgentItemID: [String: Interaction]]
    ) -> PresentedMessage? {
        guard let error = coordinator.error else { return nil }
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
        }
        return PresentedMessage(
            key: statusPresentationKey,
            message: AgentMessage(
                id: messageID,
                role: .assistant,
                text: error,
                isStreaming: false,
                controls: controls,
                renderingPolicy: .agentV2Safe
            ),
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
                let isEnabled = action.kind != .send
                    || action.labelCode == .openSend
                    || action.presentation?.kind == .send && action.presentation?.status == .active
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
            for followup in nativeMessage.followups {
                let controlID = "followup:\(followup.id)"
                controls.append(AgentMessageControl(
                    id: controlID,
                    title: followup.text,
                    isEnabled: canSendMessages,
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

    private func reconcileMessageID(localID: String, canonicalID: String) {
        guard localID != canonicalID else { return }
        if var pendingEdit, pendingEdit.targetNativeID == localID {
            pendingEdit.targetNativeID = canonicalID
            pendingEdit.isAdmitted = true
            self.pendingEdit = pendingEdit
        }
        if let editedText = editedTextByNativeID.removeValue(forKey: localID) {
            editedTextByNativeID[canonicalID] = editedText
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

    private func rollbackRejectedEditIfNeeded(outcome: ApiAgentV2RunResultState?) -> Bool {
        guard let outcome, outcome != .completed,
              let pendingEdit, !pendingEdit.isAdmitted else { return false }
        ignoredNativeIDs.removeAll()
        editedTextByNativeID.removeAll()
        self.pendingEdit = nil
        return true
    }

    private func removeOrphanedTypingIndicatorIfNeeded() {
        guard let pendingTypingIndicatorID else { return }
        self.pendingTypingIndicatorID = nil
        context?.removeItem(id: pendingTypingIndicatorID, animated: false)
    }

    private func bind(nativeID: String, to uiID: AgentItemID) {
        uiIDByNativeID[nativeID] = uiID
        nativeIDByUIID[uiID] = nativeID
    }

    private func pruneEditingState() {
        let currentIDs = Set(coordinator.messages.map(\.id))
        if ignoredNativeIDs.isDisjoint(with: currentIDs) {
            ignoredNativeIDs.removeAll()
        }
        editedTextByNativeID = editedTextByNativeID.filter { nativeID, text in
            guard let message = coordinator.messages.first(where: { $0.id == nativeID }) else { return false }
            return message.text != text
        }
        if ignoredNativeIDs.isEmpty && editedTextByNativeID.isEmpty {
            pendingEdit = nil
        }
    }

    private func resetPresentationState() {
        uiIDByNativeID.removeAll()
        nativeIDByUIID.removeAll()
        presentedKeys.removeAll()
        interactionsByMessageID.removeAll()
        ignoredNativeIDs.removeAll()
        editedTextByNativeID.removeAll()
        pendingEdit = nil
        pendingTypingIndicatorID = nil
        statusMessageID = nil
        didPresentInitialTimeline = true
    }

    private func notifyStateChanged() {
        context?.notifyStateChanged()
    }

    private func uiID(forPresentationKey key: String) -> AgentItemID? {
        if key == statusPresentationKey {
            return statusMessageID
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
    }

    private let messagePresentationPrefix = "message:"
    private let statusPresentationKey = "status"
}
