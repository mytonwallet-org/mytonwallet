import Foundation
import os.log

/// Classifies user messages into structured intents using an LLM.
///
/// This is the core classifier.
/// It sends the classification prompt to the provided `LLMProvider`, parses the JSON response,
/// and returns structured intents with detected language.
public struct IntentClassifier: Sendable {
    private let llm: LLMProvider
    private static let logger = Logger(subsystem: "MyAgent", category: "IntentClassifier")

    public init(llm: LLMProvider) {
        self.llm = llm
    }

    /// Classify a user message into one or more intents.
    ///
    /// - Parameters:
    ///   - message: The user's natural language message.
    ///   - userAddresses: The user's wallet addresses for context.
    /// - Returns: A `ClassificationResult` with intents and detected language.
    public func classify(
        message: String,
        userAddresses: [any AgentUserAddress] = [],
        savedAddresses: [any AgentUserAddress] = []
    ) async throws -> ClassificationResult {
        let userContent = ClassificationPrompt.userMessage(message, addresses: userAddresses, savedAddresses: savedAddresses)
        let raw = try await llm.generate(systemPrompt: ClassificationPrompt.system, userMessage: userContent)
        #if DEBUG
        Self.logger.debug("[Classifier] Input: \(message, privacy: .public)")
        Self.logger.debug("[Classifier] Raw LLM response: \(raw, privacy: .public)")
        #endif
        let result = try Self.parse(raw)
        #if DEBUG
        for intent in result.intents {
            Self.logger.debug("[Classifier] Intent: type=\(intent.type.rawValue, privacy: .public) to=\(intent.to ?? "null", privacy: .public) token=\(intent.token ?? "null", privacy: .public) amount=\(intent.amount.map { String($0) } ?? "null", privacy: .public)")
        }
        #endif
        return result
    }

    // MARK: - JSON Parsing

    /// Parse LLM response text into a ClassificationResult.
    /// Handles markdown code blocks, raw JSON, single-intent fallback.
    public static func parse(_ text: String) throws -> ClassificationResult {
        let json = try extractJSON(from: text)
        let intents = normalizeIntents(json)
        let lang = (json["lang"] as? String) ?? "en"

        let data = try JSONSerialization.data(withJSONObject: intents)
        let decoded = try JSONDecoder().decode([Intent].self, from: data)

        return ClassificationResult(intents: decoded, detectedLang: lang)
    }

    /// Extract a JSON dictionary from LLM output, handling ```json blocks.
    static func extractJSON(from text: String) throws -> [String: Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let nsText = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Try code block first: ```json ... ```
        if let codeBlockRegex = try? NSRegularExpression(pattern: "```(?:json)?\\s*(\\{[\\s\\S]*?\\})\\s*```", options: [.dotMatchesLineSeparators]),
           let match = codeBlockRegex.firstMatch(in: trimmed, range: fullRange),
           match.numberOfRanges > 1 {
            let jsonRange = match.range(at: 1)
            let jsonStr = nsText.substring(with: jsonRange)
            if let data = jsonStr.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }

        // Try to find raw JSON object
        if let rawRegex = try? NSRegularExpression(pattern: "\\{[\\s\\S]*\\}", options: [.dotMatchesLineSeparators]),
           let match = rawRegex.firstMatch(in: trimmed, range: fullRange) {
            let jsonStr = nsText.substring(with: match.range)
            if let data = jsonStr.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
        }

        throw ClassifierError.noJSONFound(text)
    }

    /// Normalize: if "intents" array exists use it, otherwise treat the whole dict as a single intent.
    static func normalizeIntents(_ data: [String: Any]) -> [[String: Any]] {
        if let intents = data["intents"] as? [[String: Any]] {
            return intents
        }
        // Fallback: LLM returned a single intent object
        return [data]
    }
}

public enum ClassifierError: LocalizedError {
    case noJSONFound(String)

    public var errorDescription: String? {
        switch self {
        case .noJSONFound(let text):
            return "No JSON found in classifier response: \(text.prefix(200))"
        }
    }
}
