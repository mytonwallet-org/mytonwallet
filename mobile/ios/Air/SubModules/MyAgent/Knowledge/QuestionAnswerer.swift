import Foundation

/// Answers user questions using knowledge-base context + LLM —
actor QuestionAnswerer {
    private let llm: LLMProvider
    private let knowledgeBase: KnowledgeBase
    private let i18n: I18n

    init(llm: LLMProvider, knowledgeBase: KnowledgeBase, i18n: I18n) {
        self.llm = llm
        self.knowledgeBase = knowledgeBase
        self.i18n = i18n
    }

    /// Answer a question by retrieving relevant docs and prompting the LLM.
    func answer(question: String, history: [ChatMessage] = [], lang: String) async throws -> String {
        let docs = await knowledgeBase.retrieve(question, k: 8)

        let context = docs.isEmpty
            ? "No relevant documentation found."
            : docs.joined(separator: "\n\n---\n\n")

        let langInstruction = lang == "en"
            ? "Answer in English."
            : "Answer in the same language as the user's message."

        let systemPrompt = i18n.t("prompt.qa", lang: lang, args: [
            "context": context,
            "langInstruction": langInstruction,
        ])

        let messages = history + [ChatMessage(role: .user, content: question)]
        let answer = try await llm.generate(systemPrompt: systemPrompt, messages: messages)
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
