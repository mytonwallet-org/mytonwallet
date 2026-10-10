import Foundation

@MainActor
protocol AgentModelDelegate: AnyObject {
    func agentModelDidReloadTimeline(animated: Bool, reconfigureItemIDs: [AgentItemID])
    func agentModelDidUpdateItems(_ ids: [AgentItemID], animated: Bool, scrollToBottom: Bool)
    func agentModelDidUpdateHints(animated: Bool)
    func agentModelDidUpdateState()
    func agentModelWillRevealSentUserMessage(_ userMessageID: AgentItemID, then completion: @escaping () -> Void)
}

extension AgentModelDelegate {
    func agentModelDidUpdateState() {}

    func agentModelWillRevealSentUserMessage(_ userMessageID: AgentItemID, then completion: @escaping () -> Void) {
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
    private var availableHints: [AgentHint] = []
    private var deferredTypingIndicator: AgentTimelineItem?
    private var pendingRevealUserMessageID: AgentItemID?
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
            return message.role == .assistant ? id : nil
        }
        return nil
    }

    func canSendMessage(draftText: String?) -> Bool {
        backend.canSendMessages && normalizedText(from: draftText) != nil
    }

    func refreshDerivedSystemMessages(animated: Bool = false) {
        setTimeline(baseTimelineItems, animated: animated)
        backend.refreshPresentation()
    }

    func send(
        text: String?,
        editingMessageID: AgentItemID? = nil,
        source: AgentBackendSendSource = .composer
    ) {
        guard let text = normalizedText(from: text) else { return }

        if let editingMessageID,
           let editContext = makeEditContext(for: editingMessageID) {
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
        appendMessage(message, animated: true)
        beginTypingIndicatorReveal(for: message.id)
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
        resetPendingTypingIndicator()
        backend.clearConversation { [weak self] didClear in
            guard didClear, let self else { return }
            self.replaceTimeline(with: [], animated: animated)
            self.backend.loadHints(animated: animated)
        }
    }

    func reportProblem(messageID: AgentItemID?, comment: String?) async -> Bool {
        await backend.reportProblem(messageID: messageID, comment: comment)
    }

    func loadOlderMessages() async -> Bool {
        await backend.loadOlderMessages()
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
        delegate?.agentModelDidReloadTimeline(
            animated: animated,
            reconfigureItemIDs: previousFollowupMessageID != followupMessageID
                ? previousFollowupMessageID.map { [$0] } ?? [] : []
        )
    }

    private func appendDirectly(_ item: AgentTimelineItem, animated: Bool) {
        orderedItemIDs.append(item.id)
        itemsByID[item.id] = item
        delegate?.agentModelDidReloadTimeline(animated: animated, reconfigureItemIDs: [])
    }

    private func replaceItem(id: AgentItemID, with item: AgentTimelineItem, animated: Bool) {
        flushDeferredTypingIndicatorIfNeeded(for: id)
        var baseItems = baseTimelineItems
        guard let index = baseItems.firstIndex(where: { $0.id == id }) else { return }
        baseItems[index] = item
        setTimeline(baseItems, animated: animated)
    }

    private func removeItem(id: AgentItemID, animated: Bool) {
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
        itemsByID[message.id] = .message(message)
        delegate?.agentModelDidUpdateItems([message.id], animated: animated, scrollToBottom: scrollToBottom)
    }

    private func message(for id: AgentItemID) -> AgentMessage? {
        guard let item = itemsByID[id], case .message(let message) = item else { return nil }
        return message
    }

    private func setHints(_ hints: [AgentHint], animated: Bool) {
        let filteredHints = hints.filter { hint in
            !hint.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        let timelineItems = timelineItemsByInsertingDateMessages(into: items)
        orderedItemIDs = timelineItems.map(\.id)
        itemsByID = Dictionary(uniqueKeysWithValues: timelineItems.map { ($0.id, $0) })
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

    func setTimeline(
        _ baseItems: [AgentTimelineItem],
        animated: Bool,
        reconfigureItemIDs: [AgentItemID] = []
    ) {
        let previousFollowupMessageID = followupMessageID
        let timelineItems = timelineItemsByInsertingDateMessages(into: baseItems)
        orderedItemIDs = timelineItems.map(\.id)
        itemsByID = Dictionary(uniqueKeysWithValues: timelineItems.map { ($0.id, $0) })
        var updatedIDs = Set(reconfigureItemIDs)
        if previousFollowupMessageID != followupMessageID {
            if let previousFollowupMessageID, itemsByID[previousFollowupMessageID] != nil {
                updatedIDs.insert(previousFollowupMessageID)
            }
            if let followupMessageID { updatedIDs.insert(followupMessageID) }
        }
        delegate?.agentModelDidReloadTimeline(animated: animated, reconfigureItemIDs: Array(updatedIDs))
    }

    private func normalizedText(from text: String?) -> String? {
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
        let dateText = timestamp.formatted(.dateTime.year(.defaultDigits).month(.wide).day())
        return (dateText, Self.formattedTime(timestamp))
    }

    static func formattedTime(
        _ timestamp: Date,
        locale: Locale = .autoupdatingCurrent,
        hourCycle: Locale.HourCycle = Locale.autoupdatingCurrent.hourCycle
    ) -> String {
        var components = Locale.Components(locale: locale)
        components.hourCycle = hourCycle
        return timestamp.formatted(
            .dateTime
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute()
                .locale(Locale(components: components))
        )
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
