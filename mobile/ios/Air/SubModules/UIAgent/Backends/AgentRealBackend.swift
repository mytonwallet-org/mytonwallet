import Foundation
import WalletContext
import WalletCore

private let log = Log("AgentRealBackend")
private let clientIDDefaultsKey = "ui_agent.real_backend.client_id"

@MainActor
final class AgentRealBackend: AgentBackend {
    let kind: AgentBackendKind = .real

    private weak var context: AgentBackendContext?
    private let transport: AgentRealBackendTransport
    private let defaults: UserDefaults
    private let accountContext = AccountContext(source: .current)
    private var pendingReplyTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingHintsTask: Task<Void, Never>?
    private var clientID: String

    init(
        transport: AgentRealBackendTransport = AgentHTTPStreamingTransport(endpoint: URL(string: "https://agent.mytonwallet.org/api/message")!),
        defaults: UserDefaults = .standard
    ) {
        self.transport = transport
        self.defaults = defaults
        self.clientID = Self.loadOrCreateClientID(from: defaults)
    }

    func attach(to context: AgentBackendContext) {
        self.context = context
    }

    func detach() {
        reset()
        context = nil
    }

    func loadInitialTimeline(animated: Bool) {
        context?.replaceTimeline(with: [], animated: animated)
    }

    func loadHints(animated: Bool) {
        pendingHintsTask?.cancel()
        let langCode = LocalizationSupport.shared.langCode
        pendingHintsTask = Task { [weak self] in
            defer { self?.pendingHintsTask = nil }
            do {
                guard let self else { return }
                let hints = try await self.transport.loadHints(langCode: langCode)
                guard !Task.isCancelled, let context = self.context else { return }
                context.setHints(hints, animated: animated)
            } catch {
                guard !Task.isCancelled else { return }
                log.error("load hints failed langCode=\(langCode, .public) error=\(error, .public)")
            }
        }
    }

    func prepareForEditing(_ editContext: AgentBackendEditContext) {
        cancelPendingReplies()
    }

    func didSendUserMessage(_ text: String, editContext: AgentBackendEditContext?) {
        guard let context else { return }

        let typingIndicator = AgentTypingIndicator()
        context.append(.typingIndicator(typingIndicator), animated: true)

        let taskID = UUID()
        let request = AgentRealBackendRequest(
            clientId: clientID,
            text: text,
            context: AgentRequestContext.current(using: accountContext, editContext: editContext)
        )
        log.info("send start clientId=\(clientID, .public) textChars=\(text.count) text=\(text.prefix(50), .redacted)")
        let task = Task { [weak self] in
            defer { self?.pendingReplyTasks[taskID] = nil }
            await self?.streamReply(request: request, typingIndicatorID: typingIndicator.id)
        }
        pendingReplyTasks[taskID] = task
    }

    func reset() {
        cancelPendingReplies()
        pendingHintsTask?.cancel()
        pendingHintsTask = nil
        clientID = Self.rotateClientID(in: defaults)
        log.info("reset rotated clientId=\(clientID, .public)")
    }

    private func cancelPendingReplies() {
        pendingReplyTasks.values.forEach { $0.cancel() }
        pendingReplyTasks.removeAll()
    }

    private func streamReply(request: AgentRealBackendRequest, typingIndicatorID: AgentItemID) async {
        guard context != nil else { return }

        var typingIndicatorIsVisible = true
        var streamedMessageID: AgentItemID?
        var streamedText = ""

        do {
            for try await chunk in transport.streamReply(request: request) {
                guard !Task.isCancelled, self.context != nil else { return }
                let previousCount = streamedText.count
                streamedText.append(chunk)

                let allFrames = Self.streamingFrames(for: streamedText)
                let newFrames = allFrames.enumerated().filter { $0.element.count > previousCount }
                for (_, frame) in newFrames {
                    guard !Task.isCancelled, let context = self.context else { return }

                    if let streamedMessageID, var message = context.message(for: streamedMessageID) {
                        message.text = frame
                        message.isStreaming = true
                        log.info("parsed update messageId=\(streamedMessageID, .public) chars=\(frame.count) text=\(frame.prefix(50), .redacted)")
                        context.updateMessage(message, animated: false, scrollToBottom: true)
                    } else {
                        let message = AgentMessage(
                            role: .assistant,
                            text: frame,
                            isStreaming: true
                        )
                        streamedMessageID = message.id
                        log.info("parsed create messageId=\(message.id, .public) chars=\(frame.count) text=\(frame.prefix(50), .redacted)")
                        if typingIndicatorIsVisible {
                            context.replaceItem(id: typingIndicatorID, with: .message(message), animated: true)
                            typingIndicatorIsVisible = false
                        } else {
                            context.append(.message(message), animated: true)
                        }
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
                            text: AgentBackendMessages.emptyResponseMessage,
                            isStreaming: false
                        )
                    ),
                    animated: true
                )
                return
            }

            guard let streamedMessageID, var finalMessage = context.message(for: streamedMessageID) else { return }
            let parsedMessage = Self.parseMessage(streamedText)
            finalMessage.text = parsedMessage.text
            finalMessage.action = parsedMessage.action
            finalMessage.isStreaming = false
            log.info(
                "parsed final messageId=\(streamedMessageID, .public) textChars=\(parsedMessage.text.count) text=\(parsedMessage.text.prefix(50), .redacted) actionTitle=\(parsedMessage.action?.title ?? "nil", .redacted) actionURL=\(parsedMessage.action?.url.absoluteString ?? "nil", .redacted)"
            )
            context.updateMessage(finalMessage, animated: false, scrollToBottom: true)
        } catch {
            log.error("stream failed clientId=\(request.clientId, .public) error=\(error, .public)")
            guard !Task.isCancelled, let context = self.context else { return }
            let systemMessage = AgentMessage(
                role: .system,
                text: (error as? LocalizedError)?.errorDescription ?? AgentBackendMessages.unavailableMessage,
                isStreaming: false
            )
            if typingIndicatorIsVisible {
                context.replaceItem(id: typingIndicatorID, with: .message(systemMessage), animated: true)
            } else {
                context.append(.message(systemMessage), animated: true)
            }
        }
    }

    private static func loadOrCreateClientID(from defaults: UserDefaults) -> String {
        if let existingClientID = defaults.string(forKey: clientIDDefaultsKey),
           !existingClientID.isEmpty {
            return existingClientID
        }

        let newClientID = UUID().uuidString
        defaults.set(newClientID, forKey: clientIDDefaultsKey)
        return newClientID
    }

    private static func rotateClientID(in defaults: UserDefaults) -> String {
        let newClientID = UUID().uuidString
        defaults.set(newClientID, forKey: clientIDDefaultsKey)
        return newClientID
    }
}
