import Foundation
import UIAgent
import UIInAppBrowser
import UniversalSearchCore
import UniversalSearchPersistence
import UniversalSearchWalletCore
import WalletContext
import WalletCore

private let persistenceLog = Log("UniversalSearchPersistence")

enum UniversalSearchFeatureAttributeKey {
    static let agentThread = SearchAttributeKey("universal-search.agent-thread")
    static let agentHintID = SearchAttributeKey("universal-search.agent-hint-id")
    static let agentHintCatalogVersion = SearchAttributeKey("universal-search.agent-hint-catalog-version")
    static let isPinned = SearchAttributeKey("universal-search.is-pinned")
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
                    key: UniversalSearchFeatureAttributeKey.agentHintID,
                    value: suggestion.id
                ),
                SearchAttribute(
                    key: UniversalSearchFeatureAttributeKey.agentHintCatalogVersion,
                    value: suggestion.catalogVersion
                ),
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
        try await AgentSearchProvider.shared.loadSuggestions(langCode: langCode)
    }
}

struct UniversalSearchAgentConversationSource: UniversalSearchSource {
    typealias Loader = @Sendable (String?) async throws -> [ApiAgentV2ThreadListItem]

    static let id = SearchSourceID("feature:agent-conversation")
    let sourceID = Self.id
    var scoping: UniversalSearchSourceScoping { .global }
    private let loader: Loader

    init(loader: @escaping Loader = Self.loadLiveThreads) {
        self.loader = loader
    }

    func snapshot(
        for context: UniversalSearchContext
    ) async throws -> UniversalSearchSourceSnapshot {
        let threads = try await loader(nil)
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            authority: 100,
            generatedAt: Date(),
            documents: try threads.map { try Self.document($0) }
        )
    }

    static func document(
        _ item: ApiAgentV2ThreadListItem,
        matchingQuery: UniversalSearchQuery? = nil
    ) throws -> SearchDocument {
        let thread = item.thread
        let title = thread.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? lang("New Chat")
        let subtitle = (item.preview ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let updatedAt = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            .parse(thread.lastActivityAt))
            ?? (try? Date.ISO8601FormatStyle().parse(thread.lastActivityAt))
            ?? .distantPast
        let threadJSON = String(decoding: try JSONEncoder().encode(thread), as: UTF8.self)
        var fields = [
            SearchField(title, kind: .title),
            SearchField(subtitle, kind: .description),
        ]
        if let matchingQuery {
            // Query-scoped keywords preserve server matches from messages outside the preview
            fields.append(SearchField(
                matchingQuery.text,
                kind: .keyword,
                matchPolicy: matchingQuery.requiresExactIdentifierMatch ? .exact : .text
            ))
        }
        return SearchDocument(
            id: SearchEntityID("agent-chat:\(thread.id)"),
            kind: .agentChat,
            fields: fields,
            attributes: [
                SearchAttribute(key: UniversalSearchFeatureAttributeKey.agentThread, value: threadJSON),
                SearchAttribute(key: UniversalSearchFeatureAttributeKey.title, value: title),
                SearchAttribute(key: UniversalSearchFeatureAttributeKey.subtitle, value: subtitle),
                SearchAttribute(
                    key: UniversalSearchFeatureAttributeKey.isPinned,
                    value: thread.isPinned == true ? "true" : "false"
                ),
                SearchAttribute(
                    key: UniversalSearchFeatureAttributeKey.updatedAt,
                    value: Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(updatedAt)
                ),
            ],
            signals: SearchSignals(
                traits: [.fromHistory],
                interaction: SearchInteractionSignal(
                    lastSelectedAt: updatedAt,
                    selectionCount: 1
                )
            )
        )
    }

    static func loadLiveThreads(query: String?) async throws -> [ApiAgentV2ThreadListItem] {
        guard try await Api.getAgentV2Consent() else { return [] }
        return try await Api.listAgentV2Threads(query: query).threads
    }
}

struct UniversalSearchAgentConversationQuerySource: UniversalSearchQuerySource {
    static let id = SearchSourceID("feature:agent-conversation-query")
    let sourceID = Self.id
    private let loader: UniversalSearchAgentConversationSource.Loader
    private let debounce: Duration

    init(
        loader: @escaping UniversalSearchAgentConversationSource.Loader = UniversalSearchAgentConversationSource.loadLiveThreads,
        debounce: Duration = .milliseconds(250)
    ) {
        self.loader = loader
        self.debounce = debounce
    }

    func snapshots(
        for query: UniversalSearchQuery,
        context: UniversalSearchContext
    ) -> AsyncThrowingStream<UniversalSearchSourceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !query.isEmpty else {
                        continuation.finish()
                        return
                    }
                    try await Task.sleep(for: debounce)
                    let threads = try await loader(query.text)
                    try Task.checkCancellation()
                    continuation.yield(UniversalSearchSourceSnapshot(
                        sourceID: sourceID,
                        authority: 110,
                        generatedAt: Date(),
                        documents: try threads.map {
                            try UniversalSearchAgentConversationSource.document($0, matchingQuery: query)
                        }
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
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
