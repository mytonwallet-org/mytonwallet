import Foundation
import Testing
import UIUniversalSearch
import UniversalSearchCore
import UniversalSearchWalletCore
@testable import UniversalSearchFeature

@MainActor
@Suite("Universal Search action composition")
struct UniversalSearchActionCompositionTests {
    private let context = UniversalSearchContext(
        scopeID: "account",
        network: "mainnet",
        localeIdentifier: "en"
    )

    @Test
    func `URL input promotes open website ahead of agent and Google`() throws {
        let presentation = UniversalSearchResultsPresenter(resolver: { _, _ in nil })
            .presentation(for: emptySnapshot(query: "fragment.com/collection"), context: context)

        #expect(presentation.sections.map(\.id) == [
            "open-website", "ask-agent", "search-google",
        ])
        #expect(presentation.preselectedItemID?.hasPrefix("web-action:open:") == true)
        let route = try #require(
            presentation.preselectedItemID.flatMap { presentation.routesByItemID[$0] }
        )
        guard case .website(let url, _) = route else {
            Issue.record("Expected an open website route")
            return
        }
        #expect(url.absoluteString == "https://fragment.com/collection")
    }

    @Test
    func `unknown text offers unselected agent and Google fallbacks`() {
        let presentation = UniversalSearchResultsPresenter(resolver: { _, _ in nil })
            .presentation(for: emptySnapshot(query: "tondfjnhdjsf"), context: context)

        #expect(presentation.sections.map(\.id) == ["ask-agent", "search-google"])
        #expect(presentation.preselectedItemID == nil)
    }

    @Test
    func `ordinary results retain Agent and Google fallbacks`() throws {
        let document = SearchDocument(
            id: SearchEntityID("application:fragment"),
            kind: .application,
            fields: [SearchField("Fragment", kind: .title)],
            attributes: [SearchAttribute(
                key: WalletCoreSearchAttributeKey.url,
                value: "https://fragment.com"
            )]
        )
        let presentation = UniversalSearchResultsPresenter().presentation(
            for: snapshot(query: "frag", document: document),
            context: context
        )

        #expect(presentation.sections.map(\.id) == [
            "top-hit", "ask-agent", "search-google",
        ])
        #expect(presentation.preselectedItemID == document.id.rawValue)
        #expect(presentation.routesByItemID["agent-action:frag"] != nil)
        #expect(presentation.routesByItemID["web-action:google:frag"] != nil)
    }

    @Test
    func `conversational text promotes agent`() {
        let presentation = UniversalSearchResultsPresenter(resolver: { _, _ in nil })
            .presentation(for: emptySnapshot(query: "Send 10 USDT to mom"), context: context)

        #expect(presentation.preselectedItemID == "agent-action:send 10 usdt to mom")
        guard case .some(.agent(let query, let entryPoint)) = presentation.routesByItemID[
            "agent-action:send 10 usdt to mom"
        ] else {
            Issue.record("Expected an Agent route")
            return
        }
        #expect(query == "Send 10 USDT to mom")
        #expect(entryPoint == .agentTab)
    }

    @Test(arguments: ["staking risks", "неизвестные слова", "  staking\nrisks  "])
    func `unmatched multiword text selects Agent in any language`(query: String) {
        let presentation = UniversalSearchResultsPresenter(resolver: { _, _ in nil })
            .presentation(for: emptySnapshot(query: query), context: context)

        #expect(presentation.sections.map(\.id) == ["ask-agent", "search-google"])
        #expect(presentation.preselectedItemID == presentation.sections.first?.items.first?.id)
    }

    @Test
    func `website and search intent parsing stays distinct`() throws {
        guard case .openWebsite(let url, let displayText) = UniversalSearchWebIntent(
            "https://fragment.com/path?q=1"
        ) else {
            Issue.record("Expected a website intent")
            return
        }
        #expect(url.host == "fragment.com")
        #expect(displayText == "fragment.com/path?q=1")

        guard case .searchGoogle(let query) = UniversalSearchWebIntent("fragment website") else {
            Issue.record("Expected a Google intent")
            return
        }
        #expect(query == "fragment website")
    }

    @Test
    func `chain DNS name is searched rather than opened as a website`() {
        guard case .searchGoogle(let query) = UniversalSearchWebIntent("mwme.ton") else {
            Issue.record("Expected a chain DNS name to remain a search intent")
            return
        }
        #expect(query == "mwme.ton")

        guard case .searchGoogle(let explicitQuery) = UniversalSearchWebIntent(
            "https://mwme.ton/path"
        ) else {
            Issue.record("Expected a chain DNS URL to remain a search intent")
            return
        }
        #expect(explicitQuery == "https://mwme.ton/path")
    }

    @Test
    func `lookalike Google hosts are not interpreted as search history`() throws {
        let maliciousPrefix = try #require(
            URL(string: "https://google.evil.example/search?q=fragment")
        )
        let maliciousWWWPrefix = try #require(
            URL(string: "https://www.google.evil.example/search?q=fragment")
        )

        #expect(UniversalSearchWebIntent.googleSearchQuery(from: maliciousPrefix) == nil)
        #expect(UniversalSearchWebIntent.googleSearchQuery(from: maliciousWWWPrefix) == nil)
    }

    @Test
    func `missing agent conversation keeps starter metadata and opens a start row without a query`() async throws {
        let source = UniversalSearchAgentSuggestionSource { _ in
            [
                .init(
                    id: "portfolio.performance",
                    catalogVersion: "agent-starter-hints-v1",
                    title: "Track my portfolio",
                    prompt: "Analyze my wallet portfolio and explain what stands out."
                )
            ]
        }
        let sourceSnapshot = try await source.snapshot(for: context)
        let browse = UniversalSearchBrowseSnapshot(
            recentDocuments: [],
            trendingDocuments: sourceSnapshot.documents,
            corpusRevision: 1,
            corpusDocumentCount: 1,
            generatedAt: Date(timeIntervalSince1970: 1)
        )
        let presentation = UniversalSearchResultsPresenter().browsePresentation(
            for: browse,
            context: context
        )
        let emptyConversationChats = try #require(presentation.sections.first)
        let startItem = try #require(emptyConversationChats.items.first)
        guard case .chat = startItem.content else {
            Issue.record("Expected the empty conversation action to use the chat row")
            return
        }
        #expect(emptyConversationChats.items.count == 1)
        let suggestions = try #require(presentation.sections.dropFirst().first)
        #expect(suggestions.id == "agent-suggestions")
        #expect(suggestions.items.map(\.id) == ["agent-suggestion:portfolio.performance"])
        guard case .some(.agent(let prompt, let hintEntryPoint)) = presentation
            .routesByItemID["agent-suggestion:portfolio.performance"] else {
            Issue.record("Expected a starter hint route")
            return
        }
        #expect(prompt == "Analyze my wallet portfolio and explain what stands out.")
        #expect(hintEntryPoint == .emptyState(hintId: "portfolio.performance", catalogVersion: "agent-starter-hints-v1"))
        guard case .some(.agent(let emptyConversationQuery, let entryPoint)) = presentation
            .routesByItemID[startItem.id] else {
            Issue.record("Expected the empty conversation row to open Agent")
            return
        }
        #expect(emptyConversationQuery == nil)
        #expect(entryPoint == .agentTab)
    }

    @Test
    func `localized starter and identical typed question preserve their respective origins`() async throws {
        let source = UniversalSearchAgentSuggestionSource { _ in
            [
                .init(
                    id: "learn.security",
                    catalogVersion: "catalog-from-server",
                    title: "Безопасность кошелька",
                    prompt: "Расскажи, как защитить мой кошелёк."
                )
            ]
        }
        let sourceSnapshot = try await source.snapshot(for: context)
        let document = try #require(sourceSnapshot.documents.first)
        let presenter = UniversalSearchResultsPresenter()
        let browse = presenter.browsePresentation(
            for: UniversalSearchBrowseSnapshot(
                recentDocuments: [],
                trendingDocuments: sourceSnapshot.documents,
                corpusRevision: 1,
                corpusDocumentCount: 1,
                generatedAt: Date(timeIntervalSince1970: 1)
            ),
            context: context
        )
        guard case .some(.agent(let prompt, let entryPoint)) = browse.routesByItemID[document.id.rawValue] else {
            Issue.record("Expected the localized starter hint route")
            return
        }
        #expect(prompt == "Расскажи, как защитить мой кошелёк.")
        #expect(entryPoint == .emptyState(hintId: "learn.security", catalogVersion: "catalog-from-server"))

        let typed = presenter.presentation(
            for: snapshot(query: "Расскажи, как защитить мой кошелёк.", document: document),
            context: context
        )
        let askAgent = try #require(typed.sections.first { $0.id == "ask-agent" }?.items.first)
        guard case .some(.agent(let typedPrompt, let typedEntryPoint)) = typed.routesByItemID[askAgent.id] else {
            Issue.record("Expected the typed question route")
            return
        }
        #expect(typedPrompt == "Расскажи, как защитить мой кошелёк.")
        #expect(typedEntryPoint == .agentTab)
    }

    private func emptySnapshot(query: String) -> UniversalSearchResultSnapshot {
        UniversalSearchResultSnapshot(
            query: UniversalSearchQuery(query),
            hits: [],
            totalHitCount: 0,
            corpusRevision: 0,
            rankingPolicyVersion: "test",
            generatedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func snapshot(
        query: String,
        document: SearchDocument
    ) -> UniversalSearchResultSnapshot {
        let searchQuery = UniversalSearchQuery(query)
        return UniversalSearchResultSnapshot(
            query: searchQuery,
            hits: [makeSearchHit(document)],
            totalHitCount: 1,
            corpusRevision: 1,
            rankingPolicyVersion: "test",
            generatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
