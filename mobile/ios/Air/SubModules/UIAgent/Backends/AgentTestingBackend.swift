import Foundation
import WalletContext

@MainActor
final class AgentTestingBackend: AgentBackend {
    let kind: AgentBackendKind = .testing

    private weak var context: AgentBackendContext?
    private var pendingReplyTasks: [UUID: Task<Void, Never>] = [:]

    func attach(to context: AgentBackendContext) {
        self.context = context
    }

    func detach() {
        reset()
        context = nil
    }

    func loadInitialTimeline(animated: Bool) {
        context?.replaceTimeline(with: Self.mockItems, animated: animated)
    }

    func loadHints(animated: Bool) {
        let hints = Self.mockHints(for: LocalizationSupport.shared.langCode)
        context?.setHints(hints, animated: animated)
    }

    func prepareForEditing(_ editContext: AgentBackendEditContext) {
        cancelPendingReplies()
    }

    func didSendUserMessage(_ text: String, editContext: AgentBackendEditContext?) {
        guard let context else { return }

        let typingIndicator = AgentTypingIndicator()
        context.append(.typingIndicator(typingIndicator), animated: true)

        let reply = Self.simulatedReply(for: text, index: context.itemIDs.count)
        let replyAction = Self.simulatedAction(for: text)
        let taskID = UUID()
        let task = Task { [weak self] in
            defer { self?.pendingReplyTasks[taskID] = nil }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, let context = self.context else { return }

            let frames = Self.streamingFrames(for: reply)
            guard let firstFrame = frames.first else { return }

            let message = AgentMessage(
                role: .assistant,
                text: firstFrame,
                isStreaming: true,
                action: replyAction
            )
            let messageID = message.id
            context.replaceItem(id: typingIndicator.id, with: .message(message), animated: true)

            for frame in frames.dropFirst() {
                try? await Task.sleep(for: Self.streamingDelay(for: frame))
                guard !Task.isCancelled, var currentMessage = context.message(for: messageID) else { return }
                currentMessage.text = frame
                context.updateMessage(currentMessage, animated: false, scrollToBottom: true)
            }

            guard var completedMessage = context.message(for: messageID) else { return }
            completedMessage.isStreaming = false
            context.updateMessage(completedMessage, animated: false, scrollToBottom: true)
        }
        pendingReplyTasks[taskID] = task
    }

    func reset() {
        cancelPendingReplies()
    }

    private func cancelPendingReplies() {
        pendingReplyTasks.values.forEach { $0.cancel() }
        pendingReplyTasks.removeAll()
    }

    private static let mockItems: [AgentTimelineItem] = [
        .message(
            AgentMessage(
                role: .system,
                text: "Yesterday 6:41 PM",
                isStreaming: false,
                systemStyle: .dateTime(date: "Yesterday", time: "6:41 PM")
            )
        ),
        .message(
            AgentMessage(
                role: .assistant,
                text: "I can summarize balances, explain recent activity, and guide you to the right screen with deeplinks.",
                isStreaming: false
            )
        ),
        .message(
            AgentMessage(
                role: .user,
                text: "Take me to staking for this wallet.",
                isStreaming: false
            )
        ),
        .message(
            AgentMessage(
                role: .system,
                text: "Account switched to Savings Wallet",
                isStreaming: false
            )
        ),
        .message(
            AgentMessage(
                role: .assistant,
                text: "You are now on Savings Wallet. I found the staking entry point and prepared a deeplink for it below.",
                isStreaming: false,
                action: AgentMessageAction(
                    title: "Open Earn",
                    url: URL(string: "\(SELF_PROTOCOL)stake")!
                )
            )
        ),
        .message(
            AgentMessage(
                role: .system,
                text: "Today 9:41",
                isStreaming: false,
                systemStyle: .dateTime(date: "Today", time: "9:41")
            )
        ),
        .message(
            AgentMessage(
                role: .user,
                text: "Show me TON details and price context.",
                isStreaming: false
            )
        ),
        .message(
            AgentMessage(
                role: .assistant,
                text: "TON remains one of the core assets in this wallet. I can open the token screen directly from here.",
                isStreaming: false,
                action: AgentMessageAction(
                    title: "Open TON",
                    url: URL(string: "\(SELF_PROTOCOL)token/\(TONCOIN_SLUG)")!
                )
            )
        ),
        .message(
            AgentMessage(
                role: .assistant,
                text: "System rows are centered, assistant replies can stream, and actions can appear below a response when a deeplink is available.",
                isStreaming: false
            )
        ),
    ]

    private static func simulatedReply(for input: String, index: Int) -> String {
        let cannedReplies = [
            "I can help with balances, swaps, staking, and recent activity. We can turn this into a real agent flow next.",
            "This is mocked data for now, but the collection view and composer are already wired for a live conversation feed.",
            "If you want, the next step is typing indicators, streaming updates, and hooking the messages into the Agent tab navigation."
        ]

        if input.contains("?") {
            return "Short answer: yes. This screen is ready to evolve into a real chat surface once we connect it to the backend."
        }

        return cannedReplies[index % cannedReplies.count]
    }

    private static func simulatedAction(for input: String) -> AgentMessageAction? {
        let lowercasedInput = input.lowercased()
        if lowercasedInput.contains("ton") {
            return AgentMessageAction(
                title: "Open TON",
                url: URL(string: "\(SELF_PROTOCOL)token/\(TONCOIN_SLUG)")!
            )
        }
        if lowercasedInput.contains("earn") || lowercasedInput.contains("stake") {
            return AgentMessageAction(
                title: "Open Earn",
                url: URL(string: "\(SELF_PROTOCOL)stake")!
            )
        }
        return nil
    }

    private static func streamingFrames(for text: String) -> [String] {
        var frames: [String] = []
        var currentText = ""
        var charactersSinceFrame = 0

        for character in text {
            currentText.append(character)
            charactersSinceFrame += 1

            let shouldFlush = charactersSinceFrame >= 6 || character.isSentenceBoundary || character == "\n"
            if shouldFlush {
                frames.append(currentText)
                charactersSinceFrame = 0
            }
        }

        if frames.last != currentText {
            frames.append(currentText)
        }

        return frames
    }

    private static func streamingDelay(for frame: String) -> Duration {
        if frame.last?.isSentenceBoundary == true {
            .milliseconds(140)
        } else {
            .milliseconds(70)
        }
    }

    private static func mockHints(for langCode: String) -> [AgentHint] {
        if langCode == "ru" {
            return [
                AgentHint(
                    id: "ru-0",
                    title: "Проверь крипторынок",
                    subtitle: "включая TON и основные токены",
                    prompt: "Дай мне краткий обзор крипторынка с фокусом на TON, BTC, ETH и главные тренды сегодня."
                ),
                AgentHint(
                    id: "ru-1",
                    title: "Отслеживай мой портфель",
                    subtitle: "с графиками и разбивкой по токенам",
                    prompt: "Проанализируй мой кошелёк, объясни текущую структуру портфеля, самые крупные позиции и что в нём выделяется."
                ),
                AgentHint(
                    id: "ru-2",
                    title: "Добавить токены",
                    subtitle: "по адресу, QR-коду или банковской карте",
                    prompt: "Открой экран получения средств."
                ),
                AgentHint(
                    id: "ru-3",
                    title: "Покажи варианты стейкинга",
                    subtitle: "для наград в TON и MY",
                    prompt: "Объясни стейкинг в MyTonWallet, включая стейкинг TON и MY, награды и риски."
                )
            ]
        }

        return [
            AgentHint(
                id: "en-0",
                title: "Check the crypto market",
                subtitle: "including TON and major tokens",
                prompt: "Give me a quick crypto market overview, with focus on TON, BTC, ETH and major trends today."
            ),
            AgentHint(
                id: "en-1",
                title: "Track my portfolio",
                subtitle: "with charts and token breakdown",
                prompt: "Analyze my wallet portfolio, explain the current allocation, biggest positions and what stands out."
            ),
            AgentHint(
                id: "en-2",
                title: "Add tokens",
                subtitle: "via address, QR or bank card",
                prompt: "Open my Receive screen."
            ),
            AgentHint(
                id: "en-3",
                title: "Show me staking options",
                subtitle: "for TON and MY rewards",
                prompt: "Explain staking in MyTonWallet, including how TON and MY staking works, rewards and risks."
            )
        ]
    }
}
