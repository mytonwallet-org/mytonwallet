import Foundation

/// Main entry point for the MyAgent library.
///
/// Provides a high-level API that combines intent classification, knowledge-base Q&A,
/// news search, token resolution, and deep link generation.
///
/// ## Quick Start
/// ```swift
/// let classifier = MyAgent(llm: myLLMProvider)
/// let results = try await classifier.process(message: "Send 10 TON to UQ...")
/// ```
public struct MyAgent: Sendable {
    private let intentClassifier: IntentClassifier
    private let addressResolver: AddressResolver
    private let deeplinkBuilder: DeeplinkBuilder
    private let questionAnswerer: QuestionAnswerer
    private let newsAnswerer: NewsAnswerer
    private let chatHistory: ChatHistory
    private let i18n: I18n

    /// The token resolver used for deep link building.
    /// Call `await tokenResolver.updateAssets(...)` to provide token data.
    public let tokenResolver: TokenResolver

    /// Currency rates for price conversion.
    /// Call `await currencyRates.updateRates(...)` to provide rate data.
    public let currencyRates: CurrencyRates

    /// Knowledge base for Q&A.
    /// Call `await knowledgeBase.load(version:)` to download and load a specific version.
    public let knowledgeBase: KnowledgeBase

    /// Create a new classifier with the given LLM provider.
    ///
    /// - Parameters:
    ///   - llm: An LLM provider that handles prompts (classification, QA, news summary).
    ///   - tokenResolver: Custom token resolver (uses default if nil).
    ///   - knowledgeBase: Custom knowledge base (uses default if nil).
    ///   - currencyRates: Custom currency rates (uses default if nil).
    ///   - i18n: Custom i18n instance (uses default if nil).
    ///   - maxHistoryPairs: Max conversation pairs to keep per conversation (default: 3).
    public init(
        llm: LLMProvider,
        tokenResolver: TokenResolver? = nil,
        knowledgeBase: KnowledgeBase? = nil,
        currencyRates: CurrencyRates? = nil,
        i18n: I18n? = nil,
        maxHistoryPairs: Int = 3
    ) {
        let resolvedI18n = i18n ?? I18n()
        let resolvedTokenResolver = tokenResolver ?? TokenResolver()
        let resolvedKB = knowledgeBase ?? KnowledgeBase.shared
        let resolvedRates = currencyRates ?? CurrencyRates()

        self.tokenResolver = resolvedTokenResolver
        self.currencyRates = resolvedRates
        self.knowledgeBase = resolvedKB
        self.intentClassifier = IntentClassifier(llm: llm)
        self.addressResolver = AddressResolver(tokenResolver: resolvedTokenResolver)
        self.deeplinkBuilder = DeeplinkBuilder(tokenResolver: resolvedTokenResolver, currencyRates: resolvedRates, i18n: resolvedI18n)
        self.questionAnswerer = QuestionAnswerer(llm: llm, knowledgeBase: resolvedKB, i18n: resolvedI18n)
        self.newsAnswerer = NewsAnswerer(llm: llm, i18n: resolvedI18n)
        self.chatHistory = ChatHistory(maxPairs: maxHistoryPairs)
        self.i18n = resolvedI18n
    }

    /// Classify a message and process all intents into results.
    ///
    /// Flow:
    /// 1. Classify message into intents + detect language
    /// 2. Load conversation history
    /// 3. For each intent:
    ///    - `question` → retrieve from knowledge base + LLM answer (with history)
    ///    - `searchNews` → DuckDuckGo search + LLM summary (with history)
    ///    - action intents → build deep links
    /// 4. Save user message + assistant response to history
    ///
    /// - Parameters:
    ///   - message: The user's natural language message.
    ///   - userAddresses: The user's wallet addresses for context.
    ///   - conversationId: Identifier for tracking conversation history (e.g. user ID).
    ///                     Pass `nil` to disable history.
    ///   - lang: Fallback language if classifier can't detect (default: "en").
    /// - Returns: A tuple of (results, effectiveLanguage).
    public func process(
        message: String,
        userAddresses: [any AgentUserAddress] = [],
        conversationId: String? = nil,
        lang: String = "en",
        baseCurrency: String = "USD"
    ) async throws -> (results: [IntentResult], lang: String) {
        let classification = try await intentClassifier.classify(message: message, userAddresses: userAddresses)
        return await processClassified(
            classification: classification,
            message: message,
            userAddresses: userAddresses,
            conversationId: conversationId,
            lang: lang,
            baseCurrency: baseCurrency
        )
    }

    /// Process a pre-classified message without re-running classification.
    /// Use this when you already have a `ClassificationResult` from `classify()`.
    public func processClassified(
        classification: ClassificationResult,
        message: String,
        userAddresses: [any AgentUserAddress] = [],
        conversationId: String? = nil,
        lang: String = "en",
        baseCurrency: String = "USD"
    ) async -> (results: [IntentResult], lang: String) {
        let effectiveLang = classification.detectedLang.isEmpty ? lang : classification.detectedLang

        // Resolve named addresses to correct chain
        let resolvedIntents = await addressResolver.resolve(intents: classification.intents, userAddresses: userAddresses)

        // Load history
        let history: [ChatMessage]
        if let conversationId {
            history = await chatHistory.get(conversationId)
        } else {
            history = []
        }

        var results: [IntentResult] = []
        if let intent = resolvedIntents.first {
            switch intent.type {
            case .question:
                do {
                    let answer = try await questionAnswerer.answer(question: message, history: history, lang: effectiveLang)
                    results.append(IntentResult(type: "question", message: answer))
                } catch {
                    results.append(IntentResult(
                        type: "question",
                        message: i18n.t("error.noAnswer", lang: effectiveLang),
                        error: "llmError"
                    ))
                }

            case .searchNews:
                let query = intent.query ?? message
                do {
                    let summary = try await newsAnswerer.answer(query: query, history: history, lang: effectiveLang)
                    results.append(IntentResult(type: "searchNews", message: summary))
                } catch {
                    results.append(IntentResult(
                        type: "searchNews",
                        message: i18n.t("error.noNewsResults", lang: effectiveLang),
                        error: "searchError"
                    ))
                }

            default:
                // Action intents — build deep links
                if let result = await deeplinkBuilder.build(intent: intent, lang: effectiveLang, baseCurrency: baseCurrency) {
                    results.append(result)
                }
            }
        }

        // Save to history
        if let conversationId {
            await chatHistory.add(conversationId, role: .user, content: message)
            let summary = results.compactMap(\.message).joined(separator: "\n\n")
            if !summary.isEmpty {
                await chatHistory.add(conversationId, role: .assistant, content: summary)
            }
        }

        return (results, effectiveLang)
    }

    /// Classify only — returns raw intents without processing.
    /// Useful when you want full control over how intents are handled.
    public func classify(
        message: String,
        userAddresses: [any AgentUserAddress] = []
    ) async throws -> ClassificationResult {
        try await intentClassifier.classify(message: message, userAddresses: userAddresses)
    }

    /// Build a deep link for a single intent.
    /// Useful when processing intents individually.
    public func buildDeeplink(intent: Intent, lang: String = "en", baseCurrency: String = "USD") async -> IntentResult? {
        await deeplinkBuilder.build(intent: intent, lang: lang, baseCurrency: baseCurrency)
    }

    /// Clear conversation history for a specific conversation.
    public func clearHistory(conversationId: String) async {
        await chatHistory.clear(conversationId)
    }

    public func replaceHistory(conversationId: String, messages: [ChatMessage]) async {
        await chatHistory.replace(conversationId, with: messages)
    }

    /// Clear all conversation history.
    public func clearAllHistory() async {
        await chatHistory.clearAll()
    }

    /// Parse a raw LLM JSON response into a ClassificationResult.
    /// Useful when you handle the LLM call yourself.
    public static func parseClassification(_ rawJSON: String) throws -> ClassificationResult {
        try IntentClassifier.parse(rawJSON)
    }
}
