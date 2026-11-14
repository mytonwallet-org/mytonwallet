import Foundation
import WalletContext
import WalletCore

@MainActor
protocol AgentModelDelegate: AnyObject {
    func agentModelDidReloadTimeline(animated: Bool, reconfigureItemIDs: [AgentItemID])
    func agentModelDidUpdateItems(_ ids: [AgentItemID], animated: Bool, scrollToBottom: Bool)
    func agentModelDidUpdateHints(animated: Bool)
    func agentModelDidUpdateState()
    func agentModelWillRevealSentUserMessage(_ userMessageID: AgentItemID, then completion: @escaping () -> Void)
    /// The typing row kept on screen after its run ended is about to leave the chat, once `completion` runs
    func agentModelWillRemoveHeldTypingIndicator(_ id: AgentItemID, then completion: @escaping () -> Void)
}

extension AgentModelDelegate {
    func agentModelDidUpdateState() {}

    func agentModelWillRevealSentUserMessage(_ userMessageID: AgentItemID, then completion: @escaping () -> Void) {
        completion()
    }

    func agentModelWillRemoveHeldTypingIndicator(_ id: AgentItemID, then completion: @escaping () -> Void) {
        completion()
    }
}

@MainActor
class BaseAgentModel {
    private enum Metrics {
        static let dateHeaderGap: TimeInterval = 10 * 60
    }

    weak var delegate: AgentModelDelegate?
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            backend.setActive(isActive)
        }
    }

    private var orderedItemIDs: [AgentItemID] = []
    private var itemsByID: [AgentItemID: AgentTimelineItem] = [:]
    private(set) var userMessageRevision = 0
    /// How many questions the chat has taken, edits included, for its screen to tell whether an action sent one
    private(set) var sentQuestionCount = 0
    private var availableHints: [AgentHint] = []
    private var deferredTypingIndicator: AgentTimelineItem?
    /// The typing row a Stop while the Agent thought keeps on screen for a moment, for its top's knock
    private(set) var heldTypingIndicatorID: AgentItemID?
    /// The run's end took the held typing row out, which it leaves once the hold ends, animated as the run's end had it
    private var isHeldTypingIndicatorRemoved = false
    private var isHeldTypingIndicatorRemovalAnimated = false
    private var typingIndicatorHold: Task<Void, Never>?
    private(set) var pendingRevealUserMessageID: AgentItemID?
    /// The question that waited at the chat's end and goes now, while the chat brings it up
    private(set) var revealingWaitingMessageID: AgentItemID?
    /// The question being added that waits for the answer being written
    private var appendingWaitingMessageID: AgentItemID?
    private var isAwaitingTypingIndicatorReveal = false
    private let backend: AgentBackend
    private lazy var backendContext = AgentBackendContext(
        replaceTimelineHandler: { [weak self] items, animated, reconfigureItemIDs in
            self?.replaceTimeline(
                with: items,
                animated: animated,
                reconfigureItemIDs: reconfigureItemIDs
            )
        },
        setHintsHandler: { [weak self] hints, animated in
            self?.setHints(hints, animated: animated)
        },
        replaceItemHandler: { [weak self] id, item, animated in
            self?.replaceItem(id: id, with: item, animated: animated)
        },
        appendHandler: { [weak self] item, animated in
            self?.append(item, animated: animated)
        },
        removeHandler: { [weak self] id, animated in
            self?.removeItem(id: id, animated: animated)
        },
        updateMessageHandler: { [weak self] message, animated, scrollToBottom in
            self?.updateMessage(message, animated: animated, scrollToBottom: scrollToBottom)
        },
        messageProvider: { [weak self] id in
            self?.message(for: id)
        },
        itemIDsProvider: { [weak self] in
            self?.orderedItemIDs ?? []
        },
        stateDidChangeHandler: { [weak self] in
            self?.delegate?.agentModelDidUpdateState()
        },
        sendMessageHandler: { [weak self] text, source in
            self?.send(text: text, source: source)
        },
        revealSentMessageHandler: { [weak self] id, send in
            guard let self else { return send() }
            revealingWaitingMessageID = id
            beginTypingIndicatorReveal(for: id)
            send()
            // With no typing row to wait for, the chat brings the question up at once
            if isAwaitingTypingIndicatorReveal {
                cancelPendingTypingIndicatorReveal()
                delegate?.agentModelWillRevealSentUserMessage(id) {}
            }
            revealingWaitingMessageID = nil
        }
    )

    init(backend: AgentBackend) {
        self.backend = backend
        backend.attach(to: backendContext)
        replaceTimeline(with: [], animated: false)
        backend.loadHints(animated: false)
    }

    var itemIDs: [AgentItemID] {
        orderedItemIDs
    }

    var canClearChat: Bool {
        backend.canClearConversation
    }

    var shouldConfirmChatClear: Bool {
        backend.shouldConfirmConversationClear
    }

    var canReportProblem: Bool {
        backend.canReportProblem
    }

    var typingIndicatorStatusText: String? {
        backend.typingIndicatorStatusText
    }

    var typingIndicatorAccessibilityLabel: String? {
        backend.typingIndicatorAccessibilityLabel
    }

    var accessibilityStatus: String? {
        backend.accessibilityStatus
    }

    var supportState: AgentSupportState {
        backend.supportState
    }

    /// Support has the chat: it waits for an operator or an operator is in it
    var isSupportActive: Bool {
        supportState.isActive
    }

    var isSupportRequestVisible: Bool {
        backend.isSupportRequestVisible
    }

    var canRequestSupport: Bool {
        backend.canRequestSupport
    }

    /// Sends the request for a support operator as the user's message, when the chat can; returns whether it went
    @discardableResult
    func requestSupport(source: ApiAgentV2EntryPoint.SupportRequestSource) -> Bool {
        guard backend.canRequestSupport else { return false }
        send(text: lang("$agent_support_request_message"), source: .supportRequest(source))
        return true
    }

    var areHintsVisible: Bool {
        !visibleHints.isEmpty
    }

    var visibleHints: [AgentHint] {
        hasUserMessages ? [] : availableHints
    }

    func item(for id: AgentItemID) -> AgentTimelineItem? {
        guard case .message(var message) = itemsByID[id], id != followupMessageID else {
            return itemsByID[id]
        }
        message.controls.removeAll { $0.kind == .followup }
        return .message(message)
    }

    private var followupMessageID: AgentItemID? {
        for id in orderedItemIDs.reversed() {
            guard case .message(let message) = itemsByID[id], message.role != .system else { continue }
            return message.role == .assistant && message.author == .agent ? id : nil
        }
        return nil
    }

    /// A question can be sent with `draftText`, now or to wait for the answer being written; an edit can't wait
    func canSendMessage(draftText: String?, isEditing: Bool = false) -> Bool {
        (isEditing ? backend.canSendMessages : backend.canAcceptMessages) && Self.normalizedText(from: draftText) != nil
    }

    /// The rows that stay at the chat's end, after the answer being written: the questions that wait for it, and those
    /// a wallet switch failed there with their failure
    var trailingItemIDs: [AgentItemID] {
        backend.trailingItemIDs + (appendingWaitingMessageID.map { [$0] } ?? [])
    }

    func canEditMessage(_ messageID: AgentItemID) -> Bool {
        guard case .message(let message)? = itemsByID[messageID],
              message.role == .user, !message.isEditingDisabled else { return false }
        return backend.canEditMessage(messageID: messageID)
    }

    var canStopAnswer: Bool {
        backend.canStopAnswer
    }

    func stopAnswer() {
        guard backend.canStopAnswer else { return }
        backend.stopAnswer()
    }

    /// Keeps the typing row on screen for `duration`, with its status, as its run ends, and then lets it go as the run's
    /// end had it go. Anything else the chat shows meanwhile, a new question first, lets it go at once.
    func holdTypingIndicator(for duration: TimeInterval) {
        releaseTypingIndicator()
        guard let id = orderedItemIDs.last(where: { itemID in
            if case .typingIndicator? = itemsByID[itemID] { return true }
            return false
        }) else { return }
        heldTypingIndicatorID = id
        // The chat takes the row as no longer thinking at once
        delegate?.agentModelDidUpdateState()
        typingIndicatorHold = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.endTypingIndicatorHold()
        }
    }

    /// The hold has run its time: the row leaves as the chat has rows leave, when the run's end took it out
    private func endTypingIndicatorHold() {
        typingIndicatorHold = nil
        guard let id = heldTypingIndicatorID, isHeldTypingIndicatorRemoved, let delegate else {
            releaseTypingIndicator()
            return
        }
        delegate.agentModelWillRemoveHeldTypingIndicator(id) { [weak self] in
            guard let self, heldTypingIndicatorID == id else { return }
            isHeldTypingIndicatorRemovalAnimated = true
            releaseTypingIndicator()
        }
    }

    /// Lets the held typing row go: out of the chat, when the run's end took it out meanwhile
    private func releaseTypingIndicator() {
        typingIndicatorHold?.cancel()
        typingIndicatorHold = nil
        guard let id = heldTypingIndicatorID else { return }
        heldTypingIndicatorID = nil
        let isRemoved = isHeldTypingIndicatorRemoved
        isHeldTypingIndicatorRemoved = false
        if isRemoved {
            removeItem(id: id, animated: isHeldTypingIndicatorRemovalAnimated)
        }
        delegate?.agentModelDidUpdateState()
    }

    func refreshDerivedSystemMessages(animated: Bool = false) {
        setTimeline(baseTimelineItems, animated: animated)
        backend.refreshPresentation()
    }

    func send(
        text rawText: String?,
        editingMessageID: AgentItemID? = nil,
        source: AgentBackendSendSource = .composer
    ) {
        guard let text = Self.normalizedText(from: rawText) else { return }
        if let editingMessageID,
           case .message(let message)? = itemsByID[editingMessageID], message.isEditingDisabled { return }
        releaseTypingIndicator()

        if let editingMessageID,
           let editContext = makeEditContext(for: editingMessageID) {
            // An edit replaces what follows the message, so it can't wait for the answer being written
            guard backend.canSendMessages else { return }
            sentQuestionCount += 1
            backend.prepareForEditing(editContext)
            applyEditedMessage(text, id: editingMessageID)
            beginTypingIndicatorReveal(for: editingMessageID)
            backend.didSendUserMessage(
                text,
                userMessageID: editingMessageID,
                source: source,
                editContext: editContext
            )
            cancelPendingTypingIndicatorReveal()
            return
        }

        let message = AgentMessage(
            role: .user,
            text: text,
            isStreaming: false
        )
        sentQuestionCount += 1
        // A question sent while an answer is written, or before its discussion's thread exists, waits at the chat's end
        if !source.isSupportRequest, backend.queuesNextQuestion {
            appendingWaitingMessageID = message.id
        }
        beginTypingIndicatorReveal(for: message.id)
        appendMessage(message, animated: true)
        appendingWaitingMessageID = nil
        backend.didSendUserMessage(
            text,
            userMessageID: message.id,
            source: source,
            editContext: nil
        )
        cancelPendingTypingIndicatorReveal()
    }

    func clearChat(animated: Bool = true) {
        guard backend.canClearConversation else { return }
        backend.clearConversation()
        replaceTimeline(with: [], animated: animated)
        backend.loadHints(animated: animated)
    }

    func reportProblem(messageID: AgentItemID?, comment: String?) async -> Bool {
        await backend.reportProblem(messageID: messageID, comment: comment)
    }

    func rateMessage(messageID: AgentItemID, feedback: ApiAgentV2AnswerFeedback?) async -> Bool {
        await backend.rateMessage(messageID: messageID, feedback: feedback)
    }

    func loadOlderMessages() async -> Bool {
        await backend.loadOlderMessages()
    }

    var isLoadingOlderMessages: Bool {
        backend.isLoadingOlderMessages
    }

    func canRegenerateMessage(_ messageID: AgentItemID) -> Bool {
        backend.canRegenerateMessage(messageID: messageID)
    }

    /// The rows `regenerateMessage(_:)` takes out of the chat, in timeline order: the answer, the messages after it and
    /// the date lines they leave with nothing under them
    func getItemIDsRemovedByRegenerating(_ messageID: AgentItemID) -> [AgentItemID] {
        guard backend.canRegenerateMessage(messageID: messageID) else { return [] }
        return getItemIDsLeavingTimeline(removing: Set(backend.getItemIDsRemovedByRegenerating(messageID: messageID)))
    }

    func regenerateMessage(_ messageID: AgentItemID) {
        guard backend.canRegenerateMessage(messageID: messageID) else { return }
        backend.regenerateMessage(messageID: messageID)
    }

    func performControl(messageID: AgentItemID, controlID: String) {
        guard case .message(let message) = item(for: messageID),
              message.controls.contains(where: { $0.id == controlID && $0.isEnabled }) else { return }
        backend.performControl(messageID: messageID, controlID: controlID)
    }

    func stop() {
        backend.stop()
    }

    private func append(_ item: AgentTimelineItem, animated: Bool) {
        releaseTypingIndicator()
        if case .typingIndicator = item, isAwaitingTypingIndicatorReveal {
            deferTypingIndicator(item, animated: animated)
            return
        }
        if case .message(let message) = item {
            appendMessage(message, animated: animated)
            return
        }
        appendDirectly(item, animated: animated)
    }

    private func beginTypingIndicatorReveal(for userMessageID: AgentItemID) {
        isAwaitingTypingIndicatorReveal = true
        pendingRevealUserMessageID = userMessageID
    }

    private func cancelPendingTypingIndicatorReveal() {
        isAwaitingTypingIndicatorReveal = false
        pendingRevealUserMessageID = nil
    }

    private func resetPendingTypingIndicator() {
        cancelPendingTypingIndicatorReveal()
        deferredTypingIndicator = nil
    }

    private func deferTypingIndicator(_ item: AgentTimelineItem, animated: Bool) {
        isAwaitingTypingIndicatorReveal = false
        let userMessageID = pendingRevealUserMessageID
        pendingRevealUserMessageID = nil
        deferredTypingIndicator = item

        guard let userMessageID, let delegate else {
            flushDeferredTypingIndicator(animated: animated)
            return
        }
        delegate.agentModelWillRevealSentUserMessage(userMessageID) { [weak self] in
            self?.flushDeferredTypingIndicator(animated: animated)
        }
    }

    private func flushDeferredTypingIndicator(animated: Bool) {
        guard let item = deferredTypingIndicator else { return }
        deferredTypingIndicator = nil
        appendDirectly(item, animated: animated)
    }

    private func flushDeferredTypingIndicatorIfNeeded(for id: AgentItemID) {
        guard deferredTypingIndicator?.id == id else { return }
        flushDeferredTypingIndicator(animated: false)
    }

    private func appendMessage(_ message: AgentMessage, animated: Bool) {
        if message.isDateTimeSystemMessage {
            appendDirectly(.message(message), animated: animated)
            return
        }

        let previousFollowupMessageID = followupMessageID
        var insertedItems: [AgentTimelineItem] = []
        if shouldInsertDateMessage(before: message.timestamp) {
            insertedItems.append(.message(makeDateTimeSystemMessage(for: message.timestamp)))
        }
        insertedItems.append(.message(message))

        for item in insertedItems {
            orderedItemIDs.append(item.id)
            itemsByID[item.id] = item
        }
        userMessageRevision += 1
        delegate?.agentModelDidReloadTimeline(
            animated: animated,
            reconfigureItemIDs: previousFollowupMessageID != followupMessageID
                ? previousFollowupMessageID.map { [$0] } ?? [] : []
        )
    }

    private func appendDirectly(_ item: AgentTimelineItem, animated: Bool) {
        // The typing row of an answer goes before the rows that stay at the chat's end, as the questions waiting for it
        if case .typingIndicator = item, insertBeforeTrailingItems(item, animated: animated) { return }
        orderedItemIDs.append(item.id)
        itemsByID[item.id] = item
        userMessageRevision += 1
        delegate?.agentModelDidReloadTimeline(animated: animated, reconfigureItemIDs: [])
    }

    /// Puts `item` before the rows that stay at the chat's end, and returns whether there are any
    private func insertBeforeTrailingItems(_ item: AgentTimelineItem, animated: Bool) -> Bool {
        let trailingIDs = Set(backend.trailingItemIDs)
        var baseItems = baseTimelineItems
        guard let index = baseItems.firstIndex(where: { trailingIDs.contains($0.id) }) else { return false }
        baseItems.insert(item, at: index)
        setTimeline(baseItems, animated: animated)
        return true
    }

    private func replaceItem(id: AgentItemID, with item: AgentTimelineItem, animated: Bool) {
        releaseTypingIndicator()
        flushDeferredTypingIndicatorIfNeeded(for: id)
        var baseItems = baseTimelineItems
        guard let index = baseItems.firstIndex(where: { $0.id == id }) else { return }
        baseItems[index] = item
        setTimeline(baseItems, animated: animated)
    }

    private func removeItem(id: AgentItemID, animated: Bool) {
        if id == heldTypingIndicatorID {
            isHeldTypingIndicatorRemoved = true
            isHeldTypingIndicatorRemovalAnimated = animated
            return
        }
        if deferredTypingIndicator?.id == id {
            deferredTypingIndicator = nil
            return
        }
        guard itemsByID[id] != nil else { return }
        var baseItems = baseTimelineItems
        guard let index = baseItems.firstIndex(where: { $0.id == id }) else { return }
        baseItems.remove(at: index)
        setTimeline(baseItems, animated: animated)
    }

    private func updateMessage(_ message: AgentMessage, animated: Bool, scrollToBottom: Bool) {
        let previousMessage = self.message(for: message.id)
        itemsByID[message.id] = .message(message)
        if (previousMessage?.role == .user || message.role == .user),
           previousMessage?.role != message.role || previousMessage?.text != message.text {
            userMessageRevision += 1
        }
        delegate?.agentModelDidUpdateItems([message.id], animated: animated, scrollToBottom: scrollToBottom)
    }

    func message(for id: AgentItemID) -> AgentMessage? {
        guard let item = itemsByID[id], case .message(let message) = item else { return nil }
        return message
    }

    private func setHints(_ hints: [AgentHint], animated: Bool) {
        // Contact Support asks nothing of the Agent, so it has no prompt
        let filteredHints = hints.filter { hint in
            hint.isSupportRequest
                || !hint.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !hint.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !hint.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        availableHints = filteredHints

        delegate?.agentModelDidUpdateHints(animated: animated)
    }

    private var hasUserMessages: Bool {
        orderedItemIDs.contains { itemID in
            guard let item = itemsByID[itemID],
                  case .message(let message) = item else {
                return false
            }
            return message.role == .user
        }
    }

    private func makeEditContext(for id: AgentItemID) -> AgentBackendEditContext? {
        guard let item = itemsByID[id],
              case .message(let message) = item,
              message.role == .user else {
            return nil
        }

        return AgentBackendEditContext(messageID: id)
    }

    private func applyEditedMessage(_ text: String, id: AgentItemID) {
        var baseItems = baseTimelineItems
        guard let index = baseItems.firstIndex(where: { $0.id == id }),
              case .message(var message) = baseItems[index],
              message.role == .user else {
            return
        }

        baseItems = Array(baseItems.prefix(index + 1))
        message.text = text
        message.timestamp = Date()
        message.isStreaming = false
        message.systemStyle = nil
        baseItems[index] = .message(message)
        setTimeline(baseItems, animated: true, reconfigureItemIDs: [id])
    }

    private func replaceTimeline(
        with items: [AgentTimelineItem],
        animated: Bool,
        reconfigureItemIDs: [AgentItemID] = []
    ) {
        resetPendingTypingIndicator()
        var items = items
        if let heldID = heldTypingIndicatorID, let heldItem = itemsByID[heldID] {
            // The same chat again keeps the held row at its end; a chat with more in it lets the row go
            let itemIDs = Set(items.map(\.id))
            if itemIDs.isSubset(of: orderedItemIDs), !itemIDs.contains(heldID) {
                items.append(heldItem)
                isHeldTypingIndicatorRemoved = true
                isHeldTypingIndicatorRemovalAnimated = animated
            } else {
                heldTypingIndicatorID = nil
                isHeldTypingIndicatorRemoved = false
                typingIndicatorHold?.cancel()
                typingIndicatorHold = nil
            }
        }
        let timelineItems = timelineItemsByInsertingDateMessages(into: items)
        orderedItemIDs = timelineItems.map(\.id)
        itemsByID = Dictionary(uniqueKeysWithValues: timelineItems.map { ($0.id, $0) })
        userMessageRevision += 1
        delegate?.agentModelDidReloadTimeline(
            animated: animated,
            reconfigureItemIDs: reconfigureItemIDs
        )
    }

    var baseTimelineItems: [AgentTimelineItem] {
        orderedItemIDs.compactMap { itemID in
            guard let item = itemsByID[itemID] else { return nil }
            if case .message(let message) = item, message.isDateTimeSystemMessage {
                return nil
            }
            return item
        }
    }

    private var lastMessageTimestamp: Date? {
        for itemID in orderedItemIDs.reversed() {
            guard let item = itemsByID[itemID],
                  case .message(let message) = item,
                  !message.isDateTimeSystemMessage else {
                continue
            }
            return message.timestamp
        }
        return nil
    }

    private func shouldInsertDateMessage(before timestamp: Date) -> Bool {
        lastMessageTimestamp.map { timestamp.timeIntervalSince($0) > Metrics.dateHeaderGap } ?? true
    }

    /// The rows that go when the items `removedIDs` leave the timeline: those items and the date lines that head none of
    /// the messages left. Date lines are made anew with every timeline, so one that stays is known by its timestamp.
    private func getItemIDsLeavingTimeline(removing removedIDs: Set<AgentItemID>) -> [AgentItemID] {
        guard !removedIDs.isEmpty else { return [] }
        let remainingItems = baseTimelineItems.filter { !removedIDs.contains($0.id) }
        let remainingDateTimestamps = Set(timelineItemsByInsertingDateMessages(into: remainingItems).compactMap { item -> Date? in
            guard case .message(let message) = item, message.isDateTimeSystemMessage else { return nil }
            return message.timestamp
        })
        return orderedItemIDs.filter { itemID in
            guard case .message(let message)? = itemsByID[itemID], message.isDateTimeSystemMessage else {
                return removedIDs.contains(itemID)
            }
            return !remainingDateTimestamps.contains(message.timestamp)
        }
    }

    func setTimeline(
        _ baseItems: [AgentTimelineItem],
        animated: Bool,
        reconfigureItemIDs: [AgentItemID] = []
    ) {
        let previousFollowupMessageID = followupMessageID
        let timelineItems = timelineItemsByInsertingDateMessages(into: baseItems)
        orderedItemIDs = timelineItems.map(\.id)
        itemsByID = Dictionary(uniqueKeysWithValues: timelineItems.map { ($0.id, $0) })
        userMessageRevision += 1
        var updatedIDs = Set(reconfigureItemIDs)
        if previousFollowupMessageID != followupMessageID {
            if let previousFollowupMessageID, itemsByID[previousFollowupMessageID] != nil {
                updatedIDs.insert(previousFollowupMessageID)
            }
            if let followupMessageID { updatedIDs.insert(followupMessageID) }
        }
        delegate?.agentModelDidReloadTimeline(animated: animated, reconfigureItemIDs: Array(updatedIDs))
    }

    static func normalizedText(from text: String?) -> String? {
        let trimmedText = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private func timelineItemsByInsertingDateMessages(into baseItems: [AgentTimelineItem]) -> [AgentTimelineItem] {
        var items: [AgentTimelineItem] = []
        var lastMessageTimestamp: Date?

        for item in baseItems {
            switch item {
            case .message(let message):
                guard !message.isDateTimeSystemMessage else { continue }

                if lastMessageTimestamp.map({ message.timestamp.timeIntervalSince($0) > Metrics.dateHeaderGap }) ?? true {
                    items.append(.message(makeDateTimeSystemMessage(for: message.timestamp)))
                }

                items.append(.message(message))
                lastMessageTimestamp = message.timestamp
            case .typingIndicator(let indicator):
                items.append(.typingIndicator(indicator))
            }
        }

        return items
    }

    func formattedDate(for timestamp: Date) -> (date: String, time: String) {
        let dateText = timestamp.formatted(.localizedDateTime.year(.defaultDigits).month(.wide).day())
        return (dateText, Self.formattedTime(timestamp))
    }

    /// The time in `locale`'s words on the clock `hourCycle` names, the device's 12- or 24-hour clock by default
    static func formattedTime(
        _ timestamp: Date,
        locale: Locale = .autoupdatingCurrent,
        hourCycle: Locale.HourCycle = Locale.autoupdatingCurrent.hourCycle,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var components = Locale.Components(locale: locale)
        components.hourCycle = hourCycle
        var style = Date.FormatStyle.dateTime
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute()
            .locale(Locale(components: components))
        style.timeZone = timeZone
        return timestamp.formatted(style)
    }

    private func makeDateTimeSystemMessage(for timestamp: Date) -> AgentMessage {
        let (date, time) = formattedDate(for: timestamp)
        return AgentMessage(
            role: .system,
            text: "\(date) \(time)",
            isStreaming: false,
            systemStyle: .dateTime(date: date, time: time),
            timestamp: timestamp
        )
    }
}
