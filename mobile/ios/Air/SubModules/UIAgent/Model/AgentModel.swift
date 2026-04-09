import Foundation
import WalletContext
import WalletCore

typealias AgentItemID = UUID

@MainActor
protocol AgentModelDelegate: AnyObject {
    func agentModelDidReloadTimeline(animated: Bool)
    func agentModelDidUpdateItems(_ ids: [AgentItemID], animated: Bool, scrollToBottom: Bool)
    func agentModelDidUpdateHints(animated: Bool)
}

@MainActor
final class AgentModel {
    private enum Metrics {
        static let dateHeaderGap: TimeInterval = 10 * 60
    }

    weak var delegate: AgentModelDelegate?

    private var orderedItemIDs: [AgentItemID] = []
    private var itemsByID: [AgentItemID: AgentTimelineItem] = [:]
    private var availableHints: [AgentHint] = []
    private var showsHintsInConversation = false
    private var isPersistenceEnabled = false
    private var isActive = false
    private var currentAccountID: String? = AccountStore.accountId
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

    init(backendKind: AgentBackendKind = .testing) {
        self.backend = Self.makeBackend(kind: backendKind)
        backend.attach(to: backendContext)
        let persistedItems = AgentStore.shared.persistedTimelineItems()
        if persistedItems.isEmpty {
            backend.loadInitialTimeline(animated: false)
        } else {
            let timelineItems = Self.timelineItemsByInsertingDateMessages(into: persistedItems)
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

    func switchBackend(to backendKind: AgentBackendKind, animated: Bool = true) {
        guard backend.kind != backendKind else { return }
        backend.detach()
        backend = Self.makeBackend(kind: backendKind)
        backend.attach(to: backendContext)
        backend.loadHints(animated: animated)
    }

    func setActive(_ isActive: Bool) {
        self.isActive = isActive
    }

    func handleAccountChangedEvent(animated: Bool = true) {
        guard isActive else { return }
        checkAccountChanged(animated: animated)
    }

    func checkAccountChanged(animated: Bool = true) {
        let newAccountID = AccountStore.accountId
        guard newAccountID != currentAccountID else { return }
        currentAccountID = newAccountID

        guard hasConversationMessages,
              let newAccountID,
              let account = AccountStore.accountsById[newAccountID] else {
            return
        }

        appendOrCoalesceAccountChangedMessage(for: account, animated: animated)
    }

    func refreshDerivedSystemMessages(animated: Bool = false) {
        setTimeline(baseTimelineItems, animated: animated)
    }

    func addSystemMessage(_ text: String, animated: Bool = true) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }
        appendMessage(
            AgentMessage(
                role: .system,
                text: normalizedText,
                isStreaming: false
            ),
            animated: animated
        )
    }

    func addDateTimeSystemMessage(date: String, time: String, animated: Bool = true) {
        let normalizedDate = date.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTime = time.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDate.isEmpty, !normalizedTime.isEmpty else { return }
        appendMessage(
            AgentMessage(
                role: .system,
                text: "\(normalizedDate) \(normalizedTime)",
                isStreaming: false,
                systemStyle: .dateTime(date: normalizedDate, time: normalizedTime)
            ),
            animated: animated
        )
    }

    func send(text: String?, editingMessageID: AgentItemID? = nil) {
        guard let text = normalizedText(from: text) else { return }

        showsHintsInConversation = false

        if let editingMessageID,
           let editContext = makeEditContext(for: editingMessageID) {
            backend.prepareForEditing(editContext)
            applyEditedMessage(text, id: editingMessageID)
            backend.didSendUserMessage(text, editContext: editContext)
            return
        }

        let message = AgentMessage(
            role: .user,
            text: text,
            isStreaming: false
        )
        appendMessage(message, animated: true)
        backend.didSendUserMessage(text, editContext: nil)
    }

    func clearChat(animated: Bool = true) {
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
        if case .message(let message) = item {
            appendMessage(message, animated: animated)
            return
        }
        appendDirectly(item, animated: animated)
    }

    private func appendMessage(_ message: AgentMessage, animated: Bool) {
        if message.isDateTimeSystemMessage {
            appendDirectly(.message(message), animated: animated)
            return
        }

        var insertedItems: [AgentTimelineItem] = []
        if shouldInsertDateMessage(before: message.timestamp) {
            insertedItems.append(.message(Self.makeDateTimeSystemMessage(for: message.timestamp)))
        }
        insertedItems.append(.message(message))

        for item in insertedItems {
            orderedItemIDs.append(item.id)
            itemsByID[item.id] = item
        }
        delegate?.agentModelDidReloadTimeline(animated: animated)
        if !message.isStreaming {
            persistStableTimelineIfNeeded()
        }
    }

    private func appendDirectly(_ item: AgentTimelineItem, animated: Bool) {
        orderedItemIDs.append(item.id)
        itemsByID[item.id] = item
        delegate?.agentModelDidReloadTimeline(animated: animated)
        if case .message(let message) = item, !message.isStreaming {
            persistStableTimelineIfNeeded()
        }
    }

    private func replaceItem(id: AgentItemID, with item: AgentTimelineItem, animated: Bool) {
        var baseItems = baseTimelineItems
        guard let index = baseItems.firstIndex(where: { $0.id == id }) else { return }
        baseItems[index] = item
        setTimeline(baseItems, animated: animated)
    }

    private func removeItem(id: AgentItemID, animated: Bool) {
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
            persistStableTimelineIfNeeded()
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

    private var hasConversationMessages: Bool {
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
        setTimeline(baseItems, animated: true)
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
        let timelineItems = Self.timelineItemsByInsertingDateMessages(into: items)
        orderedItemIDs = timelineItems.map(\.id)
        itemsByID = Dictionary(uniqueKeysWithValues: timelineItems.map { ($0.id, $0) })
        delegate?.agentModelDidReloadTimeline(animated: animated)
        persistStableTimelineIfNeeded()
    }

    private func persistStableTimelineIfNeeded() {
        guard isPersistenceEnabled else { return }
        AgentStore.shared.saveHistory(messages: persistedMessages)
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

    private var baseTimelineItems: [AgentTimelineItem] {
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

    private func appendOrCoalesceAccountChangedMessage(for account: MAccount, animated: Bool) {
        var baseItems = baseTimelineItems
        let message = AgentMessage(
            role: .system,
            text: lang("Switched to %@", arg1: account.displayName),
            isStreaming: false,
            systemStyle: .accountChange
        )

        if case .message(let lastMessage)? = baseItems.last,
           lastMessage.isAccountChangeSystemMessage {
            baseItems[baseItems.count - 1] = .message(message)
        } else {
            baseItems.append(.message(message))
        }

        setTimeline(baseItems, animated: animated)
    }

    private func setTimeline(_ baseItems: [AgentTimelineItem], animated: Bool) {
        let timelineItems = Self.timelineItemsByInsertingDateMessages(into: baseItems)
        orderedItemIDs = timelineItems.map(\.id)
        itemsByID = Dictionary(uniqueKeysWithValues: timelineItems.map { ($0.id, $0) })
        delegate?.agentModelDidReloadTimeline(animated: animated)
        persistStableTimelineIfNeeded()
    }

    private func normalizedText(from text: String?) -> String? {
        let trimmedText = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private static func timelineItemsByInsertingDateMessages(into baseItems: [AgentTimelineItem]) -> [AgentTimelineItem] {
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

    private static func makeDateTimeSystemMessage(for timestamp: Date) -> AgentMessage {
        let locale = LocalizationSupport.shared.locale
        let now = Date()
        let dateText: String
        if now.isInSameDay(as: timestamp) {
            dateText = lang("Today")
        } else if now.isInSameYear(as: timestamp) {
            dateText = timestamp.formatted(.dateTime.month(.wide).day().locale(locale))
        } else {
            dateText = timestamp.formatted(.dateTime.year(.defaultDigits).month(.wide).day().locale(locale))
        }
        let timeText = timestamp.formatted(
            .dateTime
                .hour(.defaultDigits(amPM: .omitted))
                .minute()
                .locale(locale)
        )

        return AgentMessage(
            role: .system,
            text: "\(dateText) \(timeText)",
            isStreaming: false,
            systemStyle: .dateTime(date: dateText, time: timeText),
            timestamp: timestamp
        )
    }

    static func preferredBackendKind() -> AgentBackendKind {
        switch ConfigStore.shared.preferredAgent {
        case .local:
            return AgentStore.shared.isLocalBackendAvailable ? .local : .real
        case .hybrid:
            return AgentStore.shared.isLocalBackendAvailable ? .hybrid : .real
        case .online:
            return .real
        }
    }

    private static func makeBackend(kind: AgentBackendKind) -> AgentBackend {
        switch kind {
        case .testing:
            AgentTestingBackend()
        case .real:
            AgentRealBackend()
        case .local:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), AgentStore.shared.isLocalBackendAvailable {
                AgentLocalBackend()
            } else {
                AgentRealBackend()
            }
            #else
            AgentRealBackend()
            #endif
        case .hybrid:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), AgentStore.shared.isLocalBackendAvailable {
                AgentHybridBackend()
            } else {
                AgentRealBackend()
            }
            #else
            AgentRealBackend()
            #endif
        }
    }
}

enum AgentTimelineItem {
    case message(AgentMessage)
    case typingIndicator(AgentTypingIndicator)

    var id: AgentItemID {
        switch self {
        case .message(let message):
            message.id
        case .typingIndicator(let indicator):
            indicator.id
        }
    }
}

struct AgentHint: Decodable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let prompt: String
}

struct AgentMessage {
    enum Role: String {
        case assistant
        case system
        case user
    }

    enum SystemStyle {
        case dateTime(date: String, time: String)
        case accountChange
    }

    let id: AgentItemID
    let role: Role
    var text: String
    var timestamp: Date
    var isStreaming: Bool
    var action: AgentMessageAction? = nil
    var systemStyle: SystemStyle? = nil

    init(
        id: AgentItemID = UUID(),
        role: Role,
        text: String,
        isStreaming: Bool,
        action: AgentMessageAction? = nil,
        systemStyle: SystemStyle? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.action = action
        self.systemStyle = systemStyle
    }
}

struct AgentMessageAction {
    let title: String
    let url: URL
}

struct AgentTypingIndicator {
    let id: AgentItemID = UUID()
}

extension Character {
    var isSentenceBoundary: Bool {
        self == "." || self == "!" || self == "?"
    }
}

private extension AgentMessage {
    var isDateTimeSystemMessage: Bool {
        if case .dateTime? = systemStyle {
            return true
        }
        return false
    }

    var isAccountChangeSystemMessage: Bool {
        if case .accountChange? = systemStyle {
            return true
        }
        return false
    }
}
