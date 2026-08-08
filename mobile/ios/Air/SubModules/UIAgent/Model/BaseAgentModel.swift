import Foundation

@MainActor
protocol AgentModelDelegate: AnyObject {
    func agentModelDidReloadTimeline(animated: Bool, reconfigureItemIDs: [AgentItemID])
    func agentModelDidUpdateItems(_ ids: [AgentItemID], animated: Bool, scrollToBottom: Bool)
    func agentModelDidUpdateHints(animated: Bool)
    func agentModelWillRevealSentUserMessage(_ userMessageID: AgentItemID, then completion: @escaping () -> Void)
}

extension AgentModelDelegate {
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
    var isActive = false
    
    private var orderedItemIDs: [AgentItemID] = []
    private var itemsByID: [AgentItemID: AgentTimelineItem] = [:]
    private var availableHints: [AgentHint] = []
    private var showsHintsInConversation = false
    private var isPersistenceEnabled = false
    private var deferredTypingIndicator: AgentTimelineItem?
    private var pendingRevealUserMessageID: AgentItemID?
    private var isAwaitingTypingIndicatorReveal = false
    private var backend: AgentBackend
    private lazy var backendContext = AgentBackendContext(
        replaceTimelineHandler: { [weak self] items, animated in
            self?.replaceTimeline(with: items, animated: animated)
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
        }
    )

    init(backend: AgentBackend) {
        self.backend = backend
        backend.attach(to: backendContext)
        let persistedItems = loadPersistedTimeline()
        if persistedItems.isEmpty {
            replaceTimeline(with: [], animated: false)
        } else {
            let timelineItems = timelineItemsByInsertingDateMessages(into: persistedItems)
            orderedItemIDs = timelineItems.map(\.id)
            itemsByID = Dictionary(uniqueKeysWithValues: timelineItems.map { ($0.id, $0) })
        }
        backend.loadHints(animated: false)
        isPersistenceEnabled = true
    }

    var itemIDs: [AgentItemID] {
        orderedItemIDs
    }

    var activeBackendKind: AgentBackendKind {
        backend.kind
    }

    var canToggleHintsVisibility: Bool {
        hasUserMessages && !availableHints.isEmpty
    }

    var areHintsVisible: Bool {
        !visibleHints.isEmpty
    }

    var visibleHints: [AgentHint] {
        shouldShowHints ? availableHints : []
    }

    func item(for id: AgentItemID) -> AgentTimelineItem? {
        itemsByID[id]
    }

    func canSendMessage(draftText: String?) -> Bool {
        normalizedText(from: draftText) != nil
    }

    func switchBackend(to backend: AgentBackend, animated: Bool = true) {
        guard backend.kind != self.backend.kind else { return }
        resetPendingTypingIndicator()
        self.backend.detach()
        self.backend = backend
        self.backend.attach(to: backendContext)
        self.backend.loadHints(animated: animated)
    }

    func refreshDerivedSystemMessages(animated: Bool = false) {
        setTimeline(baseTimelineItems, animated: animated)
    }

    func send(text: String?, editingMessageID: AgentItemID? = nil) {
        guard let text = normalizedText(from: text) else { return }

        showsHintsInConversation = false

        if let editingMessageID,
           let editContext = makeEditContext(for: editingMessageID) {
            backend.prepareForEditing(editContext)
            applyEditedMessage(text, id: editingMessageID)
            beginTypingIndicatorReveal(for: editingMessageID)
            backend.didSendUserMessage(text, editContext: editContext)
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
        backend.didSendUserMessage(text, editContext: nil)
        cancelPendingTypingIndicatorReveal()
    }

    func clearChat(animated: Bool = true) {
        resetPendingTypingIndicator()
        backend.reset()
        showsHintsInConversation = false
        replaceTimeline(with: [], animated: animated)
        backend.loadHints(animated: animated)
    }

    func toggleHintsVisibility(animated: Bool = true) {
        guard canToggleHintsVisibility else { return }
        showsHintsInConversation.toggle()
        delegate?.agentModelDidUpdateHints(animated: animated)
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

        var insertedItems: [AgentTimelineItem] = []
        if shouldInsertDateMessage(before: message.timestamp) {
            insertedItems.append(.message(makeDateTimeSystemMessage(for: message.timestamp)))
        }
        insertedItems.append(.message(message))

        for item in insertedItems {
            orderedItemIDs.append(item.id)
            itemsByID[item.id] = item
        }
        delegate?.agentModelDidReloadTimeline(animated: animated, reconfigureItemIDs: [])
        if !message.isStreaming {
            doPersistStableTimelineIfNeeded()
        }
    }

    private func appendDirectly(_ item: AgentTimelineItem, animated: Bool) {
        orderedItemIDs.append(item.id)
        itemsByID[item.id] = item
        delegate?.agentModelDidReloadTimeline(animated: animated, reconfigureItemIDs: [])
        if case .message(let message) = item, !message.isStreaming {
            doPersistStableTimelineIfNeeded()
        }
    }

    private func replaceItem(id: AgentItemID, with item: AgentTimelineItem, animated: Bool) {
        flushDeferredTypingIndicatorIfNeeded(for: id)
        var baseItems = baseTimelineItems
        guard let index = baseItems.firstIndex(where: { $0.id == id }) else { return }
        baseItems[index] = item
        setTimeline(baseItems, animated: animated)
    }

    private func removeItem(id: AgentItemID, animated: Bool) {
        flushDeferredTypingIndicatorIfNeeded(for: id)
        guard itemsByID[id] != nil else { return }
        var baseItems = baseTimelineItems
        guard let index = baseItems.firstIndex(where: { $0.id == id }) else { return }
        baseItems.remove(at: index)
        setTimeline(baseItems, animated: animated)
    }

    private func updateMessage(_ message: AgentMessage, animated: Bool, scrollToBottom: Bool) {
        itemsByID[message.id] = .message(message)
        delegate?.agentModelDidUpdateItems([message.id], animated: animated, scrollToBottom: scrollToBottom)
        if !message.isStreaming {
            doPersistStableTimelineIfNeeded()
        }
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

        if filteredHints.isEmpty {
            showsHintsInConversation = false
        }

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

    private var shouldShowHints: Bool {
        guard !availableHints.isEmpty else { return false }
        return !hasUserMessages || showsHintsInConversation
    }

    var hasConversationMessages: Bool {
        orderedItemIDs.contains { itemID in
            guard let item = itemsByID[itemID],
                  case .message(let message) = item else {
                return false
            }
            return !message.isDateTimeSystemMessage
        }
    }

    private func makeEditContext(for id: AgentItemID) -> AgentBackendEditContext? {
        guard let index = orderedItemIDs.firstIndex(of: id),
              let item = itemsByID[id],
              case .message(let message) = item,
              message.role == .user else {
            return nil
        }

        return AgentBackendEditContext(
            originalText: message.text,
            history: conversationHistory(before: index)
        )
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
        message.action = nil
        message.systemStyle = nil
        baseItems[index] = .message(message)
        setTimeline(baseItems, animated: true, reconfigureItemIDs: [id])
    }

    private func conversationHistory(before itemIndex: Int) -> [AgentBackendConversationMessage] {
        orderedItemIDs.prefix(itemIndex).compactMap { itemID in
            guard let item = itemsByID[itemID],
                  case .message(let message) = item else {
                return nil
            }

            switch message.role {
            case .user:
                return AgentBackendConversationMessage(role: .user, text: message.text)
            case .assistant:
                return AgentBackendConversationMessage(role: .assistant, text: message.text)
            case .system:
                return nil
            }
        }
    }

    private func replaceTimeline(with items: [AgentTimelineItem], animated: Bool) {
        let timelineItems = timelineItemsByInsertingDateMessages(into: items)
        orderedItemIDs = timelineItems.map(\.id)
        itemsByID = Dictionary(uniqueKeysWithValues: timelineItems.map { ($0.id, $0) })
        delegate?.agentModelDidReloadTimeline(animated: animated, reconfigureItemIDs: [])
        doPersistStableTimelineIfNeeded()
    }

    private func doPersistStableTimelineIfNeeded() {
        guard isPersistenceEnabled else { return }
        persistStableTimelineIfNeeded(messages: persistedMessages)
    }
    
    func persistStableTimelineIfNeeded(messages: [AgentMessage]) {
        assertionFailure("Override this")
    }
    
    func loadPersistedTimeline() -> [AgentTimelineItem] {
        assertionFailure("Override this")
        return []
    }

    private var persistedMessages: [AgentMessage] {
        orderedItemIDs.compactMap { itemID in
            guard let item = itemsByID[itemID],
                  case .message(var message) = item,
                  !message.isStreaming,
                  !message.isDateTimeSystemMessage else {
                return nil
            }
            message.isStreaming = false
            return message
        }
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
        let timelineItems = timelineItemsByInsertingDateMessages(into: baseItems)
        orderedItemIDs = timelineItems.map(\.id)
        itemsByID = Dictionary(uniqueKeysWithValues: timelineItems.map { ($0.id, $0) })
        delegate?.agentModelDidReloadTimeline(animated: animated, reconfigureItemIDs: reconfigureItemIDs)
        doPersistStableTimelineIfNeeded()
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
        let timeText = timestamp.formatted(
            .dateTime
                .hour(.defaultDigits(amPM: .omitted))
                .minute()
        )
        return (dateText, timeText)
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
