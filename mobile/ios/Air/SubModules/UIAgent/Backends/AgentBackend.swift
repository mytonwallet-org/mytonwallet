import Foundation
import WalletCore

struct AgentBackendEditContext {
    let messageID: AgentItemID
}

enum AgentBackendSendSource {
    case composer
    case hint(id: String, catalogVersion: String?)
    case followup(messageID: String, followupID: String)
    /// Asks for a support operator from `source`
    case supportRequest(ApiAgentV2EntryPoint.SupportRequestSource)

    var isSupportRequest: Bool {
        if case .supportRequest = self { return true }
        return false
    }
}

@MainActor
protocol AgentBackend: AnyObject {
    var canSendMessages: Bool { get }
    /// A question can go now, or wait in the chat for the answer being written, as Android queues it
    var canAcceptMessages: Bool { get }
    /// A question sent now waits in the chat: for the answer being written, or for its discussion's thread to be
    /// created
    var queuesNextQuestion: Bool { get }
    /// The rows that stay at the chat's end, after the answer being written: the questions that wait for it, and those
    /// a wallet switch failed there with their failure
    var trailingItemIDs: [AgentItemID] { get }
    /// An answer is being written, and the user can stop it
    var canStopAnswer: Bool { get }
    var canClearConversation: Bool { get }
    var shouldConfirmConversationClear: Bool { get }
    var canReportProblem: Bool { get }
    var typingIndicatorStatusText: String? { get }
    var typingIndicatorAccessibilityLabel: String? { get }
    var accessibilityStatus: String? { get }
    var supportState: AgentSupportState { get }
    /// The chat offers Contact Support
    var isSupportRequestVisible: Bool { get }
    /// A support request can go now
    var canRequestSupport: Bool { get }

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
    /// The model empties its timeline right after this call; a backend that fails to clear presents
    /// its conversation again.
    func clearConversation()
    /// Reports the conversation, or the message `messageID` names, and returns whether the report was sent
    func reportProblem(messageID: AgentItemID?, comment: String?) async -> Bool
    /// Sets the rating of the answer `messageID`, or withdraws it with `nil`, showing it at once. Returns `false` when
    /// saving failed and the rating the server keeps shows again.
    func rateMessage(messageID: AgentItemID, feedback: ApiAgentV2AnswerFeedback?) async -> Bool
    func loadOlderMessages() async -> Bool
    /// Older messages are on their way, which the chat shows with its spinner under the header
    var isLoadingOlderMessages: Bool { get }
    /// The user's message `messageID` can be edited, as one that went
    func canEditMessage(messageID: AgentItemID) -> Bool
    /// The answer `messageID` can be written again in its place
    func canRegenerateMessage(messageID: AgentItemID) -> Bool
    /// The items `regenerateMessage(messageID:)` takes out of the chat: the answer and the messages after it
    func getItemIDsRemovedByRegenerating(messageID: AgentItemID) -> [AgentItemID]
    /// Asks for the answer `messageID` again: it and the messages after it give way to the new answer
    func regenerateMessage(messageID: AgentItemID)
    func performControl(messageID: AgentItemID, controlID: String)
    /// Stops the answer being written; the chat can send again at once
    func stopAnswer()
    func refreshPresentation()
    /// The chat is on screen, so the backend keeps its wallet data current.
    func setActive(_ isActive: Bool)
    func stop()
}

extension AgentBackend {
    var canSendMessages: Bool { true }
    var canAcceptMessages: Bool { canSendMessages }
    var queuesNextQuestion: Bool { !canSendMessages && canAcceptMessages }
    var trailingItemIDs: [AgentItemID] { [] }
    var canStopAnswer: Bool { false }
    var canClearConversation: Bool { true }
    var shouldConfirmConversationClear: Bool { false }
    var canReportProblem: Bool { false }
    var typingIndicatorStatusText: String? { nil }
    var typingIndicatorAccessibilityLabel: String? { nil }
    var accessibilityStatus: String? { nil }
    var supportState: AgentSupportState { .none }
    var isSupportRequestVisible: Bool { false }
    var canRequestSupport: Bool { false }

    func reportProblem(messageID: AgentItemID?, comment: String?) async -> Bool { false }

    func rateMessage(messageID: AgentItemID, feedback: ApiAgentV2AnswerFeedback?) async -> Bool { false }

    func loadOlderMessages() async -> Bool { false }

    var isLoadingOlderMessages: Bool { false }

    func canEditMessage(messageID: AgentItemID) -> Bool { true }

    func canRegenerateMessage(messageID: AgentItemID) -> Bool { false }

    func getItemIDsRemovedByRegenerating(messageID: AgentItemID) -> [AgentItemID] { [] }

    func regenerateMessage(messageID: AgentItemID) {}

    func performControl(messageID: AgentItemID, controlID: String) {}

    func stopAnswer() {}

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
    private let revealSentMessageHandler: @MainActor (AgentItemID, () -> Void) -> Void

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
        sendMessageHandler: @escaping (String, AgentBackendSendSource) -> Void,
        revealSentMessageHandler: @escaping @MainActor (AgentItemID, () -> Void) -> Void = { _, send in send() }
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
        self.revealSentMessageHandler = revealSentMessageHandler
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

    /// A question that waited in the chat, `id`, goes as `send` runs: the chat brings it up as a question just sent,
    /// with the typing row `send` appends following once it is up
    func revealSentMessage(_ id: AgentItemID, sending send: () -> Void) {
        revealSentMessageHandler(id, send)
    }
}
