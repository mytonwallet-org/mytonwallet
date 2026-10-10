#if DEBUG

import UIKit
import WalletContext

public enum AgentSuggestionsLab {
    @MainActor
    public static func makeViewController(isEmpty: Bool) -> UIViewController {
        AgentVC(model: AgentModel(backend: AgentSuggestionsLabBackend(isEmpty: isEmpty)))
    }
}

@MainActor
private final class AgentSuggestionsLabBackend: AgentBackend {
    private let isEmpty: Bool
    private var context: AgentBackendContext?
    private var streamTask: Task<Void, Never>?
    private var didLoad = false
    var canSendMessages: Bool { streamTask == nil }

    private static let titles = [
        "Track my portfolio value",
        "Learn how to swap tokens",
        "Show me Gram staking options",
        "Learn how to keep my wallet safely",
        "Add tokens via address, QR or bank card",
    ]
    private static let longFollowup = "Which of these news stories matters most for the price of Gram this week?"
    private var followups: [AgentMessageControl] {
        (Self.titles.prefix(2) + [Self.longFollowup]).enumerated().map { index, title in
            AgentMessageControl(id: "followup:\(index)", title: title, isEnabled: true, kind: .followup)
        }
    }

    init(isEmpty: Bool) { self.isEmpty = isEmpty }
    func attach(to context: AgentBackendContext) { self.context = context }
    func detach() { stop(); context = nil }
    func stop() { streamTask?.cancel(); streamTask = nil }
    func prepareForEditing(_ editContext: AgentBackendEditContext) {}

    func loadHints(animated: Bool) {
        context?.setHints(Self.titles.enumerated().map { index, title in
            AgentHint(id: "hint:\(index)", title: title, subtitle: "Suggestion", prompt: title)
        }, animated: animated)
        guard !didLoad else { return }
        didLoad = true
        guard !isEmpty else { return }
        var items: [AgentTimelineItem] = []
        for index in 0..<4 {
            items.append(.message(AgentMessage(role: .user, text: Self.titles[index], isStreaming: false)))
            items.append(.message(AgentMessage(role: .assistant, text: Self.answer,
                                              isStreaming: false, controls: followups, renderingPolicy: .agentV2Safe)))
        }
        context?.replaceTimeline(with: items, animated: false)
    }

    func didSendUserMessage(_ text: String, userMessageID: AgentItemID, source: AgentBackendSendSource,
                            editContext: AgentBackendEditContext?) {
        let indicator = AgentTypingIndicator()
        context?.append(.typingIndicator(indicator), animated: true)
        streamTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(450))
                guard let self else { return }
                var message = AgentMessage(role: .assistant, text: "", isStreaming: true, renderingPolicy: .agentV2Safe)
                self.context?.replaceItem(id: indicator.id, with: .message(message), animated: true)
                let text = Self.answer + "\n\n" + Self.answer
                for count in stride(from: 12, to: text.count, by: 12) {
                    try await Task.sleep(for: .milliseconds(65))
                    message.text = String(text.prefix(count))
                    self.context?.updateMessage(message, animated: false, scrollToBottom: false)
                }
                message.text = text
                message.isStreaming = false
                message.controls = self.followups
                self.context?.updateMessage(message, animated: false, scrollToBottom: false)
                self.streamTask = nil
                self.context?.notifyStateChanged()
            } catch {}
        }
        context?.notifyStateChanged()
    }

    func performControl(messageID: AgentItemID, controlID: String) {
        guard canSendMessages, let followup = followups.first(where: { $0.id == controlID }) else { return }
        context?.sendMessage(followup.title, source: .followup(messageID: messageID.uuidString, followupID: controlID))
    }

    func clearConversation(completion: @escaping (Bool) -> Void) { completion(true) }

    private static let answer = """
    **Your wallet, at a glance**

    You can review your assets, explore supported tokens, or learn how swaps work.

    A swap exchanges one token for another. Before you confirm, review the amount, network fee, and minimum amount you will receive.

    • Choose the token you want to exchange.
    • Select the token you want to receive.
    • Review the quote in your wallet.

    You stay in control of the final confirmation.
    """
}

#endif
