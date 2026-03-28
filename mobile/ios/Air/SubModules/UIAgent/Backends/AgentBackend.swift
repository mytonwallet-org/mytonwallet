import Foundation

public enum AgentBackendKind: String, CaseIterable {
    case testing
    case real
    case local
    case hybrid
}

extension AgentBackendKind {
    static var menuOrder: [Self] {
        return [.real, .local, .hybrid, .testing]
    }

    var menuTitle: String {
        switch self {
        case .testing:
            "Mock"
        case .real:
            "Live"
        case .local:
            "Local (On-Device)"
        case .hybrid:
            "Hybrid"
        }
    }

    @MainActor
    var isAvailable: Bool {
        switch self {
        case .testing:
            #if DEBUG
            true
            #else
            false
            #endif
        case .real:
            true
        case .local, .hybrid:
            AgentStore.shared.isLocalBackendAvailable
        }
    }
}

struct AgentBackendConversationMessage {
    enum Role {
        case user
        case assistant
    }

    let role: Role
    let text: String
}

struct AgentBackendEditContext {
    let originalText: String
    let history: [AgentBackendConversationMessage]
}

@MainActor
protocol AgentBackend: AnyObject {
    var kind: AgentBackendKind { get }

    func attach(to context: AgentBackendContext)
    func detach()
    func loadInitialTimeline(animated: Bool)
    func loadHints(animated: Bool)
    func prepareForEditing(_ editContext: AgentBackendEditContext)
    func didSendUserMessage(_ text: String, editContext: AgentBackendEditContext?)
    func reset()
}

extension AgentBackend {
    func loadHints(animated: Bool) {}
    func prepareForEditing(_ editContext: AgentBackendEditContext) {}
}

@MainActor
final class AgentBackendContext {
    private let replaceTimelineHandler: ([AgentTimelineItem], Bool) -> Void
    private let setHintsHandler: ([AgentHint], Bool) -> Void
    private let replaceItemHandler: (AgentItemID, AgentTimelineItem, Bool) -> Void
    private let appendHandler: (AgentTimelineItem, Bool) -> Void
    private let removeHandler: (AgentItemID, Bool) -> Void
    private let updateMessageHandler: (AgentMessage, Bool, Bool) -> Void
    private let messageProvider: (AgentItemID) -> AgentMessage?
    private let itemIDsProvider: () -> [AgentItemID]

    init(
        replaceTimelineHandler: @escaping ([AgentTimelineItem], Bool) -> Void,
        setHintsHandler: @escaping ([AgentHint], Bool) -> Void,
        replaceItemHandler: @escaping (AgentItemID, AgentTimelineItem, Bool) -> Void,
        appendHandler: @escaping (AgentTimelineItem, Bool) -> Void,
        removeHandler: @escaping (AgentItemID, Bool) -> Void,
        updateMessageHandler: @escaping (AgentMessage, Bool, Bool) -> Void,
        messageProvider: @escaping (AgentItemID) -> AgentMessage?,
        itemIDsProvider: @escaping () -> [AgentItemID]
    ) {
        self.replaceTimelineHandler = replaceTimelineHandler
        self.setHintsHandler = setHintsHandler
        self.replaceItemHandler = replaceItemHandler
        self.appendHandler = appendHandler
        self.removeHandler = removeHandler
        self.updateMessageHandler = updateMessageHandler
        self.messageProvider = messageProvider
        self.itemIDsProvider = itemIDsProvider
    }

    var itemIDs: [AgentItemID] {
        itemIDsProvider()
    }

    func replaceTimeline(with items: [AgentTimelineItem], animated: Bool) {
        replaceTimelineHandler(items, animated)
    }

    func setHints(_ hints: [AgentHint], animated: Bool) {
        setHintsHandler(hints, animated)
    }

    func append(_ item: AgentTimelineItem, animated: Bool) {
        appendHandler(item, animated)
    }

    func replaceItem(id: AgentItemID, with item: AgentTimelineItem, animated: Bool) {
        replaceItemHandler(id, item, animated)
    }

    func removeItem(id: AgentItemID, animated: Bool) {
        removeHandler(id, animated)
    }

    func updateMessage(_ message: AgentMessage, animated: Bool, scrollToBottom: Bool) {
        updateMessageHandler(message, animated, scrollToBottom)
    }

    func message(for id: AgentItemID) -> AgentMessage? {
        messageProvider(id)
    }
}
