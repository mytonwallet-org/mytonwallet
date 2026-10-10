import Foundation
import WalletCore

struct AgentV2NativeAction: Equatable, Sendable {
    let id: String
    let kind: ApiAgentV2ActionKind
    let labelCode: ApiAgentV2ActionLabelCode
    let title: String
    var presentation: ApiAgentV2ActionPresentation?
}

enum AgentV2NativeMessageStatus: Equatable, Sendable {
    case streaming
    case complete
    case error
    case cancelled

    init(_ status: ApiAgentV2PersistedMessageStatus) {
        switch status {
        case .complete: self = .complete
        case .error: self = .error
        case .cancelled: self = .cancelled
        }
    }

    var isStreaming: Bool {
        self == .streaming
    }
}

enum AgentV2NativeMessageContent: Equatable, Sendable {
    case markdown(String)
    case semanticPending
    case semantic(ApiAgentV2SemanticContent)

    var kind: ApiAgentV2ContentKind {
        switch self {
        case .markdown: .markdown
        case .semanticPending, .semantic: .semantic
        }
    }

    var text: String {
        guard case .markdown(let text) = self else { return "" }
        return text
    }

    var semanticContent: ApiAgentV2SemanticContent? {
        guard case .semantic(let content) = self else { return nil }
        return content
    }
}

struct AgentV2NativeMessage: Equatable, Sendable, Identifiable {
    var id: String
    let threadId: String
    let role: ApiAgentV2MessageRole
    private(set) var content: AgentV2NativeMessageContent
    let createdAt: Date
    private(set) var status: AgentV2NativeMessageStatus
    let responseLanguage: String?
    var error: ApiAgentV2MessageError?
    var actions: [AgentV2NativeAction]
    var followups: [ApiAgentV2FollowUp]
    var tables: [ApiAgentV2AnswerTable] = []
    var tableReferences: [ApiAgentV2AnswerTableReference] = []
    var links: [ApiAgentV2AnswerLink] = []

    var text: String {
        AgentV2AnswerTables.text(content.text, tables: tables, references: tableReferences, links: links)
    }

    var contentKind: ApiAgentV2ContentKind {
        content.kind
    }

    var semanticContent: ApiAgentV2SemanticContent? {
        content.semanticContent
    }

    init(persisted message: ApiAgentV2PersistedMessage) {
        id = message.id
        threadId = message.threadId
        role = message.role
        switch message.content {
        case .markdown(let markdown):
            content = .markdown(markdown)
        case .composedMarkdown(let markdown):
            content = .markdown(markdown.text)
            tables = markdown.tables
            tableReferences = markdown.tableReferences
            links = markdown.links
        case .semantic(let semantic):
            content = .semantic(semantic)
        case nil:
            content = .markdown("")
        }
        createdAt = AgentV2DateParser.date(message.createdAt)
        status = AgentV2NativeMessageStatus(message.status)
        responseLanguage = message.responseLanguage
        error = message.error
        actions = (message.actions ?? []).map { action in
            return AgentV2NativeAction(
                id: action.id,
                kind: action.kind,
                labelCode: action.labelCode,
                title: action.title,
                presentation: nil
            )
        }
        followups = message.followups ?? []
    }

    init(
        id: String,
        threadId: String,
        role: ApiAgentV2MessageRole,
        text: String,
        contentKind: ApiAgentV2ContentKind = .markdown,
        responseLanguage: String? = nil,
        status: AgentV2NativeMessageStatus = .complete
    ) {
        self.id = id
        self.threadId = threadId
        self.role = role
        content = contentKind == .markdown ? .markdown(text) : .semanticPending
        createdAt = Date()
        self.status = status
        self.responseLanguage = responseLanguage
        error = nil
        actions = []
        followups = []
    }

    mutating func appendMarkdown(_ delta: String) {
        guard case .markdown(let text) = content else { return }
        content = .markdown(text + delta)
    }

    mutating func setSemanticContent(_ semanticContent: ApiAgentV2SemanticContent) {
        content = .semantic(semanticContent)
    }

    mutating func finalize(status: AgentV2NativeMessageStatus = .complete) {
        guard self.status.isStreaming else { return }
        self.status = status
    }

}

struct AgentV2ConversationState {
    private(set) var messages: [AgentV2NativeMessage] = []

    mutating func replaceMessages(
        _ hydratedMessages: [AgentV2NativeMessage],
        preservingLiveActions: Bool = false
    ) {
        guard preservingLiveActions else {
            messages = hydratedMessages
            return
        }
        var liveActionsByMessageId: [String: [AgentV2NativeAction]] = [:]
        for message in messages where !message.actions.isEmpty {
            liveActionsByMessageId[message.id] = message.actions
        }
        messages = hydratedMessages.map { message in
            guard let liveActions = liveActionsByMessageId[message.id] else { return message }
            var reconciledMessage = message
            reconciledMessage.actions = message.actions.map { action in
                var reconciledAction = action
                if let liveAction = liveActions.first(where: { $0.id == action.id && $0.kind == action.kind }) {
                    reconciledAction.presentation = liveAction.presentation
                }
                return reconciledAction
            }
            let savedActionIds = Set(message.actions.map(\.id))
            reconciledMessage.actions += liveActions.filter { !savedActionIds.contains($0.id) }
            return reconciledMessage
        }
    }

    mutating func prependMessages(_ messages: [AgentV2NativeMessage]) {
        let existingIds = Set(self.messages.map(\.id))
        self.messages = messages.filter { !existingIds.contains($0.id) } + self.messages
    }

    mutating func removeAllMessages() {
        messages.removeAll()
    }

    mutating func appendMessage(_ message: AgentV2NativeMessage) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
    }

    mutating func ensureAssistantMessage(
        threadId: String,
        messageId: String,
        contentKind: ApiAgentV2ContentKind,
        responseLanguage: String? = nil
    ) {
        guard !messages.contains(where: { $0.id == messageId }) else { return }
        appendMessage(AgentV2NativeMessage(
            id: messageId,
            threadId: threadId,
            role: .assistant,
            text: "",
            contentKind: contentKind,
            responseLanguage: responseLanguage,
            status: .streaming
        ))
    }

    mutating func appendMarkdown(messageId: String, delta: String) {
        mutateMessage(id: messageId) { $0.appendMarkdown(delta) }
    }

    mutating func setAnswerTables(id: String, tables: [ApiAgentV2AnswerTable], references: [ApiAgentV2AnswerTableReference]) {
        mutateMessage(id: id) {
            $0.tables = tables
            $0.tableReferences = references
        }
    }

    mutating func addAnswerLink(id: String, link: ApiAgentV2AnswerLink) {
        mutateMessage(id: id) { $0.links.append(link) }
    }

    mutating func completeMessage(id: String) {
        mutateMessage(id: id) { $0.finalize() }
    }

    mutating func endMessageContent(id: String) {
        mutateMessage(id: id) { $0.finalize() }
    }

    /// Returns whether the conversation holds the answer, which then shows the error as a hydrated failed answer does.
    mutating func failMessage(id: String, error: ApiAgentV2MessageError) -> Bool {
        guard messages.contains(where: { $0.id == id }) else { return false }
        mutateMessage(id: id) {
            $0.error = error
            $0.finalize(status: .error)
        }
        return true
    }

    mutating func setSemanticContent(id: String, content: ApiAgentV2SemanticContent) {
        mutateMessage(id: id) { $0.setSemanticContent(content) }
    }

    mutating func upsertAction(id messageId: String, action: AgentV2NativeAction) {
        mutateMessage(id: messageId) {
            $0.actions.removeAll { $0.id == action.id }
            $0.actions.append(action)
        }
    }

    mutating func setActionPresentation(
        messageId: String,
        actionId: String,
        presentation: ApiAgentV2ActionPresentation?
    ) {
        mutateMessage(id: messageId) { message in
            guard let index = message.actions.firstIndex(where: { $0.id == actionId }) else { return }
            message.actions[index].presentation = presentation
        }
    }

    @discardableResult
    mutating func expireActionPresentation(
        messageId: String,
        actionId: String,
        expiresAt: String
    ) -> Bool {
        guard let messageIndex = messages.firstIndex(where: { $0.id == messageId }),
              let actionIndex = messages[messageIndex].actions.firstIndex(where: { $0.id == actionId }),
              messages[messageIndex].actions[actionIndex].presentation?.expiresAt == expiresAt else { return false }
        messages[messageIndex].actions[actionIndex].presentation = nil
        return true
    }

    mutating func setFollowups(messageId: String, followups: [ApiAgentV2FollowUp]) {
        mutateMessage(id: messageId) { $0.followups = followups }
    }

    mutating func finalizeStreamingMessages(status: AgentV2NativeMessageStatus = .complete) {
        for index in messages.indices {
            messages[index].finalize(status: status)
        }
    }

    mutating func clearActionPresentations() {
        for messageIndex in messages.indices {
            for actionIndex in messages[messageIndex].actions.indices {
                messages[messageIndex].actions[actionIndex].presentation = nil
            }
        }
    }

    @discardableResult
    mutating func reconcileOptimisticInputMessage(localId: String?, canonicalId: String?) -> Bool {
        guard let localId, let canonicalId, localId != canonicalId,
              let localIndex = messages.firstIndex(where: { $0.id == localId }) else { return false }
        if messages.contains(where: { $0.id == canonicalId }) {
            messages.remove(at: localIndex)
        } else {
            messages[localIndex].id = canonicalId
        }
        return true
    }

    private mutating func mutateMessage(
        id: String,
        _ mutate: (inout AgentV2NativeMessage) -> Void
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[index])
    }
}

enum AgentV2DateParser {
    private static let fractionalFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let basicFormat = Date.ISO8601FormatStyle()

    static func date(_ value: String) -> Date {
        (try? fractionalFormat.parse(value)) ?? (try? basicFormat.parse(value)) ?? .distantPast
    }
}
