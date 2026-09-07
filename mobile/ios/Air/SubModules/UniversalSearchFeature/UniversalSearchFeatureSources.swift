import Foundation
import UIAgent
import UIInAppBrowser
import UniversalSearchCore
import UniversalSearchPersistence
import UniversalSearchWalletCore
import WalletContext

private let persistenceLog = Log("UniversalSearchPersistence")

enum UniversalSearchFeatureAttributeKey {
    static let query = SearchAttributeKey("universal-search.query")
    static let subtitle = SearchAttributeKey("universal-search.subtitle")
    static let title = SearchAttributeKey("universal-search.title")
    static let updatedAt = SearchAttributeKey("universal-search.updated-at")
}

struct UniversalSearchAgentSuggestionSource: UniversalSearchSource {
    typealias Loader = @Sendable (String) async throws -> [AgentSuggestion]

    static let id = SearchSourceID("feature:agent-suggestions")
    let sourceID = Self.id
    var scoping: UniversalSearchSourceScoping { .global }
    private let loader: Loader

    init(loader: @escaping Loader = Self.loadLiveSuggestions) {
        self.loader = loader
    }

    func snapshot(
        for context: UniversalSearchContext
    ) async throws -> UniversalSearchSourceSnapshot {
        let suggestions = try await loader(context.localeIdentifier)
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            authority: 100,
            generatedAt: Date(),
            documents: suggestions.enumerated().map { rank, suggestion in
                Self.document(rank: rank, suggestion: suggestion)
            }
        )
    }

    private static func document(
        rank: Int,
        suggestion: AgentSuggestion
    ) -> SearchDocument {
        SearchDocument(
            id: SearchEntityID("agent-suggestion:\(suggestion.id)"),
            kind: .agentAction,
            fields: [
                SearchField(suggestion.title, kind: .title),
                SearchField(suggestion.prompt, kind: .keyword),
            ],
            attributes: [
                SearchAttribute(
                    key: UniversalSearchFeatureAttributeKey.title,
                    value: suggestion.title
                ),
                SearchAttribute(
                    key: UniversalSearchFeatureAttributeKey.query,
                    value: suggestion.prompt
                ),
            ],
            signals: SearchSignals(recommendation: SearchRankedSignal(
                source: id,
                rank: rank + 1,
                generatedAt: Date(),
                reason: "agent-hint"
            ))
        )
    }

    private static func loadLiveSuggestions(langCode: String) async throws -> [AgentSuggestion] {
        try await AgentSuggestionProvider.suggestions(langCode: langCode)
    }
}

struct UniversalSearchAgentConversationSource: UniversalSearchSource {
    typealias Loader = @Sendable () async -> AgentConversationSearchSnapshot?

    static let id = SearchSourceID("feature:agent-conversation")
    let sourceID = Self.id
    var scoping: UniversalSearchSourceScoping { .global }
    private let loader: Loader

    init(loader: @escaping Loader = Self.loadLiveSnapshot) {
        self.loader = loader
    }

    func snapshot(
        for context: UniversalSearchContext
    ) async throws -> UniversalSearchSourceSnapshot {
        let snapshot = await loader()
        let documents = snapshot.map { [Self.document($0)] } ?? []
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            authority: 100,
            generatedAt: Date(),
            documents: documents
        )
    }

    private static func document(
        _ snapshot: AgentConversationSearchSnapshot
    ) -> SearchDocument {
        var fields = [
            SearchField(snapshot.title, kind: .title),
            SearchField(snapshot.subtitle, kind: .description),
        ]
        fields.append(contentsOf: snapshot.searchableMessages.map {
            SearchField($0, kind: .keyword)
        })
        return SearchDocument(
            id: SearchEntityID("agent-chat:current"),
            kind: .agentChat,
            fields: fields,
            attributes: [
                SearchAttribute(key: UniversalSearchFeatureAttributeKey.title, value: snapshot.title),
                SearchAttribute(key: UniversalSearchFeatureAttributeKey.subtitle, value: snapshot.subtitle),
                SearchAttribute(
                    key: UniversalSearchFeatureAttributeKey.updatedAt,
                    value: snapshot.updatedAt.ISO8601Format()
                ),
            ],
            signals: SearchSignals(
                traits: [.fromHistory],
                interaction: SearchInteractionSignal(
                    lastSelectedAt: snapshot.updatedAt,
                    selectionCount: 1
                )
            )
        )
    }

    private static func loadLiveSnapshot() async -> AgentConversationSearchSnapshot? {
        await MainActor.run {
            AgentStore.shared.conversationSearchSnapshot()
        }
    }
}

struct UniversalSearchBrowserHistorySource: UniversalSearchSource {
    typealias Loader = @Sendable () async -> [BrowserHistoryItem]

    static let id = SearchSourceID("feature:browser-history")
    static let historyTag = "explore"

    let sourceID = Self.id
    var scoping: UniversalSearchSourceScoping { .global }
    private let loader: Loader

    init(loader: @escaping Loader = Self.loadLiveHistory) {
        self.loader = loader
    }

    func snapshot(
        for context: UniversalSearchContext
    ) async throws -> UniversalSearchSourceSnapshot {
        let items = await loader()
            .filter { $0.tag == Self.historyTag }
            .sorted { $0.visitDate > $1.visitDate }
        var documentsByID: [SearchEntityID: SearchDocument] = [:]
        for (index, item) in items.enumerated() {
            guard let document = Self.document(for: item, rank: index + 1),
                  documentsByID[document.id] == nil else {
                continue
            }
            documentsByID[document.id] = document
        }
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            authority: 100,
            generatedAt: Date(),
            documents: documentsByID.values.sorted { $0.id < $1.id }
        )
    }

    static func document(for item: BrowserHistoryItem, rank: Int) -> SearchDocument? {
        guard let url = URL(string: item.url) else { return nil }
        let recommendation = SearchRankedSignal(
            source: id,
            rank: rank,
            generatedAt: item.visitDate,
            reason: "browser-history"
        )
        let interaction = SearchInteractionSignal(
            lastSelectedAt: item.visitDate,
            selectionCount: 1
        )

        if let query = UniversalSearchWebIntent.googleSearchQuery(from: url) {
            return SearchDocument(
                id: SearchEntityID("web-search-history:\(query.lowercased())"),
                kind: .webSearchHistory,
                fields: [
                    SearchField(query, kind: .title),
                    SearchField(query, kind: .keyword),
                ],
                attributes: [
                    SearchAttribute(key: UniversalSearchFeatureAttributeKey.query, value: query),
                    SearchAttribute(
                        key: UniversalSearchFeatureAttributeKey.updatedAt,
                        value: item.visitDate.ISO8601Format()
                    ),
                ],
                signals: SearchSignals(
                    traits: [.fromHistory],
                    interaction: interaction,
                    recommendation: recommendation
                )
            )
        }

        let host = url.host(percentEncoded: false) ?? url.host ?? item.url
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? host
            : item.title
        return SearchDocument(
            id: SearchEntityID("site:\(canonicalURLString(url))"),
            kind: .site,
            fields: [
                SearchField(title, kind: .title),
                SearchField(host, kind: .domain),
                SearchField(item.url, kind: .url),
            ],
            attributes: [
                SearchAttribute(key: WalletCoreSearchAttributeKey.url, value: item.url),
                SearchAttribute(key: UniversalSearchFeatureAttributeKey.title, value: title),
                SearchAttribute(
                    key: UniversalSearchFeatureAttributeKey.updatedAt,
                    value: item.visitDate.ISO8601Format()
                ),
            ],
            signals: SearchSignals(
                traits: [.fromHistory],
                interaction: interaction,
                recommendation: recommendation
            )
        )
    }

    private static func canonicalURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if components.path == "/" {
            components.path = ""
        }
        return components.string ?? url.absoluteString.lowercased()
    }

    private static func loadLiveHistory() async -> [BrowserHistoryItem] {
        await MainActor.run { BrowserHistoryStore.shared.items }
    }
}

public enum UniversalSearchFeatureFactory {
    private static let sharedIndexStore: (any UniversalSearchIndexStore)? = {
        do {
            return try GRDBUniversalSearchIndexStore()
        } catch {
            persistenceLog.error(
                "failed to open index error=\(String(describing: error), .public)"
            )
            return nil
        }
    }()

    public static let sharedCoordinator = makeCoordinator(indexStore: sharedIndexStore)
    @MainActor public static let sharedIndexService = UniversalSearchIndexService(
        coordinator: sharedCoordinator
    )

    static func makeCoordinator(
        rankingPolicy: UniversalSearchRankingPolicy = .initial,
        indexStore: (any UniversalSearchIndexStore)? = nil
    ) -> UniversalSearchCoordinator {
        UniversalSearchCoordinator(
            sources: WalletCoreUniversalSearchFactory.makeSources() + [
                UniversalSearchAppEntrySource(),
                UniversalSearchAgentSuggestionSource(),
                UniversalSearchAgentConversationSource(),
                UniversalSearchBrowserHistorySource(),
            ],
            engine: UniversalSearchEngine(policy: rankingPolicy),
            indexStore: indexStore,
            persistedSourceIDs: [
                WalletCoreTokenSearchSource.id,
                WalletCoreWalletSearchSource.id,
                WalletCoreConnectedAppSearchSource.id,
            ]
        )
    }
}
