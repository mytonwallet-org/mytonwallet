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
        guard case .some(.agent(let query)) = presentation.routesByItemID[
            "agent-action:send 10 usdt to mom"
        ] else {
            Issue.record("Expected an Agent route")
            return
        }
        #expect(query == "Send 10 USDT to mom")
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
    func `missing agent conversation uses a start row without a pending query`() throws {
        let suggestion = SearchDocument(
            id: SearchEntityID("agent-suggestion:portfolio"),
            kind: .agentAction,
            fields: [SearchField("Track my portfolio", kind: .title)],
            attributes: [
                SearchAttribute(
                    key: UniversalSearchFeatureAttributeKey.title,
                    value: "Track my portfolio"
                ),
                SearchAttribute(
                    key: UniversalSearchFeatureAttributeKey.query,
                    value: "Analyze my wallet portfolio and explain what stands out."
                ),
            ]
        )
        let browse = UniversalSearchBrowseSnapshot(
            recentDocuments: [],
            trendingDocuments: [suggestion],
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
        #expect(suggestions.items.map(\.id) == ["agent-suggestion:portfolio"])
        guard case .some(.agent(let emptyConversationQuery)) = presentation
            .routesByItemID[startItem.id] else {
            Issue.record("Expected the empty conversation row to open Agent")
            return
        }
        #expect(emptyConversationQuery == nil)
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
