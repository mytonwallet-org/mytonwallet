#if canImport(FoundationModels)
import Foundation
import FoundationModels
import MyAgent
import WalletContext
import WalletCore

private let log = Log("AgentHybridBackend")

private enum AgentHybridBackendCopy {
    static let emptyResponseMessage = "The Agent returned an empty response."
    static let fallbackErrorMessage = "Something went wrong. Please try again."
}

private enum AgentHybridBackendMetrics {
    static let clientIDDefaultsKey = "ui_agent.hybrid_backend.client_id"
    static let trailingMessageCharacters = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: "\u{00A0}\u{200B}\u{200C}\u{200D}\u{FEFF}")
    )
}

@available(iOS 26.0, *)
@MainActor
final class AgentHybridBackend: AgentBackend {
    let kind: AgentBackendKind = .hybrid

    private let accountContext = AccountContext(source: .current)
    private weak var context: AgentBackendContext?
    private let agent: MyAgent
    private let transport: AgentRealBackendTransport
    private let defaults: UserDefaults
    private var clientID: String
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]
    private var conversationID = UUID().uuidString

    init(
        transport: AgentRealBackendTransport = AgentHTTPStreamingTransport(
            endpoint: URL(string: "https://agent.mytonwallet.org/api/message")!
        ),
        defaults: UserDefaults = .standard
    ) {
        self.agent = MyAgent(llm: FoundationModelsLLMProvider())
        self.transport = transport
        self.defaults = defaults
        self.clientID = Self.loadOrCreateClientID(from: defaults)
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

    func loadHints(animated: Bool) {
        let langCode = LocalizationSupport.shared.langCode
        Task { [weak self] in
            guard let self else { return }
            do {
                let hints = try await self.transport.loadHints(langCode: langCode)
                guard !Task.isCancelled, let context = self.context else { return }
                context.setHints(hints, animated: animated)
            } catch {
                log.error("load hints failed error=\(error, .public)")
            }
        }
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
            await self?.classifyAndRoute(
                text,
                typingIndicatorID: typingIndicator.id,
                editContext: editContext
            )
        }
        pendingTasks[taskID] = task
    }

    func reset() {
        cancelPendingTasks()
        clientID = Self.rotateClientID(in: defaults)
        let agent = self.agent
        let conversationID = self.conversationID
        Task { await agent.clearHistory(conversationId: conversationID) }
        log.info("reset rotated clientId=\(clientID, .public) conversationId=\(conversationID, .public)")
        self.conversationID = UUID().uuidString
    }

    // MARK: - Routing

    private func classifyAndRoute(
        _ text: String,
        typingIndicatorID: AgentItemID,
        editContext: AgentBackendEditContext?
    ) async {
        guard context != nil else { return }
        let requestContext = AgentRequestContext.current(using: accountContext)
        let userAddresses = requestContext.userAddresses ?? []
        let savedAddresses = requestContext.savedAddresses ?? []

        do {
            let classification = try await agent.classify(
                message: text,
                userAddresses: userAddresses,
                savedAddresses: savedAddresses
            )
            guard !Task.isCancelled else { return }

            let needsRealAgent = classification.intents.contains { intent in
                intent.type == .question || intent.type == .searchNews
            }

            if needsRealAgent {
                log.info("hybrid routing to real agent conversationId=\(conversationID, .public)")
                await streamFromRealAgent(text, typingIndicatorID: typingIndicatorID, editContext: editContext)
            } else {
                log.info("hybrid processing locally conversationId=\(conversationID, .public)")
                await processLocally(text,
                                     typingIndicatorID: typingIndicatorID,
                                     classification: classification,
                                     userAddresses: userAddresses,
                                     savedAddresses: savedAddresses)
            }
        } catch {
            log.error("classify failed, falling back to real agent conversationId=\(conversationID, .public) error=\(error, .public)")
            guard !Task.isCancelled else { return }
            await streamFromRealAgent(text, typingIndicatorID: typingIndicatorID, editContext: editContext)
        }
    }

    // MARK: - Local Processing

    private func processLocally(_ text: String,
                                typingIndicatorID: AgentItemID,
                                classification: ClassificationResult,
                                userAddresses: [any AgentUserAddress],
                                savedAddresses: [any AgentUserAddress] = []) async {
        let (results, _) = await agent.processClassified(
            classification: classification,
            message: text,
            userAddresses: userAddresses,
            savedAddresses: savedAddresses,
            conversationId: conversationID
        )

        guard !Task.isCancelled, let context = self.context else { return }

        let (messageText, action) = AgentLocalBackend.formatResults(results)
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
    }

    // MARK: - Real Agent Streaming

    private func streamFromRealAgent(
        _ text: String,
        typingIndicatorID: AgentItemID,
        editContext: AgentBackendEditContext?
    ) async {
        guard context != nil else { return }

        let request = AgentRealBackendRequest(
            clientId: clientID,
            text: text,
            context: AgentRequestContext.current(using: accountContext, editContext: editContext)
        )

        var typingIndicatorIsVisible = true
        var streamedMessageID: AgentItemID?
        var streamedText = ""

        do {
            for try await chunk in transport.streamReply(request: request) {
                guard !Task.isCancelled, let context = self.context else { return }
                streamedText.append(chunk)

                if let streamedMessageID, var message = context.message(for: streamedMessageID) {
                    message.text = streamedText
                    message.isStreaming = true
                    context.updateMessage(message, animated: false, scrollToBottom: true)
                } else {
                    let message = AgentMessage(
                        role: .assistant,
                        text: streamedText,
                        isStreaming: true
                    )
                    streamedMessageID = message.id
                    if typingIndicatorIsVisible {
                        context.replaceItem(id: typingIndicatorID, with: .message(message), animated: true)
                        typingIndicatorIsVisible = false
                    } else {
                        context.append(.message(message), animated: true)
                    }
                }
            }

            guard !Task.isCancelled, let context = self.context else { return }

            if typingIndicatorIsVisible {
                context.replaceItem(
                    id: typingIndicatorID,
                    with: .message(
                        AgentMessage(
                            role: .system,
                            text: AgentHybridBackendCopy.emptyResponseMessage,
                            isStreaming: false
                        )
                    ),
                    animated: true
                )
                return
            }

            guard let streamedMessageID, var finalMessage = context.message(for: streamedMessageID) else { return }
            let parsed = Self.parseStreamedMessage(streamedText)
            finalMessage.text = parsed.text
            finalMessage.action = parsed.action
            finalMessage.isStreaming = false
            context.updateMessage(finalMessage, animated: false, scrollToBottom: true)
        } catch {
            log.error("stream failed clientId=\(clientID, .public) error=\(error, .public)")
            guard !Task.isCancelled, let context = self.context else { return }
            let systemMessage = AgentMessage(
                role: .system,
                text: (error as? LocalizedError)?.errorDescription ?? AgentHybridBackendCopy.fallbackErrorMessage,
                isStreaming: false
            )
            if typingIndicatorIsVisible {
                context.replaceItem(id: typingIndicatorID, with: .message(systemMessage), animated: true)
            } else {
                context.append(.message(systemMessage), animated: true)
            }
        }
    }

    // MARK: - Helpers

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
        let messages = editContext.history.map { message in
            ChatMessage(
                role: message.role == .user ? .user : .assistant,
                content: message.text
            )
        }
        await agent.replaceHistory(conversationId: conversationID, messages: messages)
    }

    private static func parseStreamedMessage(_ rawText: String) -> (text: String, action: AgentMessageAction?) {
        let trimmedText = rawText.trimmingCharacters(in: AgentHybridBackendMetrics.trailingMessageCharacters)
        guard let match = deeplinkRegex.matches(
            in: trimmedText,
            options: [],
            range: NSRange(trimmedText.startIndex..., in: trimmedText)
        ).last else {
            return (trimmedText, nil)
        }

        guard let fullRange = Range(match.range(at: 0), in: trimmedText),
              let titleRange = Range(match.range(at: 1), in: trimmedText),
              let urlRange = Range(match.range(at: 2), in: trimmedText) else {
            return (trimmedText, nil)
        }

        let title = String(trimmedText[titleRange])
        let urlString = String(trimmedText[urlRange])
        guard let url = URL(string: urlString) else {
            return (trimmedText, nil)
        }

        var messageText = trimmedText
        messageText.removeSubrange(fullRange)
        messageText = messageText.trimmingCharacters(in: AgentHybridBackendMetrics.trailingMessageCharacters)

        return (messageText, AgentMessageAction(title: title, url: url))
    }

    private static var deeplinkRegex: NSRegularExpression = {
        let escapedProtocol = NSRegularExpression.escapedPattern(for: SELF_PROTOCOL)
        return try! NSRegularExpression(pattern: #"\[([^\]]+)\]\s*\((\#(escapedProtocol)[^)\s]+)\)$"#)
    }()

    private static func loadOrCreateClientID(from defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: AgentHybridBackendMetrics.clientIDDefaultsKey),
           !existing.isEmpty {
            return existing
        }
        let newID = UUID().uuidString
        defaults.set(newID, forKey: AgentHybridBackendMetrics.clientIDDefaultsKey)
        return newID
    }

    private static func rotateClientID(in defaults: UserDefaults) -> String {
        let newID = UUID().uuidString
        defaults.set(newID, forKey: AgentHybridBackendMetrics.clientIDDefaultsKey)
        return newID
    }
}

@available(iOS 26.0, *)
extension AgentHybridBackend: WalletCoreData.EventsObserver {
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .tokensChanged:
            syncTokens()
        default:
            break
        }
    }
}
#endif
