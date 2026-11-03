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

@MainActor
public final class AgentSearchProvider {
    private struct SuggestionCacheEntry {
        let suggestions: [AgentSuggestion]
        let loadedAt: Date
    }

    public static let shared = AgentSearchProvider()

    private static let suggestionCacheLifetime: TimeInterval = 10 * 60

    private let conversationChangedSubject = PassthroughSubject<Void, Never>()
    private var suggestionCacheByLanguage: [String: SuggestionCacheEntry] = [:]

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

    func notifyConversationChanged() {
        conversationChangedSubject.send()
    }
}
