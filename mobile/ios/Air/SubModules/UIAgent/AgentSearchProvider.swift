@preconcurrency import Combine
import Foundation
import WalletContext
import WalletCore

public struct AgentSuggestion: Hashable, Sendable {
    public let id: String
    public let catalogVersion: String
    public let title: String
    public let prompt: String

    public init(id: String, catalogVersion: String, title: String, prompt: String) {
        self.id = id
        self.catalogVersion = catalogVersion
        self.title = title
        self.prompt = prompt
    }
}

public struct AgentConversationSearchSnapshot: Sendable {
    public let title: String
    public let subtitle: String
    public let searchableMessages: [String]
    public let updatedAt: Date

    public init(
        title: String,
        subtitle: String,
        searchableMessages: [String],
        updatedAt: Date
    ) {
        self.title = title
        self.subtitle = subtitle
        self.searchableMessages = searchableMessages
        self.updatedAt = updatedAt
    }
}

@MainActor
public final class AgentSearchProvider {
    private struct SuggestionCacheEntry {
        let suggestions: [AgentSuggestion]
        let loadedAt: Date
    }

    private struct ConversationTitleCacheEntry {
        let threadId: String
        let clearedAt: String?
        let message: SearchMessage
    }

    public static let shared = AgentSearchProvider()

    private static let suggestionCacheLifetime: TimeInterval = 10 * 60
    private static let conversationMessageLimit = 50
    private static let indexedMessageLimit = 20

    private let conversationChangedSubject = PassthroughSubject<Void, Never>()
    private var suggestionCacheByLanguage: [String: SuggestionCacheEntry] = [:]
    private var conversationTitleCache: ConversationTitleCacheEntry?

    public var conversationChanged: AnyPublisher<Void, Never> {
        conversationChangedSubject.eraseToAnyPublisher()
    }

    private init() {}

    public func loadSuggestions(langCode: String) async throws -> [AgentSuggestion] {
        let langCode = langCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = suggestionCacheByLanguage[langCode],
           Date().timeIntervalSince(cached.loadedAt) < Self.suggestionCacheLifetime {
            return cached.suggestions
        }

        let response = try await Api.getAgentV2Hints(langCode: langCode.isEmpty ? nil : langCode)
        let suggestions = response.items.map { item in
            let prompt = AgentV2Copy.hint(item.id)
            return AgentSuggestion(
                id: item.id.rawValue,
                catalogVersion: response.catalogVersion,
                title: prompt.title,
                prompt: prompt.prompt
            )
        }
        suggestionCacheByLanguage[langCode] = SuggestionCacheEntry(
            suggestions: suggestions,
            loadedAt: Date()
        )
        return suggestions
    }

    public func loadConversationSearchSnapshot() async -> AgentConversationSearchSnapshot? {
        guard (try? await Api.getAgentV2Consent()) == true,
              let defaultThread = try? await Api.getAgentV2DefaultThread() else {
            return nil
        }
        let thread = defaultThread.thread
        guard thread.messageCount > 0 else {
            conversationTitleCache = nil
            return nil
        }
        guard let hydration = try? await Api.getAgentV2Messages(
            threadId: thread.id,
            cursor: nil,
            limit: Self.conversationMessageLimit
        ),
              Self.isValidHydration(hydration, thread: thread),
              let titleMessage = await loadConversationTitle(
                  thread: thread,
                  initialHydration: hydration
              ) else {
            return nil
        }
        return Self.makeConversationSearchSnapshot(hydration, titleMessage: titleMessage)
    }

    func notifyConversationChanged() {
        conversationChangedSubject.send()
    }

    func invalidateConversationTitle() {
        conversationTitleCache = nil
    }

    static func makeSearchPreviewText(_ text: String) -> String {
        guard let attributedText = try? AttributedString(markdown: text) else { return text }
        return String(attributedText.characters)
    }

    private static func makeConversationSearchSnapshot(
        _ hydration: ApiAgentV2ThreadHydration,
        titleMessage: SearchMessage
    ) -> AgentConversationSearchSnapshot? {
        let messages = hydration.messages.compactMap(SearchMessage.init)
        guard let updatedAt = resolveUpdatedAt(thread: hydration.thread, messages: messages) else {
            return nil
        }
        let subtitle = messages.reversed().first {
            $0.id != titleMessage.id
        }?.text ?? lang("Agent")
        return AgentConversationSearchSnapshot(
            title: makeSearchPreviewText(titleMessage.text),
            subtitle: makeSearchPreviewText(subtitle),
            searchableMessages: messages.suffix(indexedMessageLimit).map(\.text),
            updatedAt: updatedAt
        )
    }

    private func loadConversationTitle(
        thread: ApiAgentV2ThreadSummary,
        initialHydration: ApiAgentV2ThreadHydration
    ) async -> SearchMessage? {
        if let cached = conversationTitleCache,
           cached.threadId == thread.id,
           cached.clearedAt == thread.clearedAt {
            return cached.message
        }

        var hydration = initialHydration
        var firstUserMessage: SearchMessage?
        var visitedCursors = Set<String>()
        while true {
            let messages = hydration.messages.compactMap(SearchMessage.init)
            if let userMessage = messages.first(where: { $0.role == .user }) {
                firstUserMessage = userMessage
            }
            guard let cursor = hydration.nextCursor else { break }
            guard visitedCursors.insert(cursor).inserted,
                  let olderHydration = try? await Api.getAgentV2Messages(
                      threadId: thread.id,
                      cursor: cursor,
                      limit: Self.conversationMessageLimit
                  ),
                  Self.isValidHydration(olderHydration, thread: thread) else {
                return nil
            }
            hydration = olderHydration
        }

        guard let firstUserMessage else { return nil }
        conversationTitleCache = ConversationTitleCacheEntry(
            threadId: thread.id,
            clearedAt: thread.clearedAt,
            message: firstUserMessage
        )
        return firstUserMessage
    }

    private static func isValidHydration(
        _ hydration: ApiAgentV2ThreadHydration,
        thread: ApiAgentV2ThreadSummary
    ) -> Bool {
        hydration.thread.id == thread.id
            && hydration.thread.clearedAt == thread.clearedAt
            && hydration.messages.allSatisfy { $0.threadId == thread.id }
    }

    private static func resolveUpdatedAt(
        thread: ApiAgentV2ThreadSummary,
        messages: [SearchMessage]
    ) -> Date? {
        let threadDate = AgentV2DateParser.date(thread.lastActivityAt)
        if threadDate != .distantPast {
            return threadDate
        }
        return messages.last(where: { $0.createdAt != .distantPast })?.createdAt
    }

    private struct SearchMessage {
        let id: String
        let role: ApiAgentV2MessageRole
        let text: String
        let createdAt: Date

        @MainActor
        init?(_ message: ApiAgentV2PersistedMessage) {
            guard let text = AgentSearchProvider.makeSearchText(message.content) else { return nil }
            id = message.id
            role = message.role
            self.text = text
            createdAt = AgentV2DateParser.date(message.createdAt)
        }
    }

    private static func makeSearchText(_ content: ApiAgentV2MessageContent?) -> String? {
        let text: String?
        switch content {
        case .markdown(let markdown):
            text = markdown
        case .composedMarkdown(let content):
            text = AgentV2AnswerTables.text(content.text, tables: content.tables, references: content.tableReferences)
        case .semantic(.notice(let notice)):
            text = AgentV2Copy.notice(notice)
        case .semantic(.clientUnsupported), nil:
            text = nil
        }
        let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

}
