import Foundation
import WalletCore

struct AgentBackendEditContext {
    let messageID: AgentItemID
}

enum AgentBackendSendSource {
    case composer
    case entryPoint(ApiAgentV2EntryPoint)
    case hint(id: String, catalogVersion: String?)
    case followup(messageID: String, followupID: String)
}

@MainActor
protocol AgentBackend: AnyObject {
    var canSendMessages: Bool { get }
    var canClearConversation: Bool { get }
    var shouldConfirmConversationClear: Bool { get }
    var canReportProblem: Bool { get }
    var typingIndicatorStatusText: String? { get }
    var typingIndicatorAccessibilityLabel: String? { get }
    var accessibilityStatus: String? { get }

    func attach(to context: AgentBackendContext)
    func detach()
    func loadHints(animated: Bool)
    func prepareForEditing(_ editContext: AgentBackendEditContext)
    func didSendUserMessage(
        _ text: String,
        userMessageID: AgentItemID,
        source: AgentBackendSendSource,
        editContext: AgentBackendEditContext?
    )
    func clearConversation(completion: @escaping (Bool) -> Void)
    /// Reports the conversation, or the message `messageID` names, and returns whether the report was sent
    func reportProblem(messageID: AgentItemID?, comment: String?) async -> Bool
    func loadOlderMessages() async -> Bool
    func performControl(messageID: AgentItemID, controlID: String)
    func refreshPresentation()
    /// The chat is on screen, so the backend keeps its wallet data current.
    func setActive(_ isActive: Bool)
    func stop()
}

extension AgentBackend {
    var canSendMessages: Bool { true }
    var canClearConversation: Bool { true }
    var shouldConfirmConversationClear: Bool { false }
    var canReportProblem: Bool { false }
    var typingIndicatorStatusText: String? { nil }
    var typingIndicatorAccessibilityLabel: String? { nil }
    var accessibilityStatus: String? { nil }

    func reportProblem(messageID: AgentItemID?, comment: String?) async -> Bool { false }

    func loadOlderMessages() async -> Bool { false }

    func performControl(messageID: AgentItemID, controlID: String) {}

    func refreshPresentation() {}

    func setActive(_ isActive: Bool) {}

    func stop() {}

}

@MainActor
final class AgentBackendContext {
    private let replaceTimelineHandler: ([AgentTimelineItem], Bool, [AgentItemID]) -> Void
    private let setHintsHandler: ([AgentHint], Bool) -> Void
    private let replaceItemHandler: (AgentItemID, AgentTimelineItem, Bool) -> Void
    private let appendHandler: (AgentTimelineItem, Bool) -> Void
    private let removeHandler: (AgentItemID, Bool) -> Void
    private let updateMessageHandler: (AgentMessage, Bool, Bool) -> Void
    private let messageProvider: (AgentItemID) -> AgentMessage?
    private let itemIDsProvider: () -> [AgentItemID]
    private let stateDidChangeHandler: () -> Void
    private let sendMessageHandler: (String, AgentBackendSendSource) -> Void

    init(
        replaceTimelineHandler: @escaping ([AgentTimelineItem], Bool, [AgentItemID]) -> Void,
        setHintsHandler: @escaping ([AgentHint], Bool) -> Void,
        replaceItemHandler: @escaping (AgentItemID, AgentTimelineItem, Bool) -> Void,
        appendHandler: @escaping (AgentTimelineItem, Bool) -> Void,
        removeHandler: @escaping (AgentItemID, Bool) -> Void,
        updateMessageHandler: @escaping (AgentMessage, Bool, Bool) -> Void,
        messageProvider: @escaping (AgentItemID) -> AgentMessage?,
        itemIDsProvider: @escaping () -> [AgentItemID],
        stateDidChangeHandler: @escaping () -> Void,
        sendMessageHandler: @escaping (String, AgentBackendSendSource) -> Void
    ) {
        self.replaceTimelineHandler = replaceTimelineHandler
        self.setHintsHandler = setHintsHandler
        self.replaceItemHandler = replaceItemHandler
        self.appendHandler = appendHandler
        self.removeHandler = removeHandler
        self.updateMessageHandler = updateMessageHandler
        self.messageProvider = messageProvider
        self.itemIDsProvider = itemIDsProvider
        self.stateDidChangeHandler = stateDidChangeHandler
        self.sendMessageHandler = sendMessageHandler
    }

    var itemIDs: [AgentItemID] {
        itemIDsProvider()
    }

    func replaceTimeline(
        with items: [AgentTimelineItem],
        animated: Bool,
        reconfigureItemIDs: [AgentItemID] = []
    ) {
        replaceTimelineHandler(items, animated, reconfigureItemIDs)
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

    func notifyStateChanged() {
        stateDidChangeHandler()
    }

    func sendMessage(_ text: String, source: AgentBackendSendSource) {
        sendMessageHandler(text, source)
    }
}
