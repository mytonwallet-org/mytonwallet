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

        let response = Self.simulatedResponse(for: text, index: context.itemIDs.count)
        let taskID = UUID()
        let task = Task { [weak self] in
            defer { self?.pendingReplyTasks[taskID] = nil }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, let context = self.context else { return }

            let frames = Self.streamingFrames(for: response.text)
            guard let firstFrame = frames.first else { return }

            let message = AgentMessage(
                role: .assistant,
                text: firstFrame,
                isStreaming: true,
                action: response.action
            )
            let messageID = message.id
            context.replaceItem(id: typingIndicator.id, with: .message(message), animated: true)

            for frameIndex in 1..<frames.count {
                let frame = frames[frameIndex]
                try? await Task.sleep(for: Self.streamingDelay(frameIndex: frameIndex, frame: frame))
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

    private static func simulatedResponse(for input: String, index: Int) -> (text: String, action: AgentMessageAction?) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fixtureIndex = Int(trimmedInput),
           fixtureIndex >= 1,
           fixtureIndex <= fixtureReplies.count {
            let parsed = Self.parseMessage(fixtureReplies[fixtureIndex - 1])
            return (parsed.text, parsed.action)
        }

        let cannedReplies = [
            "I can help with balances, swaps, staking, and recent activity. We can turn this into a real agent flow next.",
            "This is mocked data for now, but the collection view and composer are already wired for a live conversation feed.",
            "If you want, the next step is typing indicators, streaming updates, and hooking the messages into the Agent tab navigation."
        ]

        if input.contains("?") {
            return (
                "Short answer: yes. This screen is ready to evolve into a real chat surface once we connect it to the backend.",
                simulatedAction(for: input)
            )
        }

        return (cannedReplies[index % cannedReplies.count], simulatedAction(for: input))
    }

    private static func simulatedAction(for input: String) -> AgentMessageAction? {
        let lowercasedInput = input.lowercased()
        if lowercasedInput.contains("gram") || lowercasedInput.contains("ton") {
            return AgentMessageAction(
                title: "Open GRAM",
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

    private static func mockHints(for langCode: String) -> [AgentHint] {
        if langCode == "ru" {
            return [
                AgentHint(
                    id: "ru-0",
                    title: "Проверь крипторынок",
                    subtitle: "включая GRAM и основные токены",
                    prompt: "Дай мне краткий обзор крипторынка с фокусом на GRAM, BTC, ETH и главные тренды сегодня."
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
                    subtitle: "для наград в GRAM и MY",
                    prompt: "Объясни стейкинг в MyTonWallet, включая стейкинг GRAM и MY, награды и риски."
                )
            ]
        }

        return [
            AgentHint(
                id: "en-0",
                title: "Check the crypto market",
                subtitle: "including GRAM and major tokens",
                prompt: "Give me a quick crypto market overview, with focus on GRAM, BTC, ETH and major trends today."
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
                subtitle: "for GRAM and MY rewards",
                prompt: "Explain staking in MyTonWallet, including how GRAM and MY staking works, rewards and risks."
            )
        ]
    }

    private static let fixtureReplies: [String] = [
        """
        # The market is slightly up today

        Bitcoin is +1.8%, Ethereum +2.3%, and Gram +3.1% in the last 24 hours.

        The Fear & Greed Index is currently 62 (Greed).

        Would you like a quick overview of your portfolio as well?
        
        Here is a **rich text** preview covering common Agent formatting cases.

        # Heading Level 1
        ## Heading Level 2
        ### Heading Level 3

        Plain paragraph with *italic*, **bold**, and `inline code`.

        Autodetected links: https://mytonwallet.io and http://example.com/path?q=agent

        Tildes: ~single~ and ~~double~~ and raw ~ character.

        ---
        Horizontal rule above (three dashes).

        Multiple paragraphs with spacing.

        Line with trailing spaces    

        Unicode: 🚀 TON 💎 中文 العربية ñ

        List-like lines:
        - Item one
        - Item two with **bold**

        Numbered lines:
        1. First step
        2. Second step

        Long token: https://very-long-domain-name.example.com/path/to/resource/with/many/segments?foo=bar&baz=qux

        The action button below should appear after streaming finishes.

        [Open Earn](\(SELF_PROTOCOL)stake)
        """,
        
        """
        **Block content parity test**

        iOS uses inline-only markdown. Web renders the blocks below properly. On iOS you should see mostly raw text.

        # Unordered list
        - TON balance: 12.5
        - GRAM balance: 1,024
        - USDT balance: 50.00

        # Ordered list
        1. Open Earn
        2. Choose a pool
        3. Confirm staking

        # Markdown link (not bare URL)
        Read the [Agent docs](https://docs.mytonwallet.io) for more.

        # Nested inline inside list item
        - Send **TON** to `UQ...abc` before deadline

        Compare this bubble with the same content on web.

        [Open Wallet](\(SELF_PROTOCOL)home)
        """,

        """
        **Streaming boundary stress test**

        Watch how partial markdown tokens render while chunks arrive:

        1. Bold opener: **partial bold text**
        2. Code opener: `partial code block`
        3. Italic opener: *partial italic text*
        4. Link mid-stream: [MyTonWallet](https://mytonwallet.io)
        5. Heading mid-stream: ## Live Update

        ---

        Edge cases:
        - Empty-looking line below:

        - Mixed `code` and **bold** in one line
        - Repeated asterisks: ***not a horizontal rule***
        - Backslashes before tilde: \\~escaped
        - CR/LF normalization is handled by the renderer.

        [Open GRAM](\(SELF_PROTOCOL)token/\(TONCOIN_SLUG))
        """,
        """
        **Links & special content**

        Markdown link: [Docs](https://docs.mytonwallet.io)
        Bare URL: https://t.me/mytonwallet
        Email-like: agent@mytonwallet.io (plain text, not a link)

        # Quick Summary
        Your balance overview would appear here in a real response.

        `TON` `GRAM` `USDT` inline tickers.

        ---
        Emoji paragraph: ✅ ❌ ⚠️ 🎉

        Right-to-left sample: مرحبا

        CJK sample: 钱包代理测试

        Final deeplink:

        [Open Receive](\(SELF_PROTOCOL)receive)
        """,
    ]
}
