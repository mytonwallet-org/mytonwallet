import Foundation

/// Protocol for plugging in any LLM backend (local CoreML, Ollama, OpenAI, etc.).
///
/// Implement this protocol to provide the LLM that powers intent classification.
/// The classifier sends a system prompt and user message, expecting a JSON response.
public protocol LLMProvider: Sendable {
    /// Send a system + user message pair to the LLM and return the raw text response.
    ///
    /// - Parameters:
    ///   - systemPrompt: The classification system prompt.
    ///   - userMessage: The user's message with optional address context.
    /// - Returns: The LLM's raw text response (expected to be JSON).
    func generate(systemPrompt: String, userMessage: String) async throws -> String

    /// Send a system prompt with a multi-turn conversation to the LLM.
    ///
    /// Used for history-aware Q&A and news answering. The messages array contains
    /// prior conversation turns followed by the current user message.
    ///
    /// Default implementation ignores history and calls the single-turn method.
    func generate(systemPrompt: String, messages: [ChatMessage]) async throws -> String
}

extension LLMProvider {
    /// Default: extract the last user message and fall back to single-turn.
    public func generate(systemPrompt: String, messages: [ChatMessage]) async throws -> String {
        let userMessage = messages.last(where: { $0.role == .user })?.content ?? ""
        return try await generate(systemPrompt: systemPrompt, userMessage: userMessage)
    }
}
