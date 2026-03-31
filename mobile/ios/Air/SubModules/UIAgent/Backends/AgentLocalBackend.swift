#if canImport(FoundationModels)
import Foundation
import FoundationModels
import MyAgent
import WalletContext
import WalletCore

private let log = Log("AgentLocalBackend")

extension ApiToken: AgentAsset {}
extension AgentAddressInfo: AgentUserAddress {}
extension AgentBackendConversationMessage {
    var chatMessage: ChatMessage {
        ChatMessage(
            role: role == .user ? .user : .assistant,
            content: text
        )
    }
}

private enum AgentLocalBackendCopy {
    static let emptyResponseMessage = "The Agent returned an empty response."
    static let fallbackErrorMessage = "Something went wrong. Please try again."
}

@available(iOS 26.0, *)
@MainActor
final class AgentLocalBackend: AgentBackend {
    let kind: AgentBackendKind = .local

    private let accountContext = AccountContext(source: .current)

    private weak var context: AgentBackendContext?
    private let agent: MyAgent
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]
    private var conversationID = UUID().uuidString

    init() {
        self.agent = MyAgent(llm: FoundationModelsLLMProvider())
        WalletCoreData.add(eventObserver: self)
        syncTokens()
    }

    func attach(to context: AgentBackendContext) {
        self.context = context
    }

    func detach() {
        WalletCoreData.remove(observer: self)
        reset()
        context = nil
    }

    func loadInitialTimeline(animated: Bool) {
        context?.replaceTimeline(with: [], animated: animated)
    }

    func prepareForEditing(_ editContext: AgentBackendEditContext) {
        cancelPendingTasks()
    }

    func didSendUserMessage(_ text: String, editContext: AgentBackendEditContext?) {
        guard let context else { return }

        let typingIndicator = AgentTypingIndicator()
        context.append(.typingIndicator(typingIndicator), animated: true)

        let taskID = UUID()
        log.info("send start conversationId=\(conversationID, .public) textChars=\(text.count) text=\(text, .redacted)")
        let task = Task { [weak self] in
            defer { self?.pendingTasks[taskID] = nil }
            if let self, let editContext {
                await self.rebuildHistory(from: editContext)
            }
            await self?.processMessage(text, typingIndicatorID: typingIndicator.id)
        }
        pendingTasks[taskID] = task
    }

    func reset() {
        cancelPendingTasks()
        let agent = self.agent
        let conversationID = self.conversationID
        Task { await agent.clearHistory(conversationId: conversationID) }
        log.info("reset conversationId=\(conversationID, .public)")
        self.conversationID = UUID().uuidString
    }

    private func syncTokens() {
        let tokens = Array(TokenStore.tokens.values)
        let agent = self.agent
        Task { await agent.tokenResolver.updateAssets(tokens) }
    }

    private func cancelPendingTasks() {
        pendingTasks.values.forEach { $0.cancel() }
        pendingTasks.removeAll()
    }

    private func rebuildHistory(from editContext: AgentBackendEditContext) async {
        await agent.replaceHistory(
            conversationId: conversationID,
            messages: editContext.history.map(\.chatMessage)
        )
    }

    private func processMessage(_ text: String, typingIndicatorID: AgentItemID) async {
        guard context != nil else { return }
        let requestContext = AgentRequestContext.current(using: accountContext)
        let userAddresses = requestContext.userAddresses ?? []
        let savedAddresses = requestContext.savedAddresses ?? []
        do {
            let (results, _) = try await agent.process(
                message: text,
                userAddresses: userAddresses,
                savedAddresses: savedAddresses,
                conversationId: conversationID
            )

            guard !Task.isCancelled, let context = self.context else { return }

            let (messageText, action) = Self.formatResults(results)
            log.info("reply conversationId=\(conversationID, .public) textChars=\(messageText.count) text=\(messageText, .redacted) actionTitle=\(action?.title ?? "nil", .redacted)")

            context.replaceItem(
                id: typingIndicatorID,
                with: .message(
                    AgentMessage(
                        role: .assistant,
                        text: messageText,
                        isStreaming: false,
                        action: action
                    )
                ),
                animated: true
            )
        } catch {
            log.error("process failed conversationId=\(conversationID, .public) error=\(error, .public)")
            guard !Task.isCancelled, let context = self.context else { return }
            context.replaceItem(
                id: typingIndicatorID,
                with: .message(
                    AgentMessage(
                        role: .system,
                        text: (error as? LocalizedError)?.errorDescription ?? AgentLocalBackendCopy.fallbackErrorMessage,
                        isStreaming: false
                    )
                ),
                animated: true
            )
        }
    }

    static func formatResults(_ results: [IntentResult]) -> (String, AgentMessageAction?) {
        var textParts: [String] = []
        var action: AgentMessageAction?

        for result in results {
            if let message = result.message {
                textParts.append(message)
            }
            if action == nil, let deeplinks = result.deeplinks, let first = deeplinks.first,
               let url = URL(string: first.url) {
                action = AgentMessageAction(title: first.title, url: url)
            }
        }

        let text = textParts.joined(separator: "\n\n")
        return (text.isEmpty ? AgentLocalBackendCopy.emptyResponseMessage : text, action)
    }
}

@available(iOS 26.0, *)
extension AgentLocalBackend: WalletCoreData.EventsObserver {
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .tokensChanged:
            syncTokens()
        default:
            break
        }
    }
}

@available(iOS 26.0, *)
struct FoundationModelsLLMProvider: LLMProvider {
    func generate(systemPrompt: String, userMessage: String) async throws -> String {
        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: userMessage)
        return response.content
    }

    func generate(systemPrompt: String, messages: [ChatMessage]) async throws -> String {
        let session = LanguageModelSession(instructions: systemPrompt)

        for message in messages.dropLast() where message.role == .user {
            _ = try await session.respond(to: message.content)
        }

        let lastUserMessage = messages.last(where: { $0.role == .user })?.content ?? ""
        let response = try await session.respond(to: lastUserMessage)
        return response.content
    }
}
#endif
